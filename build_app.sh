#!/bin/bash
set -e

# ========= CONFIG =========
APP_NAME="Sync Audio"
PACKAGE_NAME="com.tdevs.skilltrack"
BUILD_TYPE="apk"   # apk | appbundle

# ===== Feature Toggles =====
CHANGE_PACKAGE=false
UPDATE_ANDROID_NAME=false
UPDATE_IOS_NAME=false
GENERATE_ICONS=false
BUILD_APP=true
# ==========================

echo "🔧 Preparing build..."

flutter pub get

# ---------------- Change App Package Name ----------------
if [ "$CHANGE_PACKAGE" = true ]; then
  echo "📦 Changing app package name..."
  flutter pub run change_app_package_name:payment_method "$PACKAGE_NAME"
fi

# ---------------- Android App Name ----------------
if [ "$UPDATE_ANDROID_NAME" = true ]; then
  echo "📱 Updating Android app name..."

  STRINGS_FILE="android/app/src/main/res/values/strings.xml"
  mkdir -p android/app/src/payment_method/res/values

  if [ ! -f "$STRINGS_FILE" ]; then
    cat <<EOF > "$STRINGS_FILE"
<resources>
    <string name="app_name">$APP_NAME</string>
</resources>
EOF
  else
    sed -i.bak "s|<string name=\"app_name\">.*</string>|<string name=\"app_name\">$APP_NAME</string>|" "$STRINGS_FILE"
    rm -f "$STRINGS_FILE.bak"
  fi

  MANIFEST="android/app/src/main/AndroidManifest.xml"
  sed -i.bak 's/android:label="[^"]*"/android:label="@string\/app_name"/' "$MANIFEST"
  rm -f "$MANIFEST.bak"
fi

# ---------------- iOS App Name ----------------
if [ "$UPDATE_IOS_NAME" = true ]; then
  IOS_PLIST="ios/Runner/Info.plist"
  if [ -f "$IOS_PLIST" ]; then
    echo "🍏 Updating iOS app name..."
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName '$APP_NAME'" "$IOS_PLIST"

    SANITIZED_NAME=$(echo "$APP_NAME" | tr -cd '[:alnum:]')
    /usr/libexec/PlistBuddy -c "Set :CFBundleName '$SANITIZED_NAME'" "$IOS_PLIST"
  fi
fi

# ---------------- Launcher Icon ----------------
if [ "$GENERATE_ICONS" = true ]; then
  echo "🎨 Generating launcher icons..."
  flutter pub run flutter_launcher_icons
fi

# ---------------- Build ----------------
if [ "$BUILD_APP" = true ]; then
  echo "🚀 Building app..."

  flutter clean
  flutter pub get

  if [ "$BUILD_TYPE" = "appbundle" ]; then
    flutter build appbundle --release
  else
    flutter build apk --release --split-per-abi

    APK_PATH="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
    TARGET_PATH="$PWD/${APP_NAME}.apk"

    if [ -f "$APK_PATH" ]; then
      mv "$APK_PATH" "$TARGET_PATH"
      echo "📦 APK created: $TARGET_PATH"
    else
      echo "❌ APK not found"
      exit 1
    fi
  fi
fi

echo "✅ Build completed!"