#!/usr/bin/env bash
set -euo pipefail

APP_PATH="/Applications/DormWatt.app"
WIDGET_PATH="${APP_PATH}/Contents/PlugIns/DormWattWidget.appex"
WIDGET_ID="mercury.DormWatt.Widget"
DELAY_SECONDS="${1:-25}"

sleep "${DELAY_SECONDS}"

if [[ ! -d "${WIDGET_PATH}" ]]; then
  exit 0
fi

pkill -f DormWattWidget >/dev/null 2>&1 || true
pluginkit -r "${WIDGET_PATH}" >/dev/null 2>&1 || true
pluginkit -a "${WIDGET_PATH}" >/dev/null 2>&1 || true
pluginkit -e use -i "${WIDGET_ID}" >/dev/null 2>&1 || true

killall pkd >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true
killall chronod >/dev/null 2>&1 || true
killall NotificationCenter >/dev/null 2>&1 || true

open "${APP_PATH}" >/dev/null 2>&1 || true
