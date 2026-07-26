#!/usr/bin/env bash
set -euo pipefail

apk_path="${1:-build/app/outputs/flutter-apk/app-debug.apk}"
firebase_app_id="${FIREBASE_ANDROID_APP_ID:-1:553124643634:android:0c7ff23657db82a57c0d2b}"
release_notes="${RELEASE_NOTES:-SyncMesh Audio test build}"

if [[ ! -f "$apk_path" ]]; then
  echo "APK not found: $apk_path" >&2
  exit 1
fi

firebase appdistribution:distribute "$apk_path" \
  --app "$firebase_app_id" \
  --release-notes "$release_notes"
