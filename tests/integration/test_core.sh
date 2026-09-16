#!/bin/sh
set -u
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/core.sh"

SRC="$ROOT/files"

# --- install in passwall2 mode ---
core_install passwall2 "$SRC" a

assert_ok "config.json installed"        test -f /etc/xray-frag/config.json
assert_ok "init script installed"        test -x /etc/init.d/xray-frag
assert_ok "stats tool installed"         test -x /usr/bin/xray-frag-stats
assert_ok "service enabled at boot"      test -e /etc/rc.d/S94xray-frag
assert_ok "process running"              core_is_running

assert_contains "$(cat /etc/xray-frag/config.json)" '"socks-in"' \
	"passwall2 mode installs the socks config"
assert_contains "$(cat /etc/xray-frag/config.json)" '"lengths": ["6", "98", "1"]' \
	"fragment profile a stage 1 present"
assert_contains "$(cat /etc/xray-frag/config.json)" '"maxSplit": "11"' \
	"fragment profile a stage 2 present"

sleep 1
assert_contains "$(netstat -ln 2>/dev/null)" "127.0.0.1:10808" \
	"socks port is listening"

# --- install is idempotent ---
core_install passwall2 "$SRC" a
assert_ok "still running after re-install" core_is_running

# --- switching fragment profile swaps the stages, not the mode ---
core_install passwall2 "$SRC" b
assert_contains "$(cat /etc/xray-frag/config.json)" '"socks-in"' \
	"profile switch keeps the socks inbound"
assert_contains "$(cat /etc/xray-frag/config.json)" '"lengths": ["0", "104", "1"]' \
	"fragment profile b stage 1 present"

# --- switching mode swaps the config ---
core_install standalone "$SRC" a
assert_contains "$(cat /etc/xray-frag/config.json)" '"redir-in"' \
	"standalone mode installs the dokodemo config"

# --- cron management does not clobber other entries ---
echo '# canary-entry' >> /etc/crontabs/root
core_cron_enable
assert_contains "$(cat /etc/crontabs/root)" "xray-frag-stats log" "cron line added"
assert_contains "$(cat /etc/crontabs/root)" "canary-entry"        "other cron entries preserved"
core_cron_disable
assert_contains "$(cat /etc/crontabs/root)" "canary-entry"        "canary survives cron removal"
case "$(cat /etc/crontabs/root)" in
	*xray-frag-stats*) t_fail "cron line removed" ;;
	*)                 t_pass "cron line removed" ;;
esac
sed -i '/canary-entry/d' /etc/crontabs/root

# --- removal is complete ---
core_remove
assert_fail "config dir gone"      test -d /etc/xray-frag
assert_fail "init script gone"     test -f /etc/init.d/xray-frag
assert_fail "stats tool gone"      test -f /usr/bin/xray-frag-stats
assert_fail "boot symlink gone"    test -e /etc/rc.d/S94xray-frag
assert_fail "process stopped"      core_is_running

t_summary
