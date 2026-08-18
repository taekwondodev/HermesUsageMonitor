#!/bin/bash
set -euo pipefail

APP="${1:-${HOME}/Applications/HermesUsageMonitor.app}"
APP_NAME="HermesUsageMonitor"
BUNDLE_ID="com.taekwondodev.HermesUsageMonitor"

[[ -d "${APP}" ]] || { printf 'Missing app: %s\n' "${APP}" >&2; exit 1; }
[[ -x "${APP}/Contents/MacOS/${APP_NAME}" ]] || { printf 'Missing executable.\n' >&2; exit 1; }
[[ -f "${APP}/Contents/Info.plist" ]] || { printf 'Missing Info.plist.\n' >&2; exit 1; }
[[ -f "${APP}/Contents/Resources/AppIcon.icns" ]] || { printf 'Missing Finder icon.\n' >&2; exit 1; }
[[ -d "${APP}/Contents/Resources/${APP_NAME}_HermesUsageMonitorApp.bundle" ]] || { printf 'Missing resource bundle.\n' >&2; exit 1; }

actual_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP}/Contents/Info.plist")"
[[ "${actual_id}" == "${BUNDLE_ID}" ]] || { printf 'Unexpected bundle identifier: %s\n' "${actual_id}" >&2; exit 1; }

codesign --verify --deep --strict "${APP}"
open "${APP}"
for _ in {1..50}; do
    pgrep -x "${APP_NAME}" >/dev/null 2>&1 && {
        printf 'Verified: %s\n' "${APP}"
        exit 0
    }
    sleep 0.1
done
printf 'App did not remain running after launch.\n' >&2
exit 1
