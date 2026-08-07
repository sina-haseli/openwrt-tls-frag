#!/bin/sh
# Every shipped shell file must parse under POSIX sh and contain no CR bytes.
set -u
. "$ROOT/tests/lib/assert.sh"

FILES="install.sh uninstall.sh
lib/common.sh lib/core.sh lib/verify.sh lib/mode_passwall2.sh lib/mode_standalone.sh
files/etc/init.d/xray-frag files/usr/bin/xray-frag-stats"

for f in $FILES; do
	p="$ROOT/$f"
	if [ ! -f "$p" ]; then
		t_fail "$f exists"
		continue
	fi
	assert_ok "$f parses" sh -n "$p"
	if grep -q "$(printf '\r')" "$p"; then
		t_fail "$f is LF-only"
	else
		t_pass "$f is LF-only"
	fi
done

t_summary
