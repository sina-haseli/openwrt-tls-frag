# How it works

This is the part nobody else wrote down. It covers what the parameters do, why
they are these specific values, and the approaches that fail in ways that look
like the whole technique is impossible.

## The idea

Censors on the target ISPs identify blocked sites by reading the SNI field in the
TLS ClientHello. That field sits in the very first bytes the client sends. If the
ClientHello is split across TCP segments at the right offsets, a stateless
inspector never reassembles a complete SNI and lets the connection through. The
server reassembles it normally, because that is what TCP is for.

So the connection is genuinely **direct**. There is no proxy in the data path,
only a local process that changes *how* the first few bytes are written.

## The fragment parameters

Two stacked stages, in `streamSettings.finalmask.tcp` on a `direct` outbound:

```json
[
  { "type": "fragment", "settings": { "packets": "tlshello", "lengths": ["5", "1"], "delays": ["0"], "maxSplit": "0" } },
  { "type": "fragment", "settings": { "packets": "1-1", "lengths": ["43", "1"], "delays": ["1"], "maxSplit": "522" } }
]
```

| Field | Meaning |
|---|---|
| `packets` | which writes to fragment. `tlshello` = the TLS ClientHello only. `1-1` = the first write only. |
| `lengths` | chunk size range, in bytes, as `[min, max]`. `["5","1"]` is a degenerate range meaning fixed tiny chunks. |
| `delays` | milliseconds to wait between chunks. `1` forces the chunks into separate TCP segments rather than being coalesced. |
| `maxSplit` | cap on how many splits are performed. `"0"` = unlimited. |

Stage one shreds the ClientHello itself. Stage two re-splits the resulting first
write with a 1 ms delay, which is what actually guarantees the pieces leave as
distinct segments instead of being merged by the kernel.

**These values are load-bearing. Copy them byte-for-byte.** They are duplicated
in both `files/etc/xray-frag/config.passwall2.json` and
`files/etc/xray-frag/config.standalone.json` — if you change one, change both.

### Why mild parameters are worse than none

This is the most important thing in this document.

Gentler settings — `lengths` of `10-20` or `100-200`, `maxSplit` of `3`–`6` —
break **all** foreign TLS. `example.com` returns 000. Meanwhile domestic sites
like `digikala.com` keep working perfectly, because their traffic never leaves
the country and is never inspected.

That pattern is extremely convincing: "foreign sites break when I fragment,
domestic sites do not, therefore this ISP drops fragmented ClientHellos and the
technique cannot work here." That conclusion was reached during development and
it is **wrong**. It is a parameter problem, not a capability problem. The values
above work on the same line.

If you are tuning for a different network, do not interpret "all foreign TLS
broke" as a dead end. Interpret it as "wrong parameters."

## Why the instance needs its own DoH resolver

```json
"dns": {
  "hosts": { "cloudflare-dns.com": "challenges.cloudflare.com" },
  "servers": [ { "address": "https://cloudflare-dns.com/dns-query", "timeoutMs": 12000 } ],
  "queryStrategy": "UseIPv4"
}
```

Two independent reasons:

1. **Plain DoH endpoints are blocked.** `1.1.1.1` and `8.8.8.8` DoH do not
   resolve on the target lines. The `hosts` entry points the
   `cloudflare-dns.com` connection at `challenges.cloudflare.com`, a Cloudflare
   front that is not blocked, so the DoH query reaches Cloudflare anyway.
2. **Passwall2 resolves a shunt category's DNS through that category's own
   node.** In Passwall2 mode the fragmenter *is* that node, so it has to be able
   to resolve independently or the lookup deadlocks.

DNS on the reference line is clean and unpoisoned. The custom resolver is needed
for **routing** reasons, not anti-poisoning.

## Why there is no fakedns

Importing `patterniha/Serverless-for-Iran` wholesale fails under Passwall2. Its
fakedns range collides with Passwall2's own `198.18.0.0/15` fakedns, and
Passwall2 rejects the resulting addresses as bogus.

Only the fragment parameters were portable. This project uses **no fakedns at
all**, deliberately. Do not add it back.

## Why `sockopt.mark = 255`

Mark 255 is the OUTPUT-chain bypass mark. Without it, the fragmenter's own egress
is re-captured by the proxy layer and loops back into itself.

You can see the rule Passwall2 relies on:

```
chain PSW2_OUTPUT_MANGLE {
    meta mark 0x000000ff counter return
}
```

In standalone mode the same mark is what the `meta mark 255 return` rule matches,
which is why that rule **must** come before the redirect in the nftables chain.
There is a unit test asserting that ordering.

## Why `START=94`

The procd service starts at 94, before `S99passwall2`. If Passwall2 came up
first, it would boot pointing at a SOCKS node that is not listening yet, and
YouTube/Instagram would fail for the first several seconds after every reboot.

## Why UDP is blackholed

Browsers prefer QUIC over UDP/443. QUIC does not use the TCP path, so it is never
fragmented and goes straight into the block. Killing UDP/443 for the target
domains forces the browser to fall back to TCP, which is the path this project
actually fixes.

- Passwall2 mode: the `FragUDP` shunt category routes to `_blackhole`.
- Standalone mode: an nftables `drop` on `udp dport 443` to the target set.

## Why Passwall2 cannot do this natively

Its fragment/noise options apply only to **proxy** outbounds:

- With sing-box, Passwall2 writes `fragment` inside the outbound's `tls` object,
  which requires `node.tls=1` — meaningless for a direct connection.
- With Xray, `finalmask.tcp` is gated on proxy transports.

And there is no raw-JSON node protocol to escape through. Hence a separate Xray
instance, exposed to Passwall2 as an ordinary SOCKS node.

## Why not sing-box

- `tls_record_fragment` breaks all foreign TLS on this line.
- `tls_fragment` is foreign-safe but does not defeat the YouTube/Instagram block.

Neither is a substitute.

## Standalone mode: the dnsmasq file location

The `nftset=` lines go in **`/etc/dnsmasq.conf`**, not `/etc/dnsmasq.d/`.

`/etc/dnsmasq.d` is the Debian convention and OpenWrt does not use it. OpenWrt's
dnsmasq init generates its own config and passes:

```
--conf-dir=/tmp/dnsmasq.<section>.d
```

(from `config_get dnsmasqconfdir "$cfg" confdir "/tmp/dnsmasq${cfg:+.$cfg}.d"`),
so anything dropped in `/etc/dnsmasq.d` is never read. dnsmasq also runs under
ujail with an explicit mount list, so even an absolute `conf-file=` include
pointing there would be unreadable inside the jail.

`/etc/dnsmasq.conf` is included by the generated config and is jail-mounted, and
OpenWrt ships it containing only comments — it is the intended user extension
point. This project owns a marker-delimited block in it and touches nothing else.

This cost a debugging session; see [standalone-test-log.md](standalone-test-log.md).

## Verification: why the control has to be another Xray

The obvious negative control is "fetch it without the proxy and expect failure."
That does not work, because `curl --noproxy '*'` only disables curl's own
env-var proxy handling. It does nothing about transparent interception. On a
Passwall2 router, `PSW2_OUTPUT_NAT` redirects the router's own TCP to the proxy
core, so a "direct" fetch of youtube.com returns 200 while riding the VPN.

Measured on the reference router:

| path | google | youtube | instagram |
|---|---|---|---|
| `curl --noproxy '*'` | 200 | 200 | 200 |
| mark-255, fragment stages removed | 200 | 000 | 000 |
| mark-255, fragmenter | 200 | 200 | 200 |

So the control is a throwaway Xray on a scratch port: same DoH resolver, same
`sockopt.mark 255`, fragment block removed. The only variable between the two
measured paths is the fragmentation itself, which is what makes the comparison
mean anything.

## Credit

The fragment parameters are from
[patterniha/Serverless-for-Iran](https://github.com/patterniha/Serverless-for-Iran)
(GPL-3.0), specifically its `Serverless-v48-low_delay` v2rayN configuration,
which works on Windows against the same ISPs. Everything above is an explanation
of *why* those values work and how to carry them onto OpenWrt — the values
themselves are that project's contribution.
