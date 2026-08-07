#!/bin/sh
# Differential verification: prove the fragmenter is doing the work.
# Sourced, never executed.
#
# Why not just "curl --noproxy" for the negative control:
#   --noproxy only disables curl's own env-var proxy handling. It does nothing
#   about transparent interception. On a Passwall2 router the PSW2_OUTPUT_NAT
#   chain redirects the router's own TCP to the proxy core, so a "direct" fetch
#   of youtube.com returns 200 while riding the VPN. Using that as the control
#   makes a working install report "not proven to do anything".
#
#   Instead we start a throwaway xray on a scratch port whose outbound is
#   identical to the fragmenter's -- same DoH resolver, same sockopt.mark 255
#   (which is what bypasses the proxy layer) -- with the fragment stages
#   removed. The only variable between the two paths is the fragment block,
#   so the comparison actually attributes the result to fragmentation.

VERIFY_CONTROL_URL="https://www.google.com"
VERIFY_TARGET_URLS="https://www.youtube.com https://www.instagram.com"
VERIFY_TIMEOUT=12

VERIFY_CONTROL_PORT=10898
VERIFY_CONTROL_CONF=/tmp/xray-frag-control.json
VERIFY_CONTROL_LOG=/tmp/xray-frag-control.log

# _probe <url> <curl-extra-args...>  -> HTTP status, or 000
# curl prints "000" AND exits non-zero on connection failure, so a naive
# `curl ... || echo 000` emits "000000". Capture, then substitute.
_probe() {
	_url="$1"; shift
	_out=$(curl -s -o /dev/null -w '%{http_code}' \
		--max-time "$VERIFY_TIMEOUT" \
		"$@" "$_url" 2>/dev/null)
	case "$_out" in
		[0-9][0-9][0-9]) echo "$_out" ;;
		*)               echo "000" ;;
	esac
}

# Kept for diagnostics. NOT a valid negative control -- see the header comment.
probe_direct() {
	_probe "$1" --noproxy '*'
}

probe_socks() {
	_probe "$1" --socks5-hostname "127.0.0.1:$CORE_SOCKS_PORT"
}

probe_control() {
	_probe "$1" --socks5-hostname "127.0.0.1:$VERIFY_CONTROL_PORT"
}

_control_pids() {
	ps -w 2>/dev/null | grep "[x]ray run -c $VERIFY_CONTROL_CONF" | awk '{print $1}'
}

# control_start -> 0 if the unfragmented control instance is listening
control_start() {
	control_stop

	cat > "$VERIFY_CONTROL_CONF" <<CTLEOF
{
  "log": { "loglevel": "warning" },
  "dns": {
    "hosts": { "cloudflare-dns.com": "challenges.cloudflare.com" },
    "servers": [
      { "address": "https://cloudflare-dns.com/dns-query", "timeoutMs": 12000 }
    ],
    "queryStrategy": "UseIPv4"
  },
  "inbounds": [
    {
      "tag": "control-in",
      "listen": "127.0.0.1",
      "port": $VERIFY_CONTROL_PORT,
      "protocol": "socks",
      "settings": { "auth": "noauth", "udp": true },
      "sniffing": { "enabled": true, "destOverride": ["tls", "http"], "routeOnly": true }
    }
  ],
  "outbounds": [
    {
      "tag": "plain",
      "protocol": "direct",
      "streamSettings": { "sockopt": { "mark": 255 } }
    },
    { "tag": "dns-out", "protocol": "dns" }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      { "type": "field", "port": 53, "outboundTag": "dns-out" }
    ]
  }
}
CTLEOF

	xray run -c "$VERIFY_CONTROL_CONF" >"$VERIFY_CONTROL_LOG" 2>&1 &

	_i=0
	while [ "$_i" -lt 15 ]; do
		if netstat -ln 2>/dev/null | grep -q "127.0.0.1:$VERIFY_CONTROL_PORT"; then
			return 0
		fi
		sleep 1
		_i=$((_i + 1))
	done

	log_err "verify: control instance did not start. Log: $VERIFY_CONTROL_LOG"
	control_stop
	return 1
}

control_stop() {
	_p=$(_control_pids)
	if [ -n "$_p" ]; then
		kill $_p 2>/dev/null
		sleep 1
		_p=$(_control_pids)
		[ -n "$_p" ] && kill -9 $_p 2>/dev/null
	fi
	rm -f "$VERIFY_CONTROL_CONF"
	return 0
}

# verify_fragment -> 0 only if fragmentation is demonstrably responsible
verify_fragment() {
	core_is_running || { log_err "verify: xray-frag is not running"; return 1; }

	control_start || return 1

	_rc=0

	# 1. The control host must work on the unfragmented direct path. If it does
	#    not, the box has no working direct internet and every other result
	#    below is meaningless.
	_c=$(probe_control "$VERIFY_CONTROL_URL")
	if [ "$_c" = "200" ]; then
		log_info "verify: control $VERIFY_CONTROL_URL unfragmented = $_c OK"
	else
		log_err "verify: control $VERIFY_CONTROL_URL unfragmented = $_c"
		log_err "verify: no working direct internet on this box. Aborting."
		control_stop
		return 1
	fi

	for _u in $VERIFY_TARGET_URLS; do
		# 2. Target must work THROUGH the fragmenter.
		_via=$(probe_socks "$_u")
		# 3. Target must FAIL on the identical path without the fragment stages.
		#    If it succeeds there too, this ISP does not block it and the
		#    install proves nothing.
		_ctl=$(probe_control "$_u")

		if [ "$_via" != "200" ]; then
			log_err "verify: $_u through fragmenter = $_via (expected 200)"
			_rc=1
		elif [ "$_ctl" = "200" ]; then
			log_warn "verify: $_u also works WITHOUT fragmentation ($_ctl) on the"
			log_warn "verify: same mark-255 direct path. It is not blocked on this"
			log_warn "verify: line, so this install is not proven to do anything."
			_rc=1
		else
			log_info "verify: $_u  fragmented=$_via  unfragmented=$_ctl  OK"
		fi
	done

	control_stop

	if [ "$_rc" -eq 0 ]; then
		log_info "verify: PASS - fragmentation is doing the work"
	else
		log_err "verify: FAIL - see docs/troubleshooting.md"
	fi
	return "$_rc"
}
