#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_arch="$(uname -m)"
test_dir="$(mktemp -d /tmp/dot-glass-check.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
swiftc Widgets/DotGlass/DotModels.swift Widgets/DotGlass/DotDirectory.swift tests/dot-glass/URLPolicyTests.swift -o "$test_dir/policy"
"$test_dir/policy"
swiftc -parse-as-library Widgets/DotGlass/DotModels.swift Widgets/DotGlass/DotUnread.swift tests/dot-glass/UnreadTests.swift -o "$test_dir/unread"
"$test_dir/unread"
node --test tests/dot-glass/adapter.test.mjs
python3 scripts/validate-widgets.py
# Compile against the actual SDK and widget implementation; no account or network traffic.
swiftc -target "${test_arch}-apple-macosx14.0" -emit-library -emit-module -module-name DockDoorWidgetSDK -emit-module-path "$test_dir/DockDoorWidgetSDK.swiftmodule" Sources/DockDoorWidgetSDK/*.swift -o "$test_dir/libDockDoorWidgetSDK.dylib"
install_name_tool -id @rpath/libDockDoorWidgetSDK.dylib "$test_dir/libDockDoorWidgetSDK.dylib"
swiftc -parse-as-library -target "${test_arch}-apple-macosx14.0" -I "$test_dir" -L "$test_dir" -lDockDoorWidgetSDK -Xlinker -rpath -Xlinker "$test_dir" Widgets/DotGlass/*.swift tests/dot-glass/ConnectionTests.swift -o "$test_dir/connection"
"$test_dir/connection"
swiftc -parse-as-library -target "${test_arch}-apple-macosx14.0" -I "$test_dir" -L "$test_dir" -lDockDoorWidgetSDK -Xlinker -rpath -Xlinker "$test_dir" Widgets/DotGlass/*.swift tests/dot-glass/ViewportTests.swift -o "$test_dir/viewport"
"$test_dir/viewport"
if [[ -d build/DotGlass.bundle ]]; then
  swiftc -parse-as-library -target "${test_arch}-apple-macosx14.0" -I "$test_dir" -L "$test_dir" -lDockDoorWidgetSDK -Xlinker -rpath -Xlinker "$test_dir" tests/dot-glass/BundleLoadTests.swift -o "$test_dir/bundle-loader"
  "$test_dir/bundle-loader" "$PWD/build/DotGlass.bundle"
fi
