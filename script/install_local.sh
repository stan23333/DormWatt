#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="DormWatt"
APP_ID="mercury.DormWatt"
WIDGET_ID="mercury.DormWatt.Widget"
DERIVED_DATA="$(mktemp -d "${TMPDIR:-/tmp}/DormWattInstall.XXXXXX")"
APP_DST="/Applications/${APP_NAME}.app"
WIDGET_DST="${APP_DST}/Contents/PlugIns/DormWattWidget.appex"

cleanup() {
  rm -rf "${DERIVED_DATA}"
}
trap cleanup EXIT

cd "${ROOT_DIR}"

echo "Stopping running app and widget..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
pkill -f DormWattWidget >/dev/null 2>&1 || true

echo "Removing stale unsigned debug copies..."
rm -rf "${ROOT_DIR}/build/DerivedData" "${ROOT_DIR}/build/InstallDerivedData"
find "${HOME}/Library/Developer/Xcode/DerivedData" -maxdepth 1 -type d -name "DormWatt-*" -exec rm -rf {} + 2>/dev/null || true

echo "Building ${APP_NAME}..."
xcodebuild build \
  -project DormWatt.xcodeproj \
  -scheme DormWatt \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA}" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet

APP_SRC="${DERIVED_DATA}/Build/Products/Debug/${APP_NAME}.app"
WIDGET_SRC="${APP_SRC}/Contents/PlugIns/DormWattWidget.appex"

echo "Ad-hoc signing app and widget with local App Group entitlements..."
codesign --force --sign - --entitlements DormWattWidget/DormWattWidget.entitlements "${WIDGET_SRC}"
codesign --force --sign - --entitlements DormWatt/DormWatt.entitlements "${APP_SRC}"

echo "Installing to ${APP_DST}..."
pluginkit -r "${WIDGET_DST}" >/dev/null 2>&1 || true
rm -rf "${APP_DST}"
ditto "${APP_SRC}" "${APP_DST}"
codesign --force --sign - --entitlements DormWattWidget/DormWattWidget.entitlements "${WIDGET_DST}"
codesign --force --sign - --entitlements DormWatt/DormWatt.entitlements "${APP_DST}"

echo "Refreshing LaunchServices and WidgetKit caches..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${APP_DST}"
pluginkit -a "${WIDGET_DST}"
killall pkd >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true
killall chronod >/dev/null 2>&1 || true
killall NotificationCenter >/dev/null 2>&1 || true

echo "Launching ${APP_NAME}..."
open "${APP_DST}"
sleep 3

echo "Installed versions:"
printf "  app: "
defaults read "${APP_DST}/Contents/Info" CFBundleVersion
printf "  widget: "
defaults read "${WIDGET_DST}/Contents/Info" CFBundleVersion

echo "Registered widget:"
pluginkit -m -A -D -v | grep "${WIDGET_ID}" || {
  echo "Widget registration not found for ${WIDGET_ID}" >&2
  exit 1
}

echo "Checking for stale duplicate widget bundles..."
if find "${ROOT_DIR}/build" "${HOME}/Library/Developer/Xcode/DerivedData" -path "*${APP_NAME}*.app/Contents/PlugIns/DormWattWidget.appex" -print 2>/dev/null | grep -q .; then
  echo "Found stale duplicate widget bundles after install." >&2
  exit 1
fi

echo "${APP_NAME} installed and widget cache refreshed."
