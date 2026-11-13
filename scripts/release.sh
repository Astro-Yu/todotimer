#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "${ROOT_DIR}"

CURRENT_VERSION="$(tr -d '[:space:]' < "${ROOT_DIR}/VERSION" 2>/dev/null || echo "1.0.0")"
BUMP_ARG="${1:-}"

if [[ -z "${BUMP_ARG}" ]]; then
    echo "Usage: ./scripts/release.sh [patch|minor|major|X.Y.Z]"
    echo "Current version: ${CURRENT_VERSION}"
    exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_VERSION}"

case "${BUMP_ARG}" in
    patch)
        NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
        ;;
    minor)
        NEW_VERSION="${MAJOR}.$((MINOR + 1)).0"
        ;;
    major)
        NEW_VERSION="$((MAJOR + 1)).0.0"
        ;;
    *)
        if [[ "${BUMP_ARG}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            NEW_VERSION="${BUMP_ARG}"
        else
            echo "Error: Invalid version or bump type '${BUMP_ARG}'. Use patch, minor, major, or X.Y.Z" >&2
            exit 1
        fi
        ;;
esac

TAG="v${NEW_VERSION}"
echo "Preparing release ${TAG} (previous: v${CURRENT_VERSION})..."

# 1. Update VERSION and Info.plist
echo "${NEW_VERSION}" > "${ROOT_DIR}/VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${NEW_VERSION}" "${ROOT_DIR}/Resources/Info.plist"

# 2. Build DMG
"${ROOT_DIR}/scripts/build_dmg.sh" release
DMG_FILE="${ROOT_DIR}/build/FloatingTodoTimer-v${NEW_VERSION}.dmg"

# 3. Commit & Tag
if [[ -n "$(git status --porcelain VERSION Resources/Info.plist)" ]]; then
    git add VERSION Resources/Info.plist
    git commit -m "chore(release): ${TAG}"
fi

if git rev-parse "${TAG}" >/dev/null 2>&1; then
    echo "Tag ${TAG} already exists locally, recreating..."
    git tag -d "${TAG}"
fi
git tag -a "${TAG}" -m "Release ${TAG}"

git push origin main
git push origin "${TAG}" --force

# 4. Create or Update GitHub Release via gh CLI
NOTES=$(cat <<EOF
## FloatingTodoTimer ${TAG}

### 설치 방법
1. 아래 **Assets**에서 **\`FloatingTodoTimer-${TAG}.dmg\`** 파일을 다운로드하여 실행합니다.
2. 열린 창에서 **\`FloatingTodoTimer.app\`을 \`Applications\` 폴더로 드래그**합니다.
3. 최초 1회 실행 시 macOS 보안 안내가 나타나면 **앱 아이콘 우클릭 → 열기**를 선택하거나 터미널에서 아래 명령어를 실행하세요:
   \`\`\`bash
   xattr -cr /Applications/FloatingTodoTimer.app
   \`\`\`
EOF
)

if gh release view "${TAG}" >/dev/null 2>&1; then
    gh release upload "${TAG}" "${DMG_FILE}" --clobber
else
    gh release create "${TAG}" "${DMG_FILE}" \
        --title "FloatingTodoTimer ${TAG}" \
        --notes "${NOTES}"
fi

echo "Release ${TAG} published successfully!"
