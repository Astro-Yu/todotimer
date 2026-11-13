#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="FloatingTodoTimer"
CONFIG="${1:-release}"
ROOT_DIR="${0:A:h:h}"
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${TMPDIR:-/tmp}/swiftpm-module-cache"

echo "Building ${APP_NAME} (${CONFIG})..."
cd "${ROOT_DIR}"
swift build -c "${CONFIG}" \
    --disable-sandbox \
    --cache-path "${TMPDIR:-/tmp}/swiftpm-cache" \
    -Xswiftc -module-cache-path -Xswiftc "${TMPDIR:-/tmp}/swift-module-cache" \
    -Xcc "-fmodules-cache-path=${TMPDIR:-/tmp}/clang-module-cache"

BIN_PATH="${ROOT_DIR}/.build/${CONFIG}/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
    echo "Error: Binary not found at ${BIN_PATH}" >&2
    exit 1
fi

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp "${ROOT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"
chmod +x "${MACOS_DIR}/${APP_NAME}"

codesign --force --deep --sign - "${APP_BUNDLE}" >/dev/null 2>&1 || true

echo "Successfully built app bundle at: ${APP_BUNDLE}"
echo "Run with: open \"${APP_BUNDLE}\""
