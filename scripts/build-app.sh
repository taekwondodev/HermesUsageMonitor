#!/bin/bash
set -euo pipefail

APP_NAME="HermesUsageMonitor"
BUNDLE_ID="com.taekwondodev.HermesUsageMonitor"
APPLICATIONS_DIR="${HOME}/Applications"
TARGET_APP="${APPLICATIONS_DIR}/${APP_NAME}.app"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE_ROOT=""

cleanup() {
    if [[ -n "${STAGE_ROOT}" && -d "${STAGE_ROOT}" ]]; then
        rm -rf "${STAGE_ROOT}"
    fi
}
trap cleanup EXIT

mkdir -p "${APPLICATIONS_DIR}"
STAGE_ROOT="$(mktemp -d "${APPLICATIONS_DIR}/.${APP_NAME}.XXXXXX")"
STAGE_APP="${STAGE_ROOT}/${APP_NAME}.app"
CONTENTS="${STAGE_APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
mkdir -p "${MACOS}" "${RESOURCES}"

printf 'Building release executable…\n'
(cd "${PROJECT_ROOT}" && swift build -c release --product "${APP_NAME}")
BIN_PATH="$(cd "${PROJECT_ROOT}" && swift build -c release --show-bin-path)"
EXECUTABLE="${BIN_PATH}/${APP_NAME}"
RESOURCE_BUNDLE="${BIN_PATH}/${APP_NAME}_HermesUsageMonitorApp.bundle"

[[ -x "${EXECUTABLE}" ]] || { printf 'Missing release executable: %s\n' "${EXECUTABLE}" >&2; exit 1; }
[[ -d "${RESOURCE_BUNDLE}" ]] || { printf 'Missing SwiftPM resource bundle: %s\n' "${RESOURCE_BUNDLE}" >&2; exit 1; }

cp "${EXECUTABLE}" "${MACOS}/${APP_NAME}"
cp -R "${RESOURCE_BUNDLE}" "${RESOURCES}/"
cp "${PROJECT_ROOT}/scripts/Info.plist" "${CONTENTS}/Info.plist"

ICONSET="${STAGE_ROOT}/AppIcon.iconset"
printf 'Generating Finder icon…\n'
swift "${PROJECT_ROOT}/scripts/generate-app-icon.swift" "${ICONSET}"
iconutil --convert icns --output "${RESOURCES}/AppIcon.icns" "${ICONSET}"

printf 'Signing ad-hoc…\n'
codesign --force --deep --sign - --timestamp=none "${STAGE_APP}"
codesign --verify --deep --strict --verbose=2 "${STAGE_APP}"

if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
    printf '%s is currently running. Close it before installing the new build? [y/N] ' "${APP_NAME}"
    read -r answer </dev/tty
    case "${answer}" in
        y|Y|yes|YES)
            pkill -TERM -x "${APP_NAME}" || true
            for _ in {1..50}; do
                pgrep -x "${APP_NAME}" >/dev/null 2>&1 || break
                sleep 0.1
            done
            if pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
                printf 'The running instance did not exit; installation cancelled.\n' >&2
                exit 1
            fi
            ;;
        *)
            printf 'Installation cancelled; existing app was not modified.\n'
            exit 0
            ;;
    esac
fi

BACKUP="${APPLICATIONS_DIR}/.${APP_NAME}.previous.$$"
if [[ -e "${TARGET_APP}" ]]; then
    mv "${TARGET_APP}" "${BACKUP}"
fi
if ! mv "${STAGE_APP}" "${TARGET_APP}"; then
    if [[ -e "${BACKUP}" ]]; then
        mv "${BACKUP}" "${TARGET_APP}"
    fi
    printf 'Installation failed; previous app restored when available.\n' >&2
    exit 1
fi
rm -rf "${BACKUP}" 2>/dev/null || true

printf 'Installed: %s\n' "${TARGET_APP}"
open "${TARGET_APP}"
