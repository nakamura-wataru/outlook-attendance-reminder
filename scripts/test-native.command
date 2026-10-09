#!/bin/bash
set -euo pipefail
reminder_project="$(cd "$(dirname "$0")/.." && pwd)"
reminder_clang='/Library/Developer/CommandLineTools/usr/bin/clang'
reminder_sdk='/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk'
reminder_test="$(/usr/bin/mktemp /private/tmp/attendance-native-test.XXXXXX)"
trap '/bin/rm -f "$reminder_test"' EXIT
"$reminder_clang" -isysroot "$reminder_sdk" -mmacosx-version-min=11.0 -fobjc-arc -framework Cocoa -framework WebKit -Wall -Wextra -Werror -Wno-unused-parameter "$reminder_project/source/launcher.test.m" -o "$reminder_test"
"$reminder_test"
