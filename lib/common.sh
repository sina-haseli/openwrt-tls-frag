#!/bin/sh
# Shared helpers: logging, preflight gates, version comparison.
# Sourced, never executed. No side effects at source time.

XRAY_MIN_VERSION="26.6.27"

log_info() { printf '[xray-frag] %s\n' "$1" >&2; }
log_warn() { printf '[xray-frag] WARN: %s\n' "$1" >&2; }
log_err()  { printf '[xray-frag] ERROR: %s\n' "$1" >&2; }
die()      { log_err "$1"; exit 1; }

# _vpart <version> <index 1..3> -> numeric component, 0 if absent
_vpart() {
	echo "$1" | awk -F. -v i="$2" '{
		v = (i <= NF) ? $i : "0"
		gsub(/[^0-9].*$/, "", v)
		if (v == "") v = "0"
		print v + 0
	}'
}

# version_ge <have> <want>  -> 0 if have >= want
version_ge() {
	_h="$1"; _w="$2"
	# strip a leading "v"
	_h=${_h#v}; _w=${_w#v}
	_i=1
	while [ "$_i" -le 3 ]; do
		_a=$(_vpart "$_h" "$_i")
		_b=$(_vpart "$_w" "$_i")
		[ "$_a" -gt "$_b" ] && return 0
		[ "$_a" -lt "$_b" ] && return 1
		_i=$((_i + 1))
	done
	return 0
}

# xray_version -> bare dotted version, e.g. 26.7.28
xray_version() {
	command -v xray >/dev/null 2>&1 || return 1
	xray version 2>/dev/null | awk 'NR==1 {print $2; exit}'
}

require_root() {
	[ "$(id -u)" = "0" ] || die "must run as root"
}

require_openwrt() {
	[ -f /etc/openwrt_release ] || die "this does not look like OpenWrt (/etc/openwrt_release missing)"
}

require_xray() {
	command -v xray >/dev/null 2>&1 || die \
		"xray not found. Install it first:  apk add xray-core   (or opkg install xray-core)"
	_xv=$(xray_version)
	[ -n "$_xv" ] || die "could not determine xray version from 'xray version'"
	version_ge "$_xv" "$XRAY_MIN_VERSION" || die \
		"xray $_xv is too old. Need >= $XRAY_MIN_VERSION for streamSettings.finalmask.
Older builds accept this config and silently do NOT fragment, so this is a hard stop."
	log_info "xray $_xv (>= $XRAY_MIN_VERSION) OK"
}

# require_space <kb>
require_space() {
	_free=$(df -k / | awk 'NR==2 {print $4}')
	[ -n "$_free" ] || die "could not determine free space on /"
	[ "$_free" -ge "$1" ] || die "not enough space on /: ${_free}KB free, need ${1}KB"
}
