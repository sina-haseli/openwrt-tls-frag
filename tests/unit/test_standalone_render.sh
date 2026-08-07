#!/bin/sh
set -u
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/core.sh"
. "$ROOT/lib/mode_standalone.sh"

NFT=$(sa_render_nft)

assert_contains "$NFT" "set xrayfrag4"           "declares the ipv4 set"
assert_contains "$NFT" "type ipv4_addr"          "set holds addresses"
assert_contains "$NFT" "redirect to :10809"      "redirects to the dokodemo port"
assert_contains "$NFT" "@xrayfrag4"              "matches on the set"
assert_contains "$NFT" "meta mark 255 return"    "exempts marked traffic"
assert_contains "$NFT" "udp dport 443"           "drops QUIC"

# Loop prevention must come BEFORE the redirect, or the fragmenter's own
# egress gets redirected back into itself.
MARK_LINE=$(printf '%s\n' "$NFT" | grep -n "meta mark 255 return" | head -1 | cut -d: -f1)
REDIR_LINE=$(printf '%s\n' "$NFT" | grep -n "redirect to :10809" | head -1 | cut -d: -f1)
if [ "$MARK_LINE" -lt "$REDIR_LINE" ]; then
	t_pass "mark-255 return precedes the redirect"
else
	t_fail "mark-255 return precedes the redirect (mark@$MARK_LINE redirect@$REDIR_LINE)"
fi

# --- unscoped rules must not carry a source filter ---
case "$NFT" in
	*"ip saddr"*) t_fail "unscoped render has no saddr filter" ;;
	*)            t_pass "unscoped render has no saddr filter" ;;
esac

# --- scoped rules (used by the isolated test) must filter on the host ---
NFT_SCOPED=$(sa_render_nft "192.168.1.77")
assert_contains "$NFT_SCOPED" "ip saddr 192.168.1.77" "scoped render filters by source ip"

# --- dnsmasq config ---
DNS=$(sa_render_dnsmasq)
assert_contains "$DNS" "nftset=/youtube.com/4#inet#fw4#xrayfrag4" "youtube nftset line"
assert_contains "$DNS" "nftset=/instagram.com/4#inet#fw4#xrayfrag4" "instagram nftset line"
assert_contains "$DNS" "googlevideo.com" "googlevideo nftset line"
assert_contains "$DNS" "fbcdn.net"       "fbcdn nftset line"
assert_eq "$(printf '%s\n' "$DNS" | grep -c '^nftset=')" "8" "one nftset line per dns domain"

# geosite: entries are an Xray concept; dnsmasq must never see them
case "$DNS" in
	*geosite*) t_fail "no geosite entries in dnsmasq config" ;;
	*)         t_pass "no geosite entries in dnsmasq config" ;;
esac

t_summary
