#!/bin/bash
# Builds both screensavers from src/ using the Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"

# Build for the host architecture. arm64 macOS starts at 11.0, so the
# 10.15 floor is only valid on Intel.
ARCH="$(uname -m)"
if [ "${ARCH}" = "arm64" ]; then MINVER=11.0; else MINVER=10.15; fi
echo "building ${ARCH}, min macOS ${MINVER}, SDK ${SDK}"

rm -rf build
mkdir -p build

# saver <bundle name> <executable> <Info.plist> <source...>
saver() {
  local name="$1"; local exec="$2"; local plist="$3"; shift 3
  local out="build/${name}.saver"
  mkdir -p "${out}/Contents/MacOS" "${out}/Contents/Resources"

  swiftc -emit-object \
    -o "build/${exec}.o" \
    "$@" \
    -sdk "${SDK}" \
    -target "${ARCH}-apple-macosx${MINVER}" \
    -O -wmo

  # Linked with clang rather than swiftc so the result is a loadable bundle
  # (MH_BUNDLE) rather than a dylib. The Swift runtime ships with macOS on
  # 10.14.4+, so only an rpath to it is needed.
  clang -bundle \
    -o "${out}/Contents/MacOS/${exec}" \
    "build/${exec}.o" \
    -isysroot "${SDK}" \
    -arch "${ARCH}" \
    -mmacosx-version-min=${MINVER} \
    -framework Cocoa \
    -framework ScreenSaver \
    -L"${SDK}/usr/lib/swift" -L/usr/lib/swift \
    -Xlinker -rpath -Xlinker /usr/lib/swift

  cp "${plist}" "${out}/Contents/Info.plist"

  # Ad-hoc sign so macOS will load it without complaint.
  codesign --force --deep --sign - "${out}" >/dev/null 2>&1 || \
    echo "note: ad-hoc codesign skipped for ${name}"

  echo "Built ${out}"
}

COUNTER="src/CounterWindow.swift src/DrumDigits.swift src/Hardware.swift src/ChronometerView.swift"

saver "M-5 Multitronic" "M5Panel" src/M5Panel-Info.plist \
      src/M5PanelView.swift

saver "TOS Chronometer" "Chronometer" src/Chronometer-Info.plist \
      ${COUNTER}

saver "M-5 Multitronic with Clock" "M5Clock" src/M5Clock-Info.plist \
      src/M5PanelView.swift src/M5ClockView.swift ${COUNTER}
