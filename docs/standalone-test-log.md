# Standalone mode — isolated verification log

**Date:** 2026-08-07
**Verdict:** Standalone mode works. Both YouTube and Instagram were carried by the
transparent redirect + fragmentation path on a line where both are blocked.
One caveat applies to every client (see *Limitation* below) and is not a defect
in the redirect — it is inherent to the DNS-driven nftset approach.

These are the values actually observed, not the expected ones.

## Environment

| | |
|---|---|
| Router | OpenWrt 25.12.5 (r33051-f5dae5ece4), aarch64_generic |
| Xray | 26.7.28 (go1.26.5 linux/arm64) |
| dnsmasq | dnsmasq-full 2.93-r1 (has `--nftset`) |
| Client | Windows 11, 192.168.1.120, curl 8.x with schannel |
| Line | Iranian ISP; YouTube and Instagram blocked by SNI inspection |

## Isolation mechanism

The rest of the LAN kept using the production Passwall2 path throughout.

1. A Passwall2 `acl_rule` matching the test host's MAC (normally `enabled='0'`)
   was enabled, so that one host — and only that host — bypassed Passwall2.
2. The nftables rules were installed with `--scope-ip 192.168.1.120`, so both the
   redirect and the QUIC drop carried `ip saddr 192.168.1.120`.

Confirmed after install: exactly one `ip saddr 192.168.1.120` match in the
redirect chain, 12 other DHCP leases untouched, all 7 Passwall2 processes still
serving them.

## Step 4 — control, before installing standalone mode

With the host off Passwall2 and nothing else in the path:

```
https://www.google.com           200
https://www.youtube.com          000
https://www.instagram.com        000
```

The targets are genuinely blocked for this host. Without this measurement
nothing below would prove anything.

## Step 7 — the nftables set fills

After `ipconfig /flushdns` and resolving the targets against 192.168.1.1, the set
populated. Final size during the test: **56 elements**, including YouTube
(`142.251.15x.4`), googlevideo (`142.251.xxx.119`) and Instagram
(`57.144.148.34`, `179.60.195.174`).

## Step 8 — the measurement

```
https://www.google.com      code=200  ip=142.251.157.119
https://www.youtube.com     code=200  ip=142.251.152.4
https://www.instagram.com   code=000  ip=            <- see Limitation
```

Instagram pinned to an address the router had actually resolved (and therefore
placed in the set):

```
--resolve www.instagram.com:443:57.144.148.34   code=200  ip=57.144.148.34
--resolve www.instagram.com:443:179.60.195.174  code=200  ip=179.60.195.174
```

Both 200. The redirect is what carried them:

```
chain xray_frag_redirect {
    type nat hook prerouting priority dstnat - 5; policy accept;
    meta mark 0x000000ff return
    ip saddr 192.168.1.120 ip daddr @xrayfrag4 tcp dport { 80, 443 } \
        counter packets 58 bytes 3016 redirect to :10809
}
```

QUIC was being dropped as intended, which is what forced the TCP path:

```
ip saddr 192.168.1.120 ip daddr @xrayfrag4 udp dport 443 \
    counter packets 40 bytes 61120 drop
```

Fragmenter cost while serving this: RSS 36 MB, 8 threads, 1% average CPU of one
core, 20 open connections.

## Limitation — clients must resolve through the router

The bare `https://www.instagram.com` fetch returned 000 while the pinned fetches
returned 200. Cause: the test client had a second DNS path. A WireGuard adapter
(`wt0`, Up) advertised its own resolver `redacted`, so some lookups were
answered off-router. Those answers never reach dnsmasq, so their addresses never
enter `xrayfrag4`, so the connection is never redirected and hits the block.

Routing was not the problem — `Find-NetRoute` confirmed 157.240.253.174 egressed
via Ethernet → 192.168.1.1. Only resolution leaked.

This is inherent to the nftset design, not a bug in the rules. Standalone mode
requires that clients resolve through the router's dnsmasq. Anything that
bypasses it — browser DoH/DoT, a VPN adapter's resolver, a hardcoded public DNS
— bypasses the redirect with it. Passwall2 mode does not have this problem
because Xray resolves the domain itself.

## Two defects found and fixed during this test

**1. `/etc/dnsmasq.d/` is never read on OpenWrt.** The nftset lines were
originally written to `/etc/dnsmasq.d/90-xray-frag.conf`. The set stayed empty.
OpenWrt's dnsmasq init generates its own config and passes
`--conf-dir=/tmp/dnsmasq.<section>.d`
(`config_get dnsmasqconfdir "$cfg" confdir "/tmp/dnsmasq${cfg:+.$cfg}.d"`), so
that file is never read; `grep nftset /var/etc/dnsmasq.conf.*` returned nothing.
dnsmasq also runs under ujail with an explicit mount list, so even an absolute
`conf-file=` include pointing there would be unreadable inside the jail.

Fixed by writing a marker-delimited block into `/etc/dnsmasq.conf`, which *is*
included by the generated config and *is* jail-mounted. Confirmed: after the
change the set filled within seconds of the first lookup.

**2. The redirect rule had no `counter`.** "Did anything actually get
redirected" is the first question when standalone mode misbehaves, and it could
not be answered. `counter` added, with a unit test asserting it stays.

## A red herring worth recording

Instagram over the redirect first failed with:

```
schannel: next InitializeSecurityContext failed: CRYPT_E_REVOCATION_OFFLINE
(0x80092013) - The revocation function was unable to check revocation because
the revocation server was offline.
```

The TCP connection and TLS handshake had *succeeded*. Windows schannel was
failing a certificate-revocation lookup, because the revocation responder is
itself unreachable on this line. `curl --ssl-no-revoke` then returned 200.

On Windows, a 000 from curl does not necessarily mean the transport failed.
Check the verbose output before concluding the fragmenter is at fault.

## Revert

Fully reverted and confirmed:

- `/etc/nftables.d/90-xray-frag.nft` — gone
- `/etc/dnsmasq.d/` — gone
- xray-frag block in `/etc/dnsmasq.conf` — 0 lines remaining
- `xrayfrag4` set — gone
- Passwall2 mode reinstalled, `verify: PASS - fragmentation is doing the work`
- `acl_rule[2].enabled` back to `0`; full ACL snapshot compared byte-for-byte
  against the pre-test capture: **identical**
