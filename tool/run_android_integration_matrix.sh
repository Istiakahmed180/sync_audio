#!/usr/bin/env bash
set -euo pipefail

devices=()
while IFS= read -r device; do
  devices+=("$device")
done < <(adb devices | awk 'NR > 1 && $2 == "device" {print $1}')
count=${#devices[@]}
if (( count < 2 || count > 3 )); then
  echo "Connect exactly 2 or 3 authorized Android devices; found $count." >&2
  adb devices >&2
  exit 2
fi

flutter build apk --debug
for device in "${devices[@]}"; do
  adb -s "$device" install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null
done

for device in "${devices[@]}"; do
  echo "=== Running Android integration test on $device ==="
  flutter test integration_test/android_device_test.dart -d "$device" --reporter expanded
done

echo "Android device matrix passed on $count devices."
