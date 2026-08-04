#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIGURATION="${SIGNALCASE_CONFIGURATION:-debug}"
APP_DIR="${PROJECT_DIR}/.build/Signalcase.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
EXECUTABLE_PATH="${PROJECT_DIR}/.build/${CONFIGURATION}/Signalcase"

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

xattr -cr "${APP_DIR}"
codesign --force --sign - "${APP_DIR}" >/dev/null

print "Built ${APP_DIR}"

if [[ "${1:-}" == "--open" ]]; then
    open "${APP_DIR}"
fi

