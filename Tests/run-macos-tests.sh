#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Эти проверки требуют macOS и Command Line Tools.' >&2
  exit 1
fi
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
xcrun swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/BetterTokenPanel/LowBalancePolicy.swift" \
  "$ROOT/Sources/BetterTokenPanel/DetectorSupport.swift" \
  "$ROOT/Sources/BetterTokenPanel/PanelNavigation.swift" \
  "$ROOT/Sources/BetterTokenPanel/Credentials.swift" \
  "$ROOT/Sources/BetterTokenPanel/BalanceMonitor.swift" \
  "$ROOT/Sources/BetterTokenPanel/PanelModel.swift" \
  "$ROOT/Tests/model.test.swift" \
  -framework AppKit -framework SwiftUI -framework WebKit -framework Security \
  -o "$TEMP/model-tests"
"$TEMP/model-tests"
xcrun swiftc -parse-as-library -swift-version 5 \
  "$ROOT/Sources/BetterTokenPanel/LowBalancePolicy.swift" \
  "$ROOT/Tests/low-balance.test.swift" -o "$TEMP/low-balance-tests"
"$TEMP/low-balance-tests"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/Sources/BetterTokenPanel/LaunchAtLogin.swift" \
  "$ROOT/Tests/launch-at-login.test.swift" \
  -framework AppKit -framework SwiftUI -framework ServiceManagement \
  -o "$TEMP/launch-at-login-tests"
"$TEMP/launch-at-login-tests"
