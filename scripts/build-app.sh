#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build --configuration release
binary_dir="$(swift build --configuration release --show-bin-path)"
bundle="$project_dir/build/Artifacts.noindex/Codex Usage.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/CodexUsage" "$bundle/Contents/MacOS/CodexUsage"
cp "$project_dir/Resources/Info.plist" "$bundle/Contents/Info.plist"
cp "$project_dir/THIRD_PARTY_NOTICES.md" "$bundle/Contents/Resources/THIRD_PARTY_NOTICES.md"
swift "$project_dir/scripts/make-icon.swift" "$project_dir/build"
cp "$project_dir/build/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$bundle"
printf '已生成：%s\n' "$bundle"
