#!/bin/sh
# Rendered fragment profiles. The mode templates carry a __FRAG_STAGES__
# placeholder; the profile file supplies the stages. These assertions pin the
# exact v50 values so a stray edit cannot silently change what ships.
set -u
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/core.sh"

SRC="$ROOT/files"

A_PW2=$(core_render_config "$SRC" passwall2 a)
B_PW2=$(core_render_config "$SRC" passwall2 b)
A_SA=$(core_render_config "$SRC" standalone a)
B_SA=$(core_render_config "$SRC" standalone b)

# --- profile A: fragA / low_delay (the default) ---
assert_contains "$A_PW2" '"packets": "tlshello", "lengths": ["6", "98", "1"]' \
	"profile a stage-1 tlshello lengths"
assert_contains "$A_PW2" '"packets": "1-1", "lengths": ["114", "1"]' \
	"profile a stage-2 lengths"
assert_contains "$A_PW2" '"maxSplit": "0"' \
	"profile a stage-1 maxSplit"
assert_contains "$A_PW2" '"maxSplit": "11"' \
	"profile a stage-2 maxSplit"

# --- profile B: fragB / high_delay, differs only in stage-1 lengths ---
assert_contains "$B_PW2" '"packets": "tlshello", "lengths": ["0", "104", "1"]' \
	"profile b stage-1 tlshello lengths"
assert_contains "$B_PW2" '"packets": "1-1", "lengths": ["114", "1"]' \
	"profile b stage-2 lengths"
assert_contains "$B_PW2" '"maxSplit": "11"' \
	"profile b stage-2 maxSplit"

# --- the placeholder must be substituted, never shipped ---
case "$A_PW2" in
	*__FRAG_STAGES__*) t_fail "profile a has no leftover placeholder" ;;
	*)                 t_pass "profile a has no leftover placeholder" ;;
esac
case "$B_PW2" in
	*__FRAG_STAGES__*) t_fail "profile b has no leftover placeholder" ;;
	*)                 t_pass "profile b has no leftover placeholder" ;;
esac

# --- the fragment stages are identical across modes for the same profile ---
assert_eq "$(printf '%s\n' "$A_PW2" | grep -c '"type": "fragment"')" \
	"$(printf '%s\n' "$A_SA" | grep -c '"type": "fragment"')" \
	"both modes render two fragment stages in profile a"

# --- each mode keeps its own inbound ---
assert_contains "$A_PW2" '"socks-in"' "passwall2 profile a uses the socks inbound"
assert_contains "$B_PW2" '"socks-in"' "passwall2 profile b uses the socks inbound"
assert_contains "$A_SA"  '"redir-in"' "standalone profile a uses the dokodemo inbound"
assert_contains "$B_SA"  '"redir-in"' "standalone profile b uses the dokodemo inbound"

# --- rendered output is valid JSON (best effort; python3/jq may be absent) ---
if command -v python3 >/dev/null 2>&1; then
	printf '%s\n' "$A_PW2" | python3 -m json.tool >/dev/null 2>&1
	assert_eq "$?" "0" "profile a passwall2 renders valid JSON"
	printf '%s\n' "$B_SA" | python3 -m json.tool >/dev/null 2>&1
	assert_eq "$?" "0" "profile b standalone renders valid JSON"
fi

# --- an unknown profile is rejected ---
assert_fail "unknown profile is rejected" \
	sh -c '. "$1/lib/common.sh"; . "$1/lib/core.sh"; core_render_config "$1" passwall2 z' \
	sh "$ROOT"

t_summary
