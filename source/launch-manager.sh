#!/bin/bash
set -euo pipefail
reminder_resources="$(cd "$(dirname "$0")" && pwd)"
case "$(/usr/bin/uname -m)" in
  arm64) reminder_arch='arm64' ;;
  x86_64) reminder_arch='x64' ;;
  *) printf 'このMacには対応していません。\n' >&2; exit 1 ;;
esac
exec "$reminder_resources/runtime/$reminder_arch/node" "$reminder_resources/app/app-manager.cjs" "$@"
