#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${SIGNALCASE_CONFIGURATION:-debug}"
APP_DIR="${PROJECT_DIR}/.build/Signalcase.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
EXECUTABLE_PATH="${PROJECT_DIR}/.build/${CONFIGURATION}/Signalcase"

read_env_value() {
    local key="$1"
    local file="${PROJECT_DIR:h}/website/.env.local"
    [[ -f "${file}" ]] || return 0
    awk -F= -v key="${key}" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "${file}"
}

SUPABASE_URL="${SIGNALCASE_SUPABASE_URL:-$(read_env_value NEXT_PUBLIC_SUPABASE_URL)}"
SUPABASE_PUBLISHABLE_KEY="${SIGNALCASE_SUPABASE_PUBLISHABLE_KEY:-$(read_env_value NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)}"
CLOUD_URL="${SIGNALCASE_CLOUD_URL:-$(read_env_value NEXT_PUBLIC_SITE_URL)}"
CLOUD_URL="${CLOUD_URL:-http://localhost:3002}"

cd "${PROJECT_DIR}"
swift build --configuration "${CONFIGURATION}"

mkdir -p "${MACOS_DIR}"
cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/Signalcase"

INFO_PLIST="${CONTENTS_DIR}/Info.plist"
plutil -create xml1 "${INFO_PLIST}"
plutil -insert CFBundleDevelopmentRegion -string en "${INFO_PLIST}"
plutil -insert CFBundleDisplayName -string Signalcase "${INFO_PLIST}"
plutil -insert CFBundleExecutable -string Signalcase "${INFO_PLIST}"
plutil -insert CFBundleIdentifier -string app.signalcase.mac "${INFO_PLIST}"
plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "${INFO_PLIST}"
plutil -insert CFBundleName -string Signalcase "${INFO_PLIST}"
plutil -insert CFBundlePackageType -string APPL "${INFO_PLIST}"
plutil -insert CFBundleShortVersionString -string 0.1.0 "${INFO_PLIST}"
plutil -insert CFBundleVersion -string 1 "${INFO_PLIST}"
plutil -insert LSMinimumSystemVersion -string 14.0 "${INFO_PLIST}"
plutil -insert NSHighResolutionCapable -bool true "${INFO_PLIST}"
plutil -insert CFBundleURLTypes -json '[{"CFBundleURLName":"app.signalcase.callback","CFBundleURLSchemes":["signalcase"]}]' "${INFO_PLIST}"
plutil -insert SignalcaseCloudURL -string "${CLOUD_URL}" "${INFO_PLIST}"
plutil -insert SignalcaseSupabaseURL -string "${SUPABASE_URL}" "${INFO_PLIST}"
plutil -insert SignalcaseSupabasePublishableKey -string "${SUPABASE_PUBLISHABLE_KEY}" "${INFO_PLIST}"

xattr -cr "${APP_DIR}"
codesign --force --sign - "${APP_DIR}" >/dev/null

print "Built ${APP_DIR}"

if [[ "${1:-}" == "--open" ]]; then
    open "${APP_DIR}"
fi
