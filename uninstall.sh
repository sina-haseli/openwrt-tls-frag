#!/bin/sh
# Reverse everything install.sh did.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/lib/common.sh"
. "$HERE/lib/core.sh"
. "$HERE/lib/mode_passwall2.sh"
. "$HERE/lib/mode_standalone.sh"

STATE_FILE=/etc/xray-frag/.install-state

require_root

ASSUME_YES=0
[ "${1:-}" = "-y" ] && ASSUME_YES=1

MODE=""
BACKUP=""
if [ -f "$STATE_FILE" ]; then
	# shellcheck disable=SC1090
	. "$STATE_FILE"
else
	log_warn "no state file at $STATE_FILE; removing everything this project can create"
fi

if [ "$ASSUME_YES" -eq 0 ]; then
	printf 'Remove xray-frag%s? [y/N] ' "${MODE:+ ($MODE mode)}"
	read -r ans
	case "$ans" in
		y|Y|yes|YES) : ;;
		*) echo "aborted"; exit 0 ;;
	esac
fi

# Standalone artifacts are removed unconditionally: they are inert if absent,
# and a missing state file must not leave firewall rules behind.
sa_remove 2>/dev/null

if [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
	cp "$BACKUP" /etc/config/passwall2
	log_info "restored passwall2 config from $BACKUP"
else
	log_warn "no backup found; removing the specific sections instead"
fi

# Always strip this project's sections, backup or not. The restored file can
# itself contain them -- the box may have been wired by hand before this
# installer existed, or by an install whose backup predates a later re-run.
# "Uninstalled" has to mean they are gone. pw2_remove commits and restarts
# passwall2, so it also publishes the restored file above.
if pw2_present; then
	pw2_remove
elif [ -n "$BACKUP" ] && [ -f "$BACKUP" ]; then
	/etc/init.d/passwall2 restart >/dev/null 2>&1
fi

core_remove
rm -f "$STATE_FILE"

log_info "uninstalled. Your original routing is restored."
