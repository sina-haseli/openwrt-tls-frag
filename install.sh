#!/bin/sh
# xray-frag installer. See README.md.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/common.sh"
. "$HERE/lib/core.sh"
. "$HERE/lib/verify.sh"
. "$HERE/lib/mode_passwall2.sh"
. "$HERE/lib/mode_standalone.sh"

STATE_FILE=/etc/xray-frag/.install-state

MODE=auto
SCOPE_IP=""
DO_VERIFY=1
DO_STATS=1

usage() {
	cat <<USAGE
xray-frag installer - direct TLS fragmentation for OpenWrt

Usage: ./install.sh [options]

  --mode auto|passwall2|standalone
                    auto (default) uses passwall2 if installed, else standalone
  --scope-ip <ip>   standalone only: apply rules to this source IP only.
                    Intended for isolated testing, not normal use.
  --no-verify       skip the post-install differential check (not recommended)
  --no-stats        do not install the one-minute stats cron sampler
  -h, --help        this message

Requires xray >= $XRAY_MIN_VERSION. Standalone mode also requires dnsmasq-full.
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
		--mode)      MODE="${2:-}"; shift 2 ;;
		--scope-ip)  SCOPE_IP="${2:-}"; shift 2 ;;
		--no-verify) DO_VERIFY=0; shift ;;
		--no-stats)  DO_STATS=0; shift ;;
		-h|--help)   usage; exit 0 ;;
		*)           usage; die "unknown argument: $1" ;;
	esac
done

case "$MODE" in
	auto|passwall2|standalone) : ;;
	*) usage; die "unknown mode: $MODE" ;;
esac

require_root
require_openwrt
require_xray
require_space 4096

if [ "$MODE" = "auto" ]; then
	if pw2_present; then
		MODE=passwall2
		log_info "auto: passwall2 detected"
	else
		MODE=standalone
		log_info "auto: no passwall2, using standalone"
	fi
fi

if [ -n "$SCOPE_IP" ] && [ "$MODE" != "standalone" ]; then
	die "--scope-ip only applies to standalone mode"
fi

BACKUP=""
SHUNT=""
if [ "$MODE" = "passwall2" ]; then
	pw2_present || die "passwall2 is not installed. Use --mode standalone."
	# Discover and validate BEFORE writing anything.
	SHUNT=$(pw2_shunt_id) || die "cannot wire passwall2 (see above)"
	# Keep the backup taken by the FIRST install. Re-installing must not
	# overwrite the record of the pre-project state with an already-wired
	# config, or uninstall would "restore" our own sections.
	if [ -f "$STATE_FILE" ]; then
		_prev_backup=$(sed -n 's/^BACKUP=//p' "$STATE_FILE" | head -1)
		if [ -n "$_prev_backup" ] && [ -f "$_prev_backup" ]; then
			BACKUP="$_prev_backup"
			log_info "reusing pre-existing backup $BACKUP"
		fi
	fi
	[ -n "$BACKUP" ] || BACKUP=$(pw2_backup)
else
	sa_requirements
fi

core_install "$MODE" "$HERE/files"

if [ "$MODE" = "passwall2" ]; then
	pw2_install "$SHUNT"
else
	sa_install "$SCOPE_IP"
fi

[ "$DO_STATS" -eq 1 ] && core_cron_enable

mkdir -p /etc/xray-frag
{
	echo "MODE=$MODE"
	echo "BACKUP=$BACKUP"
	echo "SCOPE=$SCOPE_IP"
} > "$STATE_FILE"

log_info "installed in $MODE mode"

if [ "$DO_VERIFY" -eq 1 ]; then
	if [ "$MODE" = "standalone" ]; then
		log_warn "standalone mode is transparent; the SOCKS-based check does not apply."
		log_warn "Test from a LAN client: flush its DNS, then load youtube.com."
		log_warn "On the router, watch the set fill:  nft list set inet fw4 $SA_SET4"
	else
		log_info "running differential verification..."
		if verify_fragment; then
			log_info "DONE - fragmentation confirmed working"
		else
			log_err "install completed but verification FAILED."
			log_err "See docs/troubleshooting.md. To undo: ./uninstall.sh"
			exit 1
		fi
	fi
fi

exit 0
