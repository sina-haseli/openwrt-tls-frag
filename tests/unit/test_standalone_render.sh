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
# The redirect rule must be counted: "did anything actually get redirected"
# is the first question when standalone mode does not work.
assert_contains "$NFT" "counter redirect to :10809" "redirect rule is counted"
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

# --- the dnsmasq target must be /etc/dnsmasq.conf, not /etc/dnsmasq.d ---
# OpenWrt's dnsmasq passes --conf-dir=/tmp/dnsmasq.<section>.d and runs under
# ujail, so a file in /etc/dnsmasq.d is never read and cannot be included.
assert_eq "$SA_DNS_CONF" "/etc/dnsmasq.conf" "dnsmasq config target is /etc/dnsmasq.conf"

# --- managed-block install/remove on a scratch file ---
TMPD="${TMPDIR:-/tmp}/xray-frag-test.$$"
mkdir -p "$TMPD"
SA_DNS_CONF="$TMPD/dnsmasq.conf"

printf '%s\n' "# user comment above" "domain-needed" > "$SA_DNS_CONF"

assert_fail "block absent before install" sa_dns_block_present
sa_dns_install
assert_ok "block present after install" sa_dns_block_present
assert_contains "$(cat "$SA_DNS_CONF")" "nftset=/youtube.com/4#inet#fw4#xrayfrag4" \
	"install writes the nftset lines"
assert_contains "$(cat "$SA_DNS_CONF")" "domain-needed" "pre-existing user lines survive install"

# installing twice must replace, not duplicate
sa_dns_install
assert_eq "$(grep -c '^nftset=' "$SA_DNS_CONF")" "8" "re-install does not duplicate the block"
assert_eq "$(grep -cF "$SA_DNS_BEGIN" "$SA_DNS_CONF")" "1" "only one begin marker"

sa_dns_remove
assert_fail "block gone after remove" sa_dns_block_present
assert_eq "$(grep -c '^nftset=' "$SA_DNS_CONF")" "0" "remove strips every nftset line"
assert_contains "$(cat "$SA_DNS_CONF")" "domain-needed" "user lines survive remove"
assert_contains "$(cat "$SA_DNS_CONF")" "# user comment above" "user comments survive remove"

# remove on a file without our block must be a harmless no-op
sa_dns_remove
assert_eq "$(wc -l < "$SA_DNS_CONF")" "2" "remove is a no-op when the block is absent"

rm -rf "$TMPD"

t_summary
