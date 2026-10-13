#!/bin/bash
set -euo pipefail
reminder_project="$(cd "$(dirname "$0")/.." && pwd)"
reminder_clang='/Library/Developer/CommandLineTools/usr/bin/clang'
reminder_sdk='/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk'
if [[ ! -x "$reminder_clang" ]]; then
  reminder_clang="$(/usr/bin/xcrun --find clang)"
  reminder_sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
fi
reminder_output="$(/usr/bin/mktemp "$reminder_project/native/.launcher.XXXXXX")"
reminder_icon_work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/attendance-icon.XXXXXX")"
trap '/bin/rm -f "$reminder_output"; /bin/rm -rf "$reminder_icon_work"' EXIT
"$reminder_clang" -isysroot "$reminder_sdk" -arch arm64 -arch x86_64 -mmacosx-version-min=11.0 -fobjc-arc -framework Cocoa -framework WebKit -Wall -Wextra -Werror -Wno-unused-parameter "$reminder_project/source/launcher.m" -o "$reminder_output"
/bin/chmod 755 "$reminder_output"
/usr/bin/codesign --force --sign - "$reminder_output"
/bin/mv "$reminder_output" "$reminder_project/native/launcher"
cd "$reminder_project/native"
/usr/bin/shasum -a 256 launcher > launcher.sha256
"$reminder_clang" -isysroot "$reminder_sdk" -mmacosx-version-min=11.0 -fobjc-arc -framework Cocoa -Wall -Wextra -Werror "$reminder_project/scripts/render-icon.m" -o "$reminder_icon_work/render-icon"
/bin/mkdir "$reminder_icon_work/AppIcon.iconset"
"$reminder_icon_work/render-icon" "$reminder_icon_work/AppIcon.iconset"
/usr/bin/iconutil -c icns "$reminder_icon_work/AppIcon.iconset" -o "$reminder_project/native/AppIcon.icns"
printf 'Appleシリコン・Intel共通のアプリ実行ファイルを作成しました。\n'
