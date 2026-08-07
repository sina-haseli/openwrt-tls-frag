# openwrt-tls-frag

**[فارسی](README.fa.md)**

Unblock YouTube and Instagram on an OpenWrt router by splitting the TLS
ClientHello across TCP segments, so the censor's inspector never sees a complete
SNI. The connection then goes **directly** to the real server. No proxy server,
no VPN, no bandwidth cost, nothing to pay for, nothing to lose access to.

This packages a configuration that has been running on a production home router
since 2026-08-06.

## Credits

The fragment parameters come from
**[patterniha/Serverless-for-Iran](https://github.com/patterniha/Serverless-for-Iran)**
(GPL-3.0), by way of its `Serverless-v48-low_delay` v2rayN configuration. Those
specific values are the whole trick — this project would not exist without that
work. If this is useful to you, go star that repository.

What this project adds is packaging: an OpenWrt installer, Passwall2
integration, a standalone transparent-proxy mode, and verification that actually
proves the fragmentation is doing the work.

## Honest limitations — read before installing

- **YouTube and Instagram only.** The shipped domain list covers those two.
- **x.com does not work** with this technique. Out of scope.
- **Not a VPN replacement.** Everything else on your connection is unaffected.
- **Verified on Iranian ISPs**, on OpenWrt 25.12.5 aarch64 with Xray 26.7.28.
  The fragment parameters are tuned to one inspector's behaviour. On other
  networks they may need adjusting — see [docs/how-it-works.md](docs/how-it-works.md)
  so you can adapt them rather than guess.
- **Standalone mode requires clients to resolve DNS through the router.** It is
  verified working (see [docs/standalone-test-log.md](docs/standalone-test-log.md)),
  but it redirects by IP address, and it only learns which addresses to redirect
  by watching the router's dnsmasq answer queries. A client using browser DoH/DoT,
  a VPN adapter's resolver, or a hardcoded public DNS will bypass the redirect
  entirely. Passwall2 mode does not have this constraint.

## Requirements

| | |
|---|---|
| OpenWrt | 22.03+ (needs fw4/nftables) |
| Xray-core | **≥ 26.6.27** — below this `finalmask` does not exist and Xray silently does not fragment |
| Free rootfs | ~2 MB |
| Mode A | Passwall2, with a **shunt** node as the global node |
| Mode B | `dnsmasq-full` (plain `dnsmasq` has no `nftset` support) |

Xray is not bundled. Install it first: `apk add xray-core` (or
`opkg install xray-core`).

## Install

One line, on the router, as root:

```sh
curl -fsSL https://raw.githubusercontent.com/sina-haseli/openwrt-tls-frag/master/get.sh | sh
```

It auto-detects: Passwall2 if present, standalone otherwise. To force a mode,
pass arguments after `-s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/sina-haseli/openwrt-tls-frag/master/get.sh | sh -s -- --mode passwall2
curl -fsSL https://raw.githubusercontent.com/sina-haseli/openwrt-tls-frag/master/get.sh | sh -s -- --mode standalone
```

The bootstrap downloads a tarball into `/tmp` (tmpfs), runs the installer, and
deletes itself — nothing is written to flash except the installed files.
OpenWrt has no `git`, which is why this fetches a tarball rather than cloning.

If you would rather read the code before running it — and you should — download
and inspect it first:

```sh
curl -fsSL -o /tmp/get.sh https://raw.githubusercontent.com/sina-haseli/openwrt-tls-frag/master/get.sh
less /tmp/get.sh
sh /tmp/get.sh
```

Or on a machine that does have `git`:

```sh
git clone https://github.com/sina-haseli/openwrt-tls-frag
cd openwrt-tls-frag
./install.sh
```

Options:

| Flag | Effect |
|---|---|
| `--mode auto\|passwall2\|standalone` | default `auto` |
| `--scope-ip <ip>` | standalone only — apply rules to one source IP. For isolated testing. |
| `--no-verify` | skip the post-install check (not recommended) |
| `--no-stats` | do not install the one-minute stats sampler |

### Mode A — Passwall2

Adds a `FRAGDRCT` SOCKS node pointing at the fragmenter, a `FragTCP` shunt rule
routing the YT/IG domains to it, and a `FragUDP` rule blackholing their QUIC so
browsers fall back to the TCP path being fragmented.

The global shunt node's ID is **discovered**, never hardcoded — it is random per
install. If your global node is not a shunt, the installer refuses to touch it
and tells you so, rather than corrupting your routing.

### Mode B — Standalone

For routers with no proxy package. dnsmasq resolves the target domains into an
nftables set; fw4 redirects matching TCP to a `dokodemo-door` inbound and drops
matching QUIC. Read the DNS limitation above first.

## Verify

The installer does not report success because a process started. That check
would have passed for a setup that did nothing — which is a false positive that
actually happened during development, where the traffic was quietly riding a VPN.

Instead it runs a **differential** check. It starts a throwaway Xray on a scratch
port with the same DoH resolver and the same `sockopt.mark 255`, but with the
fragment stages removed, and compares:

```
verify: control https://www.google.com unfragmented = 200 OK
verify: https://www.youtube.com  fragmented=200  unfragmented=000  OK
verify: https://www.instagram.com  fragmented=200  unfragmented=000  OK
verify: PASS - fragmentation is doing the work
```

It passes only if the targets work **through** the fragmenter *and* fail on the
identical path without it. If they work without it too, you are told the install
proves nothing — either the line does not block them, or something else is
carrying the traffic.

Note that `curl --noproxy` is **not** a valid control here: it only disables
curl's env-var proxy handling, not transparent nftables interception. On a
Passwall2 router a "direct" fetch of youtube.com returns 200 while riding the
VPN.

## Uninstall

If you installed with the one-liner, you have no local copy — use the same
bootstrap:

```sh
curl -fsSL https://raw.githubusercontent.com/sina-haseli/openwrt-tls-frag/master/get.sh | sh -s -- --uninstall
```

From a clone:

```sh
./uninstall.sh
```

Stops and disables the service, removes `/etc/xray-frag`,
`/etc/init.d/xray-frag`, `/usr/bin/xray-frag-stats`, the cron line, and any
standalone firewall/dnsmasq rules. It restores the timestamped
`/etc/config/passwall2` backup taken at install time, then strips this project's
UCI sections regardless — so "uninstalled" means gone, even if the box was wired
by hand before.

## Monitoring

```sh
xray-frag-stats now      # RSS, threads, CPU, open connections
xray-frag-stats history  # peaks and the last 20 samples
xray-frag-stats watch    # live
```

History lives in `/tmp` (tmpfs) **on purpose**: no disk writes, no flash wear. It
clears on reboot, and that is the accepted trade — the reference device has only
~36 MB free on rootfs.

## Cost

RSS ~36–42 MB, flat across 30 connections (no leak). 8 threads. ~1–2% average CPU
of one core. ~32 ms CPU per TLS handshake.

Cost scales with **connections/sec, not bandwidth**: `packets: "tlshello"`
fragments only the handshake and `packets: "1-1"` only the first write, so
throughput is untouched. For scale, on the same device Passwall2's own Xray is
~80 MB and its sing-box ~42 MB.

## How it works

[docs/how-it-works.md](docs/how-it-works.md) — the parameters and *why* they are
what they are, the DoH trick, and the dead ends already explored so you do not
repeat them.

[docs/troubleshooting.md](docs/troubleshooting.md) — symptom-first.

## License

MIT — see [LICENSE](LICENSE). Fragment parameters derived from
[patterniha/Serverless-for-Iran](https://github.com/patterniha/Serverless-for-Iran)
(GPL-3.0).
