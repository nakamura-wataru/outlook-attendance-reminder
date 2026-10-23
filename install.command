#!/bin/bash
set -euo pipefail
reminder_project="$(cd "$(dirname "$0")" && pwd)"
if /usr/bin/git -C "$reminder_project" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf '最新版を確認しています…\n'
  /usr/bin/git -C "$reminder_project" pull --ff-only
fi
exec /bin/bash "$reminder_project/scripts/install-app.sh" "$@"
