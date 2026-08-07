#!/bin/sh
# Standalone mode: transparent redirect for routers without Passwall2.
# dnsmasq resolves the target domains into an nftables set; fw4 redirects
# matching TCP to the dokodemo-door inbound and drops matching QUIC.
# Sourced, never executed.

SA_NFT_FILE=/etc/nftables.d/90-xray-frag.nft
SA_SET4=xrayfrag4

# The nftset lines go into /etc/dnsmasq.conf, NOT /etc/dnsmasq.d/.
#
# /etc/dnsmasq.d is the Debian convention and OpenWrt does not use it. The
# OpenWrt dnsmasq init generates its own config and passes
#   --conf-dir=/tmp/dnsmasq.<section>.d
# (see config_get dnsmasqconfdir ... confdir "/tmp/dnsmasq${cfg:+.$cfg}.d"),
# so a file dropped in /etc/dnsmasq.d is never read. Worse, dnsmasq runs
# under ujail with an explicit mount list, so even an absolute conf-file=
# include pointing there would be unreadable inside the jail.
#
# /etc/dnsmasq.conf is included by the generated config (conf-file=...) and is
# jail-mounted by the init script, so it is the one persistent file that is
# guaranteed to be read. OpenWrt ships it containing only comments, i.e. it is
# the intended user extension point. We own a marker-delimited block in it and
# touch nothing else.
SA_DNS_CONF=/etc/dnsmasq.conf
SA_DNS_BEGIN="# >>> xray-frag begin (managed - do not edit) >>>"
SA_DNS_END="# <<< xray-frag end <<<"

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
	${_saddr}ip daddr @$SA_SET4 tcp dport { 80, 443 } counter redirect to :$CORE_REDIR_PORT
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
	echo "# Populates the nftables set $SA_SET4 with resolved target addresses."
	printf '%s\n' "$SA_DOMAINS" | while read -r _d; do
		[ -n "$_d" ] || continue
		echo "nftset=/$_d/4#inet#fw4#$SA_SET4"
	done
}

# sa_dns_block_present -> 0 if our managed block is in $SA_DNS_CONF
sa_dns_block_present() {
	[ -f "$SA_DNS_CONF" ] || return 1
	grep -qF "$SA_DNS_BEGIN" "$SA_DNS_CONF"
}

# sa_dns_install -- replace (not duplicate) our block in $SA_DNS_CONF
sa_dns_install() {
	sa_dns_remove
	[ -f "$SA_DNS_CONF" ] || touch "$SA_DNS_CONF"
	{
		echo "$SA_DNS_BEGIN"
		sa_render_dnsmasq
		echo "$SA_DNS_END"
	} >> "$SA_DNS_CONF"
}

# sa_dns_remove -- delete our block, leaving every other line untouched
sa_dns_remove() {
	[ -f "$SA_DNS_CONF" ] || return 0
	sa_dns_block_present || return 0
	sed -i "\\|^${SA_DNS_BEGIN}\$|,\\|^${SA_DNS_END}\$|d" "$SA_DNS_CONF"
}

# sa_install [scope-ip]
sa_install() {
	sa_requirements
	mkdir -p /etc/nftables.d
	sa_render_nft "${1:-}"  > "$SA_NFT_FILE"
	sa_dns_install

	/etc/init.d/dnsmasq restart >/dev/null 2>&1 || die "dnsmasq failed to restart - check $SA_DNS_CONF"
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
	rm -f "$SA_NFT_FILE"
	# Legacy location from before the /etc/dnsmasq.d finding; harmless if absent.
	rm -f /etc/dnsmasq.d/90-xray-frag.conf
	sa_dns_remove
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	fw4 restart >/dev/null 2>&1
	log_info "standalone rules removed"
}
