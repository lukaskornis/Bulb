#!/bin/zsh
# Renders the README screenshots offscreen from the app's own views. Shows no window.
set -euo pipefail
cd "$(dirname "$0")/.."

tool=$(mktemp -d)/render
swiftc -O Sources/SliderRow.swift Sources/Icon.swift screenshots/main.swift -o "$tool" -framework AppKit
"$tool" screenshots
rm -rf "$(dirname "$tool")"
