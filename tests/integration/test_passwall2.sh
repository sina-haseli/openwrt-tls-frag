#!/bin/sh
set -u
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/core.sh"
. "$ROOT/lib/mode_passwall2.sh"

assert_ok "passwall2 is present" pw2_present

SAFETY=$(pw2_backup)
echo "  (safety backup: $SAFETY)"

SHUNT=$(pw2_shunt_id)
assert_ok "shunt id is non-empty" test -n "$SHUNT"
assert_eq "$(uci -q get "passwall2.${SHUNT}.protocol")" "_shunt" "discovered node is a shunt"

pw2_install "$SHUNT"

assert_eq "$(uci -q get passwall2.FRAGDRCT.protocol)" "socks"     "FRAGDRCT is a socks node"
assert_eq "$(uci -q get passwall2.FRAGDRCT.port)"     "10808"     "FRAGDRCT points at 10808"
assert_eq "$(uci -q get passwall2.FragTCP.network)"   "tcp"       "FragTCP is tcp"
assert_eq "$(uci -q get passwall2.FragUDP.network)"   "udp"       "FragUDP is udp"
assert_eq "$(uci -q get "passwall2.${SHUNT}.FragTCP")" "FRAGDRCT" "shunt routes FragTCP to FRAGDRCT"
assert_eq "$(uci -q get "passwall2.${SHUNT}.FragUDP")" "_blackhole" "shunt blackholes FragUDP"
assert_eq "$(uci -q get passwall2.FragTCP.domain_list | grep -c .)" "10" "FragTCP has 10 domains"

# --- idempotent: running twice must not duplicate or break anything ---
pw2_install "$SHUNT"
assert_eq "$(uci -q get "passwall2.${SHUNT}.FragTCP")" "FRAGDRCT" "still wired after second install"
assert_eq "$(uci show passwall2 | grep -c '^passwall2.FRAGDRCT=')" "1" "FRAGDRCT not duplicated"

# --- removal ---
pw2_remove
assert_fail "FRAGDRCT gone" uci -q get passwall2.FRAGDRCT.protocol
assert_fail "FragTCP gone"  uci -q get passwall2.FragTCP.network
assert_fail "shunt key gone" uci -q get "passwall2.${SHUNT}.FragTCP"

# --- restore production state ---
pw2_install "$SHUNT"
assert_eq "$(uci -q get "passwall2.${SHUNT}.FragTCP")" "FRAGDRCT" "production wiring restored"

t_summary
