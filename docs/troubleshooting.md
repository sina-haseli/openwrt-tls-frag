# Troubleshooting

Symptom first. Each entry: what you see → why → how to confirm → what to do.

---

## `install.sh` says xray is too old

**Why:** `streamSettings.finalmask` does not exist before Xray 26.6.27. Older
builds **accept the config and silently do not fragment**, so this is a hard stop
rather than a warning — otherwise you would get a successful-looking install that
does nothing.

**Confirm:**
```sh
xray version
```

**Fix:** `apk add xray-core` (or `opkg install xray-core`), or build ≥ 26.6.27.

---

## Verification fails: targets return 000 *through* the fragmenter

**Why:** the fragmenter is not actually running, or it failed to parse its config.

**Confirm:**
```sh
xray-frag-stats now
logread -e xray-frag
/etc/init.d/xray-frag restart
```

**Fix:** read the log. A JSON syntax error or an unknown field in
`/etc/xray-frag/config.json` will show there.

---

## Verification warns the targets work *without* fragmentation

```
verify: https://www.youtube.com also works WITHOUT fragmentation (200) on the
verify: same mark-255 direct path. It is not blocked on this line, so this
verify: install is not proven to do anything.
```

**Why:** exactly what it says — on the unfragmented control path the target
already returns 200. Either your ISP does not block it, or something is carrying
the traffic that the mark-255 bypass did not escape.

**Confirm:** disable any other VPN or proxy on the router and re-run:
```sh
cd /root/openwrt-tls-frag && . lib/common.sh && . lib/core.sh && . lib/verify.sh && verify_fragment
```

**Fix:** if the site genuinely is not blocked for you, this project has nothing to
do and you do not need it.

---

## YouTube/Instagram break for a few seconds after every reboot

**Why:** start ordering. Passwall2 came up before the fragmenter and pointed at a
SOCKS node that was not listening yet.

**Confirm:**
```sh
ls /etc/rc.d/ | grep -e xray-frag -e passwall2
```
`S94xray-frag` must sort before `S99passwall2`.

**Fix:**
```sh
/etc/init.d/xray-frag enable
```

---

## Passwall2 install refuses: "global node is not a shunt"

**Why:** this installer wires the fragment categories onto a **shunt** node,
because a shunt node is the only place Passwall2 keeps per-domain routing rules.
Your global node is a plain proxy node. Writing to it would corrupt your routing,
so the installer stops instead.

**Confirm:**
```sh
uci get passwall2.@global[0].node
uci get passwall2.$(uci get passwall2.@global[0].node).protocol
```

**Fix:** switch your global node to a shunt node in the Passwall2 UI, or run
`./install.sh --mode standalone`.

---

## Standalone: the nftables set stays empty

**Why, most likely:** your dnsmasq has no `nftset` support, or clients are not
resolving through the router at all.

**Confirm:**
```sh
dnsmasq --help 2>&1 | grep -- --nftset      # must print something
grep -c nftset /etc/dnsmasq.conf            # must be 8
nft list set inet fw4 xrayfrag4
```

**Fix:**
- No `--nftset`: install the full build — `apk add dnsmasq-full` (replacing plain
  `dnsmasq`).
- 0 lines in `/etc/dnsmasq.conf`: re-run `./install.sh --mode standalone`.
- Set exists but empty: flush the client's DNS cache (`ipconfig /flushdns`, or
  `resolvectl flush-caches`) and load the site again. The set only fills when the
  router's dnsmasq answers a query.

Note the set is recreated empty every time `fw4 restart` runs — including during
an install. An empty set immediately after installing is normal; resolve
something first.

---

## Standalone: pages still blocked, and the set has addresses in it

**Why:** the client connected to an address that is not in the set, because that
client resolved the name somewhere other than the router's dnsmasq. Redirection
is by destination IP; an address the router never handed out is never redirected.

Common causes: browser DoH/DoT ("Secure DNS"), a VPN adapter advertising its own
resolver, a hardcoded `8.8.8.8`, or an IPv6 answer (this project handles IPv4
only).

**Confirm:** compare what the client actually connected to against the set.
```sh
# on the client
curl -s -o /dev/null -w "%{remote_ip}\n" https://www.instagram.com
# on the router
nft list set inet fw4 xrayfrag4 | grep <that-ip>
```
Also check the client's DNS servers — on Windows,
`Get-DnsClientServerAddress -AddressFamily IPv4`.

**Fix:** turn off Secure DNS in the browser, disconnect the competing VPN
adapter, or point the client's DNS at the router. If you cannot control the
clients, use Passwall2 mode instead — Xray resolves the domain itself there, so
this constraint does not apply.

---

## Standalone: QUIC still in use

**Why:** the UDP drop rule is not matching, so the browser never falls back to
the TCP path being fragmented.

**Confirm:**
```sh
nft list chain inet fw4 xray_frag_quic
```
The `drop` rule should have a non-zero counter once the site has been loaded.

**Fix:** if the counter is 0, the destination addresses are not in the set — see
the previous entry. Note this chain hooks `forward`, so it covers LAN clients,
not traffic originating on the router itself.

---

## Standalone: was anything redirected at all?

```sh
nft list chain inet fw4 xray_frag_redirect
```

A non-zero counter on the `redirect` rule means traffic reached the fragmenter. A
zero counter means the problem is upstream of the fragmenter — DNS or set
population — not fragmentation.

---

## Windows: curl returns 000 but the connection looked fine

**Why:** Windows schannel may be failing a certificate **revocation** check,
because the revocation responder is itself unreachable on a censored line. The
TCP connection and TLS handshake actually succeeded.

**Confirm:**
```powershell
curl.exe -sv -o NUL https://www.instagram.com
```
Look for `CRYPT_E_REVOCATION_OFFLINE (0x80092013)`.

**Fix:** for testing, `curl.exe --ssl-no-revoke`. Browsers do not usually hit
this. A 000 from curl on Windows is not by itself evidence that the fragmenter
failed.

---

## x.com does not work

Known, and out of scope. This technique does not defeat the block on x.com. Only
YouTube and Instagram are supported.

---

## I want to add more domains

Edit both places for Passwall2 mode:

- `lib/mode_passwall2.sh` → `PW2_DOMAINS` (Xray syntax: `geosite:` / `domain:`)

and for standalone mode:

- `lib/mode_standalone.sh` → `SA_DOMAINS` (bare suffixes only — dnsmasq has no
  concept of `geosite:`)

Then re-run `./install.sh`. A configurable domain list is deliberately out of
scope for v1.
