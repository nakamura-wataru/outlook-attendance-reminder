#!/bin/bash
set -euo pipefail
reminder_project="$(cd "$(dirname "$0")" && pwd)"
exec /bin/bash "$reminder_project/scripts/install-app.sh" "$@"
