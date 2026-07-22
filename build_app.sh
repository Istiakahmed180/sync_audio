#!/bin/bash
set -e

# ========= CONFIG =========
APP_NAME="Sync Audio"
PACKAGE_NAME="com.tdevs.syncaudio"
BUILD_TYPE="apk"   # apk | appbundle
BUILD_TARGET="${1:-android}" # android | macos
CREATE_MACOS_DMG=true

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
  echo "📦 Package ID is configured in android/app/build.gradle.kts: $PACKAGE_NAME"
  echo "❌ Automatic package renaming is not supported by this script. Update the Gradle namespace and Kotlin package together."
  exit 1
fi

# ---------------- Android App Name ----------------
if [ "$UPDATE_ANDROID_NAME" = true ]; then
  echo "📱 Updating Android app name..."

  STRINGS_FILE="android/app/src/main/res/values/strings.xml"
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

  if [ "$BUILD_TARGET" = "android" ] && [ ! -f "android/key.properties" ]; then
    echo "❌ Missing android/key.properties. Copy android/key.properties.example and configure release signing first."
    exit 1
  fi

  flutter clean
  flutter pub get

  if [ "$BUILD_TARGET" = "macos" ]; then
    if [ "$(uname -s)" != "Darwin" ]; then
      echo "❌ macOS builds must run on macOS."
      exit 1
    fi

    flutter build macos --release

    MACOS_APP_PATH="build/macos/Build/Products/Release/sync_audio.app"
    MACOS_DMG_PATH="$PWD/${APP_NAME}.dmg"
    if [ ! -d "$MACOS_APP_PATH" ]; then
      echo "❌ macOS app not found: $MACOS_APP_PATH"
      exit 1
    fi

    if [ "$CREATE_MACOS_DMG" = true ]; then
      DMG_STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sync-audio-dmg.XXXXXX")
      trap 'rm -rf "$DMG_STAGING_DIR"' EXIT
      cp -R "$MACOS_APP_PATH" "$DMG_STAGING_DIR/"
      ln -s /Applications "$DMG_STAGING_DIR/Applications"
      hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING_DIR" \
        -ov \
        -format UDZO \
        "$MACOS_DMG_PATH"
      echo "📦 macOS DMG created: $MACOS_DMG_PATH"
    fi
  elif [ "$BUILD_TYPE" = "appbundle" ]; then
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
