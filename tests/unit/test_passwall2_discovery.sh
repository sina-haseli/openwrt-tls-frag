#!/bin/sh
set -u
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/mode_passwall2.sh"

# --- happy path: global node exists and is a shunt ---
uci() {
	case "$*" in
		"-q get passwall2.@global[0].node") echo "ABCD1234" ;;
		"-q get passwall2.ABCD1234.protocol") echo "_shunt" ;;
		*) return 1 ;;
	esac
}
assert_eq "$(pw2_shunt_id)" "ABCD1234" "discovers the global shunt id"

# --- the shunt id must be discovered at runtime, never hardcoded ---
# The reference router's actual shunt section name is private and deliberately
# does not appear in this repository. Set FORBIDDEN_SHUNT_ID to your own
# router's id to run the strict literal check locally before publishing.
PW2_SRC=$(cat "$ROOT/lib/mode_passwall2.sh")
assert_contains "$PW2_SRC" 'uci -q get passwall2.@global[0].node' \
	"shunt id is discovered from uci at runtime"

if [ -n "${FORBIDDEN_SHUNT_ID:-}" ]; then
	case "$PW2_SRC" in
		*"$FORBIDDEN_SHUNT_ID"*) t_fail "no hardcoded shunt id in mode_passwall2.sh" ;;
		*)                       t_pass "no hardcoded shunt id in mode_passwall2.sh" ;;
	esac
else
	t_pass "no hardcoded shunt id (set FORBIDDEN_SHUNT_ID for the strict check)"
fi

# --- global node is a plain node, not a shunt: must refuse ---
uci() {
	case "$*" in
		"-q get passwall2.@global[0].node") echo "PLAIN001" ;;
		"-q get passwall2.PLAIN001.protocol") echo "vless" ;;
		*) return 1 ;;
	esac
}
assert_fail "refuses a non-shunt global node" pw2_shunt_id

# --- no global node set at all: must refuse ---
uci() { return 1; }
assert_fail "refuses when no global node is set" pw2_shunt_id

# --- global node set to empty string: must refuse ---
uci() {
	case "$*" in
		"-q get passwall2.@global[0].node") echo "" ;;
		*) return 1 ;;
	esac
}
assert_fail "refuses an empty global node" pw2_shunt_id

# --- the domain list is exactly the 10 documented entries ---
assert_eq "$(printf '%s\n' "$PW2_DOMAINS" | grep -c .)" "10" "domain list has 10 entries"
assert_contains "$PW2_DOMAINS" "geosite:youtube"      "domain list has geosite:youtube"
assert_contains "$PW2_DOMAINS" "geosite:instagram"    "domain list has geosite:instagram"
assert_contains "$PW2_DOMAINS" "domain:googlevideo.com" "domain list has googlevideo"
assert_contains "$PW2_DOMAINS" "domain:fbcdn.net"     "domain list has fbcdn.net"

t_summary
