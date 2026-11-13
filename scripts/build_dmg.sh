#!/usr/bin/env zsh
set -euo pipefail

APP_NAME="FloatingTodoTimer"
CONFIG="${1:-release}"
ROOT_DIR="${0:A:h:h}"
VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION" 2>/dev/null || echo "1.0.0")"
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
VERSIONED_DMG_PATH="${BUILD_DIR}/${APP_NAME}-v${VERSION}.dmg"
LATEST_DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
STAGING_DIR="/tmp/${APP_NAME}-dmg-staging"

export CLANG_MODULE_CACHE_PATH="/tmp/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="/tmp/swiftpm-module-cache"

cd "${ROOT_DIR}"

# 1. Generate AppIcon.icns if needed
if [[ ! -f "${ROOT_DIR}/Resources/AppIcon.icns" ]]; then
    echo "Generating AppIcon.icns..."
    swift -module-cache-path "/tmp/swift-module-cache" "${ROOT_DIR}/scripts/generate_icon.swift"
fi

# 2. Build the .app bundle
"${ROOT_DIR}/scripts/build_app.sh" "${CONFIG}"

# 3. Prepare DMG staging directory with .app and /Applications symlink
echo "Preparing DMG staging directory..."
rm -rf "${STAGING_DIR}" "${VERSIONED_DMG_PATH}" "${LATEST_DMG_PATH}"
mkdir -p "${STAGING_DIR}"
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

# 4. Create compressed .dmg image
echo "Creating ${VERSIONED_DMG_PATH}..."
hdiutil create \
    -volname "${APP_NAME} v${VERSION}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${VERSIONED_DMG_PATH}"

cp "${VERSIONED_DMG_PATH}" "${LATEST_DMG_PATH}"
rm -rf "${STAGING_DIR}"

echo "Successfully created DMG installer:"
echo "  - ${VERSIONED_DMG_PATH}"
echo "  - ${LATEST_DMG_PATH}"
