#!/bin/sh
set -u
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/core.sh"
. "$ROOT/lib/verify.sh"

# --- probes always emit a 3-digit code, never fail ---
CODE=$(probe_direct "https://example.com")
assert_ok "probe_direct returns 3 chars" test "${#CODE}" -eq 3
assert_ok "probe_direct never fails"     probe_direct "https://no-such-host.invalid"
assert_eq "$(probe_direct 'https://no-such-host.invalid')" "000" \
	"unreachable host probes as 000"

# --- the control instance starts, listens, and stops cleanly ---
assert_ok "control instance starts" control_start
assert_contains "$(netstat -ln 2>/dev/null)" "127.0.0.1:10898" \
	"control instance is listening"
assert_eq "$(probe_control 'https://www.google.com')" "200" \
	"control reaches the unblocked control host"
# The control must be a genuinely direct path, not the proxy layer: on this
# line the blocked targets must fail through it.
assert_eq "$(probe_control 'https://www.youtube.com')" "000" \
	"control cannot reach youtube unfragmented"
control_stop
assert_eq "$(_control_pids)" "" "control instance stopped"
assert_fail "control config cleaned up" test -f /tmp/xray-frag-control.json

# --- with the fragmenter up, verification must pass ---
core_install passwall2 "$ROOT/files"
assert_ok "verify passes with fragmenter running" verify_fragment

# verify_fragment must not leak its control instance
assert_eq "$(_control_pids)" "" "no control instance left after verify"

# --- with the fragmenter down, verification must FAIL ---
# This is the regression guard for the false-positive that occurred during
# original development, where traffic silently rode the VPN.
/etc/init.d/xray-frag stop
sleep 2
assert_fail "verify fails with fragmenter stopped" verify_fragment

/etc/init.d/xray-frag start
sleep 2
assert_ok "fragmenter restarted" core_is_running

t_summary
