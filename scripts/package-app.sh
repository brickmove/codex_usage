#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
"$project_dir/scripts/build-app.sh"
bundle="$project_dir/build/Codex Usage.app"
info="$bundle/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
minimum_os="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info")"
architecture="$(/usr/bin/lipo -archs "$bundle/Contents/MacOS/CodexUsage" | tr ' ' '-')"

/usr/bin/codesign --verify --deep --strict "$bundle"
/usr/bin/plutil -lint "$info" "$project_dir/Resources/InstallerComponents.plist"

package_tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-package.XXXXXX")"
trap 'rm -rf "$package_tmp"' EXIT
mkdir -p "$package_tmp/root/Applications" "$project_dir/dist"
/usr/bin/ditto "$bundle" "$package_tmp/root/Applications/Codex Usage.app"
package_name="Codex-Usage-$version-$architecture.pkg"
package="$project_dir/dist/$package_name"
/usr/bin/pkgbuild \
    --root "$package_tmp/root" \
    --component-plist "$project_dir/Resources/InstallerComponents.plist" \
    --identifier "$identifier" \
    --version "$version" \
    --install-location / \
    --ownership recommended \
    --min-os-version "$minimum_os" \
    "$package"
(
    cd "$project_dir/dist"
    /usr/bin/shasum -a 256 "$package_name" > "$package_name.sha256"
)
printf '已生成安装包：%s\n安装位置：/Applications/Codex Usage.app\n' "$package"
