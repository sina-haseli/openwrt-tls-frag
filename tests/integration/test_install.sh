#!/bin/sh
set -u
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/lib/common.sh"

STATE=/etc/xray-frag/.install-state

# --- help works and does not mutate anything ---
assert_ok "install.sh --help exits 0" sh "$ROOT/install.sh" --help
assert_contains "$(sh "$ROOT/install.sh" --help 2>&1)" "--mode" "help documents --mode"

# --- rejects an unknown mode instead of guessing ---
assert_fail "rejects unknown mode" sh "$ROOT/install.sh" --mode nonsense

# --- --scope-ip is refused outside standalone mode ---
assert_fail "rejects --scope-ip with passwall2" \
	sh "$ROOT/install.sh" --mode passwall2 --scope-ip 192.168.1.77 --no-verify

# --- full passwall2 install, with the differential check ---
assert_ok "install --mode passwall2" sh "$ROOT/install.sh" --mode passwall2
assert_ok "state file written" test -f "$STATE"
assert_contains "$(cat $STATE)" "MODE=passwall2" "state records the mode"
assert_contains "$(cat $STATE)" "BACKUP=/etc/config/passwall2.bak-frag-" "state records the backup path"
assert_ok "FRAGDRCT exists" uci -q get passwall2.FRAGDRCT.protocol

FIRST_BACKUP=$(sed -n 's/^BACKUP=//p' "$STATE" | head -1)

# The remaining installs use --no-verify: they exercise mode selection and
# idempotency, not the fragmentation check, and each verification run costs
# ~40s of live probing.

# --- auto mode picks passwall2 on this router ---
assert_ok "install --mode auto" sh "$ROOT/install.sh" --mode auto --no-verify
assert_contains "$(cat $STATE)" "MODE=passwall2" "auto selected passwall2"

# --- re-running is safe ---
assert_ok "install is idempotent" sh "$ROOT/install.sh" --mode passwall2 --no-verify
assert_eq "$(uci show passwall2 | grep -c '^passwall2.FRAGDRCT=')" "1" "no duplicate node after re-install"

# Re-installing must NOT re-take the backup. If it did, the recorded backup
# would be a config that already has our sections wired, and uninstall would
# restore them instead of removing them.
assert_eq "$(sed -n 's/^BACKUP=//p' "$STATE" | head -1)" "$FIRST_BACKUP" \
	"re-install preserves the original backup"

# --- uninstall reverses everything ---
assert_ok "uninstall -y" sh "$ROOT/uninstall.sh" -y
assert_fail "config dir gone"  test -d /etc/xray-frag
assert_fail "FRAGDRCT gone"    uci -q get passwall2.FRAGDRCT.protocol
assert_fail "FragTCP gone"     uci -q get passwall2.FragTCP.network

# --- restore production state, verified for real ---
assert_ok "reinstall for production" sh "$ROOT/install.sh" --mode passwall2

t_summary
