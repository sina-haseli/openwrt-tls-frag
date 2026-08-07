#!/bin/sh
set -u
. "$ROOT/tests/lib/assert.sh"
. "$ROOT/lib/common.sh"

# --- version_ge: equal ---
assert_ok   "26.6.27 >= 26.6.27"        version_ge 26.6.27 26.6.27

# --- version_ge: clearly newer ---
assert_ok   "26.7.28 >= 26.6.27"        version_ge 26.7.28 26.6.27
assert_ok   "27.0.0 >= 26.6.27"         version_ge 27.0.0  26.6.27
assert_ok   "26.6.28 >= 26.6.27"        version_ge 26.6.28 26.6.27

# --- version_ge: clearly older, must be rejected ---
assert_fail "26.6.26 < 26.6.27"         version_ge 26.6.26 26.6.27
assert_fail "26.5.99 < 26.6.27"         version_ge 26.5.99 26.6.27
assert_fail "25.12.5 < 26.6.27"         version_ge 25.12.5 26.6.27
assert_fail "1.8.24 < 26.6.27"          version_ge 1.8.24  26.6.27

# --- no lexical comparison: 26.10.0 must beat 26.9.0 ---
assert_ok   "26.10.0 >= 26.9.0"         version_ge 26.10.0 26.9.0
assert_fail "26.9.0 < 26.10.0"          version_ge 26.9.0  26.10.0

# --- suffixes are stripped, not compared ---
assert_ok   "26.7.28-1 >= 26.6.27"      version_ge 26.7.28-1 26.6.27
assert_ok   "v26.7.28 >= 26.6.27"       version_ge v26.7.28  26.6.27

# --- short versions treat missing components as zero ---
assert_ok   "27.0 >= 26.6.27"           version_ge 27.0 26.6.27
assert_fail "26.6 < 26.6.27"            version_ge 26.6 26.6.27

# --- XRAY_MIN_VERSION is the documented floor ---
assert_eq "$XRAY_MIN_VERSION" "26.6.27" "XRAY_MIN_VERSION is 26.6.27"

# --- xray_version parses real `xray version` output via a stub ---
xray() {
	echo "Xray 26.7.28 (Xray, Penetrates Everything.) OpenWrt (go1.26.5 linux/arm64)"
	echo "A unified platform for anti-censorship."
}
assert_eq "$(xray_version)" "26.7.28" "xray_version parses version banner"

t_summary
