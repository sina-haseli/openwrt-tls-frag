#!/bin/sh
# Minimal assertion helpers. Sourced by test files.

T_PASSED=0
T_FAILED=0

t_pass() {
	T_PASSED=$((T_PASSED + 1))
	printf '  ok   %s\n' "$1"
}

t_fail() {
	T_FAILED=$((T_FAILED + 1))
	printf '  FAIL %s\n' "$1"
}

assert_eq() {
	# assert_eq <actual> <expected> <message>
	if [ "$1" = "$2" ]; then
		t_pass "$3"
	else
		t_fail "$3 (expected '$2', got '$1')"
	fi
}

assert_contains() {
	# assert_contains <haystack> <needle> <message>
	case "$1" in
		*"$2"*) t_pass "$3" ;;
		*)      t_fail "$3 (missing '$2')" ;;
	esac
}

assert_ok() {
	# assert_ok <message> <command...>
	msg="$1"; shift
	if "$@" >/dev/null 2>&1; then
		t_pass "$msg"
	else
		t_fail "$msg (command failed: $*)"
	fi
}

assert_fail() {
	# assert_fail <message> <command...>
	msg="$1"; shift
	if "$@" >/dev/null 2>&1; then
		t_fail "$msg (command unexpectedly succeeded: $*)"
	else
		t_pass "$msg"
	fi
}

t_summary() {
	printf '\n  %d passed, %d failed\n' "$T_PASSED" "$T_FAILED"
	[ "$T_FAILED" -eq 0 ]
}
