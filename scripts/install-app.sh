#!/bin/bash
set -euo pipefail
reminder_project="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(/usr/bin/uname -s)" != Darwin ]]; then
  printf 'このアプリはMac専用です。\n' >&2; exit 1
fi
reminder_os_major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d . -f 1)"
if (( reminder_os_major < 11 )); then
  printf 'macOS 11以降が必要です。\n' >&2; exit 1
fi
reminder_machine="$(/usr/bin/uname -m)"
if [[ "$(/usr/sbin/sysctl -n sysctl.proc_translated 2>/dev/null || true)" == 1 ]]; then reminder_machine=arm64; fi
case "$reminder_machine" in
  arm64) reminder_arch=arm64; reminder_sha=23b25245dcfb9af7262f8ff142e9e2e0af025368117329e7a7458a51e5922f53 ;;
  x86_64) reminder_arch=x64; reminder_sha=8a677b0219178efd6eb0e475457c4afb452b521a92f6e67845a73bd85727f2a8 ;;
  *) printf 'このMacの種類には対応していません。\n' >&2; exit 1 ;;
esac
reminder_cache="${ATTENDANCE_RUNTIME_CACHE:-$reminder_project/.cache/runtime}"
mkdir -p "$reminder_cache"
reminder_cache="$(cd "$reminder_cache" && pwd)"
reminder_archive="$reminder_cache/node-v22.23.3-darwin-$reminder_arch.tar.gz"
reminder_runtime="$reminder_cache/node-v22.23.3-darwin-$reminder_arch"
reminder_verify_archive() {
  [[ -f "$reminder_archive" ]] && [[ "$(/usr/bin/shasum -a 256 "$reminder_archive" | /usr/bin/cut -d ' ' -f 1)" == "$reminder_sha" ]]
}
if ! reminder_verify_archive; then
  printf 'アプリ専用のNode.jsを準備しています（初回は約50MB）。\n'
  reminder_partial="$(/usr/bin/mktemp "$reminder_cache/.download.XXXXXX")"
  trap '/bin/rm -f "$reminder_partial"' EXIT
  /usr/bin/curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --retry 2 --connect-timeout 20 --max-time 300 \
    "https://nodejs.org/download/release/v22.23.3/node-v22.23.3-darwin-$reminder_arch.tar.gz" -o "$reminder_partial"
  if [[ "$(/usr/bin/shasum -a 256 "$reminder_partial" | /usr/bin/cut -d ' ' -f 1)" != "$reminder_sha" ]]; then
    printf 'Node.jsの検証に失敗しました。既存のアプリは変更していません。\n' >&2; exit 1
  fi
  /bin/mv "$reminder_partial" "$reminder_archive"
  trap - EXIT
fi
# Expand only the verified official archive, including npm for Macs without Node.js.
/usr/bin/tar -xzf "$reminder_archive" -C "$reminder_cache"
export PATH="$reminder_runtime/bin:$PATH"
cd "$reminder_project"
if [[ "${1:-}" == --dependencies-ready ]]; then shift; fi
exec "$reminder_runtime/bin/node" "$reminder_project/scripts/install-app.cjs" --runtime "$reminder_runtime" --arch "$reminder_arch" "$@"
