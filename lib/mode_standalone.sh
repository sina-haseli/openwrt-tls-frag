#!/bin/sh
# Standalone mode: transparent redirect for routers without Passwall2.
# dnsmasq resolves the target domains into an nftables set; fw4 redirects
# matching TCP to the dokodemo-door inbound and drops matching QUIC.
# Sourced, never executed.

SA_NFT_FILE=/etc/nftables.d/90-xray-frag.nft
SA_DNS_FILE=/etc/dnsmasq.d/90-xray-frag.conf
SA_SET4=xrayfrag4

# Bare domains only. dnsmasq matches literal suffixes; "geosite:" is an Xray
# concept and is meaningless here.
SA_DOMAINS='youtube.com
youtu.be
googlevideo.com
ytimg.com
ggpht.com
instagram.com
cdninstagram.com
fbcdn.net'

sa_requirements() {
	[ -d /etc/nftables.d ] || die "no /etc/nftables.d - this needs fw4 (OpenWrt 22.03+)"
	command -v dnsmasq >/dev/null 2>&1 || die "dnsmasq not found"
	if ! dnsmasq --help 2>&1 | grep -q -- "--nftset"; then
		die "this dnsmasq lacks nftset support. Install the full build:
  apk add dnsmasq-full   (or: opkg install dnsmasq-full, replacing dnsmasq)"
	fi
}

# sa_render_nft [scope-ip]
sa_render_nft() {
	_scope="${1:-}"
	if [ -n "$_scope" ]; then
		_saddr="ip saddr $_scope "
		_note="  # SCOPED TO $_scope (isolated test mode)"
	else
		_saddr=""
		_note=""
	fi

	cat <<NFTEOF
# Managed by xray-frag. Do not edit; re-run install.sh instead.
# Included by fw4 inside "table inet fw4".$_note

set $SA_SET4 {
	type ipv4_addr
	flags timeout
	timeout 1h
}

chain xray_frag_redirect {
	type nat hook prerouting priority dstnat - 5; policy accept;
	# Loop prevention: the fragmenter's own egress carries mark 255 and must
	# never be redirected back into the fragmenter. This rule MUST stay first.
	meta mark 255 return
	${_saddr}ip daddr @$SA_SET4 tcp dport { 80, 443 } redirect to :$CORE_REDIR_PORT
}

chain xray_frag_quic {
	type filter hook forward priority filter - 5; policy accept;
	# Drop QUIC to the targets so browsers fall back to TCP, which is the
	# path being fragmented. Without this, Chrome uses UDP/443 and bypasses us.
	meta mark 255 return
	${_saddr}ip daddr @$SA_SET4 udp dport 443 counter drop
}
NFTEOF
}

sa_render_dnsmasq() {
	echo "# Managed by xray-frag. Do not edit; re-run install.sh instead."
	echo "# Populates the nftables set $SA_SET4 with resolved target addresses."
	printf '%s\n' "$SA_DOMAINS" | while read -r _d; do
		[ -n "$_d" ] || continue
		echo "nftset=/$_d/4#inet#fw4#$SA_SET4"
	done
}

# sa_install [scope-ip]
sa_install() {
	sa_requirements
	mkdir -p /etc/nftables.d /etc/dnsmasq.d
	sa_render_nft "${1:-}"  > "$SA_NFT_FILE"
	sa_render_dnsmasq       > "$SA_DNS_FILE"

	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || die "dnsmasq failed to restart - check $SA_DNS_FILE"
	fw4 restart >/dev/null 2>&1 || die "fw4 failed to reload - check $SA_NFT_FILE"

	nft list set inet fw4 "$SA_SET4" >/dev/null 2>&1 || \
		die "nftables set $SA_SET4 was not created - check 'fw4 check' output"

	if [ -n "${1:-}" ]; then
		log_info "standalone installed, SCOPED to ${1} (isolated test mode)"
	else
		log_info "standalone installed (transparent redirect for all LAN clients)"
	fi
	log_info "note: clients must flush DNS or wait for TTL before the set fills"
}

sa_remove() {
	rm -f "$SA_NFT_FILE" "$SA_DNS_FILE"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	fw4 restart >/dev/null 2>&1
	log_info "standalone rules removed"
}
