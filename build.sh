#!/bin/bash
# Builds "M-5 Multitronic.saver" from src/ using the Command Line Tools.
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(xcrun --show-sdk-path)"
NAME="M-5 Multitronic"
EXEC="M5Panel"
OUT="build/${NAME}.saver"

# Build for the host architecture. arm64 macOS starts at 11.0, so the
# 10.15 floor is only valid on Intel.
ARCH="$(uname -m)"
if [ "${ARCH}" = "arm64" ]; then MINVER=11.0; else MINVER=10.15; fi
echo "building ${ARCH}, min macOS ${MINVER}, SDK ${SDK}"

rm -rf build
mkdir -p "${OUT}/Contents/MacOS" "${OUT}/Contents/Resources"

swiftc -emit-object \
  -o build/M5PanelView.o \
  src/M5PanelView.swift \
  -sdk "${SDK}" \
  -target "${ARCH}-apple-macosx${MINVER}" \
  -O -wmo

# Linked with clang rather than swiftc so the result is a loadable bundle
# (MH_BUNDLE) rather than a dylib. The Swift runtime ships with macOS on
# 10.14.4+, so only an rpath to it is needed.
clang -bundle \
  -o "${OUT}/Contents/MacOS/${EXEC}" \
  build/M5PanelView.o \
  -isysroot "${SDK}" \
  -arch "${ARCH}" \
  -mmacosx-version-min=${MINVER} \
  -framework Cocoa \
  -framework ScreenSaver \
  -L"${SDK}/usr/lib/swift" -L/usr/lib/swift \
  -Xlinker -rpath -Xlinker /usr/lib/swift

cp src/Info.plist "${OUT}/Contents/Info.plist"

# Ad-hoc sign so macOS will load it without complaint.
codesign --force --deep --sign - "${OUT}" >/dev/null 2>&1 || \
  echo "note: ad-hoc codesign skipped"

echo "Built ${OUT}"
