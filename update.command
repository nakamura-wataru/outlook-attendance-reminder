#!/bin/bash
set -euo pipefail

reminder_project="$(cd "$(dirname "$0")" && pwd)"

if ! /usr/bin/git -C "$reminder_project" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'このファイルは、打刻リマインダーを最初に取得したフォルダで実行してください。\n' >&2
  exit 1
fi

printf '最新版を確認しています…\n'
/usr/bin/git -C "$reminder_project" pull --ff-only
exec /bin/bash "$reminder_project/install.command"
