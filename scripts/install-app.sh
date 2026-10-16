#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:-}" in
    "") "$project_dir/scripts/build-app.sh" ;;
    --skip-build) ;;
    *) printf '用法：%s [--skip-build]\n' "$0" >&2; exit 1 ;;
esac
bundle="$project_dir/build/Artifacts.noindex/Codex Usage.app"
destination="/Applications/Codex Usage.app"
identifier="local.codexusage.menubar"

if [[ ! -w /Applications ]]; then
    printf '当前用户无法写入 /Applications，请改用生成的 .pkg 安装包。\n' >&2
    exit 1
fi
if [[ -L "$destination" ]]; then
    printf '安装目标是符号链接，无法替换：%s\n' "$destination" >&2
    exit 1
fi
source_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle/Contents/Info.plist")"
if [[ "$source_identifier" != "$identifier" ]]; then
    printf '应用标识不匹配，无法安装。\n' >&2
    exit 1
fi
/usr/bin/codesign --verify --deep --strict "$bundle"
if [[ -e "$destination" ]]; then
    installed_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$installed_identifier" != "$identifier" ]]; then
        printf '同名路径不属于 Codex Usage，无法替换：%s\n' "$destination" >&2
        exit 1
    fi
    if /usr/sbin/lsof -t "$destination/Contents/MacOS/CodexUsage" >/dev/null 2>&1; then
        printf '请先从菜单栏退出 Codex Usage，再运行安装。\n' >&2
        exit 1
    fi
fi

install_tmp="$(mktemp -d /Applications/.codex-usage-install.XXXXXX)"
cleanup() {
    if [[ -d "$install_tmp/previous.app" && ! -e "$destination" ]]; then
        mv "$install_tmp/previous.app" "$destination"
    fi
    rm -rf "$install_tmp"
}
trap cleanup EXIT
/usr/bin/ditto "$bundle" "$install_tmp/Codex Usage.app"
/usr/bin/codesign --verify --deep --strict "$install_tmp/Codex Usage.app"
if [[ -e "$destination" ]]; then
    mv "$destination" "$install_tmp/previous.app"
fi
mv "$install_tmp/Codex Usage.app" "$destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
printf '已安装：%s\n可从“应用程序”双击启动，运行后显示在菜单栏。\n' "$destination"
