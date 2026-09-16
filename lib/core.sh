#!/bin/sh
# Install and remove the mode-independent core: config, service, stats tool.
# Sourced, never executed.

CORE_SOCKS_PORT=10808
CORE_REDIR_PORT=10809

CORE_CONF_DIR=/etc/xray-frag
CORE_CONF=$CORE_CONF_DIR/config.json
CORE_INIT=/etc/init.d/xray-frag
CORE_STATS=/usr/bin/xray-frag-stats
CORE_CRON=/etc/crontabs/root
CORE_CRON_LINE="* * * * * /usr/bin/xray-frag-stats log"

core_is_running() {
	ps -w 2>/dev/null | grep -q "[x]ray-frag/config.json"
}

# core_render_config <files-dir> <mode> <profile> -> rendered config on stdout
#
# The mode template carries a __FRAG_STAGES__ placeholder where the fragment
# array belongs; the profile file supplies those stages. One file per profile
# means the two modes cannot drift apart.
core_render_config() {
	_src="$1"
	_mode="$2"
	_profile="$3"

	_tpl="$_src/etc/xray-frag/config.$_mode.json"
	_frag="$_src/etc/xray-frag/frag-$_profile.json"

	[ -f "$_tpl" ]  || die "missing config template: $_tpl"
	[ -f "$_frag" ] || die "missing fragment profile: $_frag"
	grep -q '__FRAG_STAGES__' "$_tpl" || die "template $_tpl has no __FRAG_STAGES__ placeholder"

	awk -v frag="$_frag" '
		/__FRAG_STAGES__/ {
			while ((getline _l < frag) > 0) print _l
			close(frag)
			next
		}
		{ print }
	' "$_tpl"
}

# core_install <passwall2|standalone> <files-dir> [fragment-profile]
# fragment-profile is "a" (default, low delay) or "b" (high delay).
core_install() {
	_mode="$1"
	_src="$2"
	_profile="${3:-a}"

	case "$_mode" in
		passwall2|standalone) : ;;
		*) die "core_install: unknown mode '$_mode'" ;;
	esac
	case "$_profile" in
		a|b) : ;;
		*) die "core_install: unknown fragment profile '$_profile' (expected a or b)" ;;
	esac

	require_space 2048

	mkdir -p "$CORE_CONF_DIR"
	core_render_config "$_src" "$_mode" "$_profile" > "$CORE_CONF"
	cp "$_src/etc/init.d/xray-frag" "$CORE_INIT"
	cp "$_src/usr/bin/xray-frag-stats" "$CORE_STATS"
	chmod 0755 "$CORE_INIT" "$CORE_STATS"

	"$CORE_INIT" enable
	"$CORE_INIT" restart

	# procd start is async; give it a moment before callers probe the port
	_i=0
	while [ "$_i" -lt 20 ]; do
		core_is_running && break
		sleep 1
		_i=$((_i + 1))
	done

	core_is_running || die "xray-frag failed to start. Check: logread -e xray-frag"
	log_info "core installed in $_mode mode"
}

core_remove() {
	if [ -x "$CORE_INIT" ]; then
		"$CORE_INIT" stop 2>/dev/null
		"$CORE_INIT" disable 2>/dev/null
	fi
	core_cron_disable
	rm -f "$CORE_INIT" "$CORE_STATS"
	rm -rf "$CORE_CONF_DIR"
	rm -f /etc/rc.d/S94xray-frag /etc/rc.d/K10xray-frag
	log_info "core removed"
}

core_cron_enable() {
	[ -f "$CORE_CRON" ] || touch "$CORE_CRON"
	grep -q "xray-frag-stats log" "$CORE_CRON" && return 0
	echo "$CORE_CRON_LINE" >> "$CORE_CRON"
	/etc/init.d/cron restart >/dev/null 2>&1
	log_info "stats sampler enabled (logs to /tmp, cleared on reboot)"
}

core_cron_disable() {
	[ -f "$CORE_CRON" ] || return 0
	grep -q "xray-frag-stats" "$CORE_CRON" || return 0
	sed -i '/xray-frag-stats/d' "$CORE_CRON"
	/etc/init.d/cron restart >/dev/null 2>&1
}
