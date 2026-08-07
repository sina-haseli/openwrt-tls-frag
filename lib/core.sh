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

# core_install <passwall2|standalone> <files-dir>
core_install() {
	_mode="$1"
	_src="$2"

	case "$_mode" in
		passwall2|standalone) : ;;
		*) die "core_install: unknown mode '$_mode'" ;;
	esac

	_cfg="$_src/etc/xray-frag/config.$_mode.json"
	[ -f "$_cfg" ] || die "missing config template: $_cfg"

	require_space 2048

	mkdir -p "$CORE_CONF_DIR"
	cp "$_cfg" "$CORE_CONF"
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
