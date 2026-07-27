#!/bin/bash
set -e

# ========= CONFIG =========
APP_NAME="SyncMesh Audio"
PACKAGE_NAME="io.syncmesh.audio"
BUILD_TYPE="apk"   # apk | appbundle
BUILD_TARGET="${1:-android}" # android | macos | windows
ANDROID_BUILD_MODE="${ANDROID_BUILD_MODE:-release}" # release | debug
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
CREATE_MACOS_DMG=false
CREATE_WINDOWS_INSTALLER=false
WINDOWS_INSTALLER_NAME="SyncAudioSetup"
ISCC_PATH=""
UPLOAD_FIREBASE="${UPLOAD_FIREBASE:-false}"

# GitHub Actions can select debug/release without changing local settings.
if [ "${BUILD_SINGLE_TARGET:-false}" = true ]; then
  ANDROID_BUILD_MODE="${CI_ANDROID_BUILD_MODE:-$ANDROID_BUILD_MODE}"
  OUTPUT_DIR="${CI_OUTPUT_DIR:-$OUTPUT_DIR}"
  CREATE_MACOS_DMG="${CI_CREATE_MACOS_DMG:-$CREATE_MACOS_DMG}"
  CREATE_WINDOWS_INSTALLER="${CI_CREATE_WINDOWS_INSTALLER:-$CREATE_WINDOWS_INSTALLER}"
  WINDOWS_INSTALLER_NAME="${CI_WINDOWS_INSTALLER_NAME:-$WINDOWS_INSTALLER_NAME}"
  ISCC_PATH="${CI_ISCC_PATH:-$ISCC_PATH}"
fi

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

  if [ "$BUILD_TARGET" = "android" ] && [ "$ANDROID_BUILD_MODE" != "release" ] && [ "$ANDROID_BUILD_MODE" != "debug" ]; then
    echo "❌ ANDROID_BUILD_MODE must be release or debug."
    exit 1
  fi

  if [ "$BUILD_TARGET" = "android" ] && [ "$ANDROID_BUILD_MODE" = "release" ] && [ ! -f "android/key.properties" ]; then
    echo "❌ Missing android/key.properties. Copy android/key.properties.example and configure release signing first."
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR"

  flutter clean
  flutter pub get

  if [ "$BUILD_TARGET" = "macos" ]; then
    if [ "$(uname -s)" != "Darwin" ]; then
      echo "❌ macOS builds must run on macOS."
      exit 1
    fi

    flutter build macos --release

    MACOS_APP_PATH="build/macos/Build/Products/Release/SyncMesh Audio.app"
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
      MACOS_DMG_PATH="$PWD/$OUTPUT_DIR/${APP_NAME}.dmg"
      hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGING_DIR" \
        -ov \
        -format UDZO \
        "$MACOS_DMG_PATH"
      echo "📦 macOS DMG created: $MACOS_DMG_PATH"
    fi
  elif [ "$BUILD_TARGET" = "windows" ]; then
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*) ;;
      *)
        echo "❌ Windows builds must run on Windows."
        exit 1
        ;;
    esac

    flutter build windows --release

    WINDOWS_RELEASE_PATH="build/windows/x64/runner/Release"
    WINDOWS_PORTABLE_PATH="$PWD/$OUTPUT_DIR/windows-portable"
    if [ ! -d "$WINDOWS_RELEASE_PATH" ]; then
      echo "❌ Windows release not found: $WINDOWS_RELEASE_PATH"
      exit 1
    fi
    mkdir -p "$WINDOWS_PORTABLE_PATH"
    cp -R "$WINDOWS_RELEASE_PATH/." "$WINDOWS_PORTABLE_PATH/"
    echo "📦 Windows portable build created: $WINDOWS_PORTABLE_PATH"

    if [ "$CREATE_WINDOWS_INSTALLER" = true ]; then
      if [ -z "$ISCC_PATH" ]; then
        ISCC_PATH="$(command -v ISCC.exe 2>/dev/null || command -v iscc 2>/dev/null || true)"
      fi
      if [ -z "$ISCC_PATH" ] && [ -f "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" ]; then
        ISCC_PATH="/c/Program Files (x86)/Inno Setup 6/ISCC.exe"
      fi
      if [ -z "$ISCC_PATH" ]; then
        echo "❌ Inno Setup compiler (ISCC.exe) was not found."
        exit 1
      fi
      "$ISCC_PATH" "/O$OUTPUT_DIR" "/F$WINDOWS_INSTALLER_NAME" "installer/SyncAudio.iss"
      echo "📦 Windows installer created: $OUTPUT_DIR/$WINDOWS_INSTALLER_NAME.exe"
    fi
  elif [ "$BUILD_TYPE" = "appbundle" ]; then
    flutter build appbundle --release
    AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
    TARGET_PATH="$PWD/$OUTPUT_DIR/$APP_NAME.aab"
    mv "$AAB_PATH" "$TARGET_PATH"
    echo "📦 AAB created: $TARGET_PATH"
  else
    flutter build apk --"$ANDROID_BUILD_MODE" --split-per-abi

    APK_PATH="build/app/outputs/flutter-apk/app-arm64-v8a-${ANDROID_BUILD_MODE}.apk"
    SUFFIX=""
    [ "$ANDROID_BUILD_MODE" = "debug" ] && SUFFIX="-debug"
    TARGET_PATH="$PWD/$OUTPUT_DIR/$APP_NAME$SUFFIX.apk"

    if [ -f "$APK_PATH" ]; then
      mv "$APK_PATH" "$TARGET_PATH"
      echo "📦 APK created: $TARGET_PATH"
      if [ "$UPLOAD_FIREBASE" = true ]; then
        if ! command -v firebase >/dev/null 2>&1; then
          echo "❌ Firebase CLI is required for automatic App Distribution upload."
          echo "   Install it and run: firebase login"
          exit 1
        fi
        if [ ! -x "tool/firebase_distribute.sh" ]; then
          echo "❌ Firebase upload helper is missing or not executable."
          exit 1
        fi
        echo "☁️ Uploading APK to Firebase App Distribution..."
        RELEASE_NOTES="${RELEASE_NOTES:-$APP_NAME release $(date -u +%Y-%m-%dT%H:%M:%SZ)}" \
          ./tool/firebase_distribute.sh "$TARGET_PATH"
        echo "☁️ Firebase App Distribution upload completed."
      else
        echo "ℹ️ Firebase upload skipped (UPLOAD_FIREBASE=false)."
      fi
    else
      echo "❌ APK not found"
      exit 1
    fi
  fi
fi

echo "✅ Build completed!"
