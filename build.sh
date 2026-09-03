#!/bin/bash
# Builds the screen savers from src/. Requires Xcode (not just the Command Line
# Tools) for a current SDK and the Metal toolchain.
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
MINVER=15.0
ARCHS="x86_64 arm64"

echo "building universal (${ARCHS}), min macOS ${MINVER}"
echo "SDK ${SDK}"

rm -rf build
mkdir -p build

# saver <bundle name> <executable> <Info.plist> <source...>
saver() {
  local name="$1"; local exec="$2"; local plist="$3"; shift 3
  local out="build/${name}.saver"
  mkdir -p "${out}/Contents/MacOS" "${out}/Contents/Resources"

  local slices=()
  for arch in ${ARCHS}; do
    swiftc -emit-object \
      -o "build/${exec}-${arch}.o" \
      "$@" \
      -sdk "${SDK}" \
      -target "${arch}-apple-macosx${MINVER}" \
      -O -wmo

    # Linked with clang rather than swiftc so the result is a loadable bundle
    # (MH_BUNDLE) rather than a dylib.
    clang -bundle \
      -o "build/${exec}-${arch}" \
      "build/${exec}-${arch}.o" \
      -isysroot "${SDK}" \
      -arch "${arch}" \
      -mmacosx-version-min=${MINVER} \
      -framework Cocoa \
      -framework ScreenSaver
    slices+=("build/${exec}-${arch}")
  done

  lipo -create "${slices[@]}" -output "${out}/Contents/MacOS/${exec}"
  cp "${plist}" "${out}/Contents/Info.plist"

  # System Settings shows CFBundleName, not the filename. These drifted apart
  # once already and shipped, because a rename touched only the filename.
  local declared
  declared=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "${out}/Contents/Info.plist")
  if [ "${declared}" != "${name}" ]; then
    echo "ERROR: ${plist} declares CFBundleName '${declared}' but the bundle is '${name}'" >&2
    exit 1
  fi

  # Ad-hoc sign so macOS will load it without complaint.
  codesign --force --deep --sign - "${out}" >/dev/null 2>&1 || \
    echo "note: ad-hoc codesign skipped for ${name}"

  echo "Built ${out}"
}

COUNTER="src/CounterWindow.swift src/DrumDigits.swift src/Hardware.swift src/ChronometerView.swift"

saver "M-5 Multitronic" "M5Panel" src/M5Panel-Info.plist \
      src/M5PanelView.swift

saver "TOS Chronometer - Remaster" "Chronometer" src/Chronometer-Info.plist \
      ${COUNTER}

saver "TOS Chronometer - Classic" "ChronometerRetro" src/ChronometerRetro-Info.plist \
      ${COUNTER} src/ChronometerRetroView.swift

saver "TOS Helm Chronometer" "HelmChronometer" src/HelmChronometer-Info.plist \
      ${COUNTER} src/PanelDial.swift src/HelmChronometerView.swift

saver "TOS Shipboard Clock" "ShipboardClock" src/ShipboardClock-Info.plist \
      ${COUNTER} src/ClockOptions.swift src/ShipboardClockView.swift

saver "M-5 Multitronic with Clock - Remaster" "M5Clock" src/M5Clock-Info.plist \
      src/M5PanelView.swift src/M5ClockView.swift src/ClockOptions.swift ${COUNTER}

saver "M-5 Multitronic with Clock - Classic" "M5ClockRetro" src/M5ClockRetro-Info.plist \
      src/M5PanelView.swift src/M5ClockView.swift src/M5ClockRetroView.swift \
      src/ClockOptions.swift ${COUNTER}
