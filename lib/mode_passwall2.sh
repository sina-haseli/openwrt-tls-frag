#!/bin/sh
# Passwall2 integration: discover the global shunt node and wire the
# fragment categories onto it. Sourced, never executed.

PW2_CONF=/etc/config/passwall2
PW2_NODE_ID=FRAGDRCT
PW2_TCP_RULE=FragTCP
PW2_UDP_RULE=FragUDP

PW2_DOMAINS='geosite:youtube
domain:youtube.com
domain:youtu.be
domain:googlevideo.com
domain:ytimg.com
domain:ggpht.com
geosite:instagram
domain:instagram.com
domain:cdninstagram.com
domain:fbcdn.net'

pw2_present() {
	[ -f "$PW2_CONF" ] && command -v uci >/dev/null 2>&1
}

# pw2_shunt_id -> section name of the global shunt node
# Never hardcode this. Every install has a different randomly-generated id,
# and writing to the wrong section corrupts the user's routing.
pw2_shunt_id() {
	_id=$(uci -q get passwall2.@global[0].node) || {
		log_err "passwall2 has no global node set"
		return 1
	}
	[ -n "$_id" ] || { log_err "passwall2 global node is empty"; return 1; }

	_proto=$(uci -q get "passwall2.${_id}.protocol")
	if [ "$_proto" != "_shunt" ]; then
		log_err "passwall2 global node '$_id' is protocol '${_proto:-unknown}', not '_shunt'."
		log_err "This installer only wires fragment categories onto a shunt node,"
		log_err "because that is the only place per-domain routing rules exist."
		log_err "Either switch your global node to a shunt in the Passwall2 UI,"
		log_err "or re-run with --mode standalone."
		return 1
	fi
	echo "$_id"
}

# pw2_backup -> echoes the backup path
pw2_backup() {
	_ts=$(date +%Y%m%d-%H%M%S)
	_bak="${PW2_CONF}.bak-frag-${_ts}"
	cp "$PW2_CONF" "$_bak" || die "could not back up $PW2_CONF"
	log_info "backed up passwall2 config to $_bak"
	echo "$_bak"
}

# pw2_install <shunt-id>
pw2_install() {
	_shunt="$1"
	[ -n "$_shunt" ] || die "pw2_install: empty shunt id"

	# SOCKS node pointing at the fragmenter
	uci -q delete "passwall2.$PW2_NODE_ID"
	uci set "passwall2.$PW2_NODE_ID=nodes"
	uci set "passwall2.$PW2_NODE_ID.remarks=Fragment Direct (YT/IG)"
	uci set "passwall2.$PW2_NODE_ID.type=Xray"
	uci set "passwall2.$PW2_NODE_ID.protocol=socks"
	uci set "passwall2.$PW2_NODE_ID.address=127.0.0.1"
	uci set "passwall2.$PW2_NODE_ID.port=$CORE_SOCKS_PORT"

	# TCP category -> fragmenter
	uci -q delete "passwall2.$PW2_TCP_RULE"
	uci set "passwall2.$PW2_TCP_RULE=shunt_rules"
	uci set "passwall2.$PW2_TCP_RULE.remarks=Fragment TCP (YT/IG)"
	uci set "passwall2.$PW2_TCP_RULE.network=tcp"
	uci set "passwall2.$PW2_TCP_RULE.domain_list=$PW2_DOMAINS"

	# UDP category -> blackhole, to kill QUIC and force the TCP path we fragment
	uci -q delete "passwall2.$PW2_UDP_RULE"
	uci set "passwall2.$PW2_UDP_RULE=shunt_rules"
	uci set "passwall2.$PW2_UDP_RULE.remarks=Fragment UDP block (QUIC)"
	uci set "passwall2.$PW2_UDP_RULE.network=udp"
	uci set "passwall2.$PW2_UDP_RULE.domain_list=$PW2_DOMAINS"

	uci set "passwall2.${_shunt}.${PW2_TCP_RULE}=$PW2_NODE_ID"
	uci set "passwall2.${_shunt}.${PW2_UDP_RULE}=_blackhole"

	uci commit passwall2
	/etc/init.d/passwall2 restart >/dev/null 2>&1
	log_info "passwall2 wired: $PW2_TCP_RULE -> $PW2_NODE_ID, $PW2_UDP_RULE -> _blackhole (shunt $_shunt)"
}

pw2_remove() {
	pw2_present || return 0
	_shunt=$(uci -q get passwall2.@global[0].node)
	if [ -n "$_shunt" ]; then
		uci -q delete "passwall2.${_shunt}.${PW2_TCP_RULE}"
		uci -q delete "passwall2.${_shunt}.${PW2_UDP_RULE}"
	fi
	uci -q delete "passwall2.$PW2_TCP_RULE"
	uci -q delete "passwall2.$PW2_UDP_RULE"
	uci -q delete "passwall2.$PW2_NODE_ID"
	uci commit passwall2
	/etc/init.d/passwall2 restart >/dev/null 2>&1
	log_info "passwall2 sections removed"
}
