#!/bin/sh
# One-line bootstrap for xray-frag. OpenWrt has no git, so this fetches a
# tarball instead of cloning.
#
#   install:    curl -fsSL https://raw.githubusercontent.com/sina-haseli/openwrt-tls-frag/master/get.sh | sh
#   with args:  curl -fsSL .../get.sh | sh -s -- --mode standalone
#   uninstall:  curl -fsSL .../get.sh | sh -s -- --uninstall
#
# Everything happens under /tmp (tmpfs): no flash wear, nothing left on disk.
# Override the source with XRAY_FRAG_REPO / XRAY_FRAG_REF.
set -u

REPO=${XRAY_FRAG_REPO:-sina-haseli/openwrt-tls-frag}
REF=${XRAY_FRAG_REF:-master}
URL="https://codeload.github.com/$REPO/tar.gz/refs/heads/$REF"

WORK=/tmp/xray-frag-get.$$
TGZ="$WORK/src.tar.gz"

say()  { printf '[xray-frag] %s\n' "$1" >&2; }
fail() { printf '[xray-frag] ERROR: %s\n' "$1" >&2; exit 1; }

cleanup() { cd /; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

[ "$(id -u)" = "0" ] || fail "must run as root"

mkdir -p "$WORK" || fail "could not create $WORK"

say "fetching $REPO@$REF"
if command -v curl >/dev/null 2>&1; then
	curl -fsSL --max-time 120 "$URL" -o "$TGZ" \
		|| fail "download failed. Check connectivity and that $REPO@$REF exists."
elif command -v wget >/dev/null 2>&1; then
	wget -q -O "$TGZ" "$URL" \
		|| fail "download failed. Check connectivity and that $REPO@$REF exists."
else
	fail "need curl or wget to bootstrap"
fi

[ -s "$TGZ" ] || fail "downloaded archive is empty"

tar -xzf "$TGZ" -C "$WORK" || fail "could not extract the archive (needs gzip-capable tar)"

SRC=$(find "$WORK" -maxdepth 1 -type d -name '*openwrt-tls-frag*' | head -1)
[ -n "$SRC" ]              || fail "unexpected archive layout"
[ -f "$SRC/install.sh" ]   || fail "install.sh missing from the archive"

cd "$SRC" || fail "could not enter $SRC"
chmod +x install.sh uninstall.sh 2>/dev/null

# stdin is the pipe this script arrived on, so never let a child read it.
case "${1:-}" in
	--uninstall)
		say "running uninstaller"
		sh uninstall.sh -y </dev/null
		RC=$?
		;;
	*)
		say "running installer"
		sh install.sh "$@" </dev/null
		RC=$?
		if [ "$RC" -eq 0 ]; then
			say "to remove later:  curl -fsSL https://raw.githubusercontent.com/$REPO/$REF/get.sh | sh -s -- --uninstall"
		fi
		;;
esac

exit "$RC"
