#!/usr/bin/env bash
# Builds a debug-signed APK without Gradle, using only Android SDK build tools.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
: "${ANDROID_HOME:?ANDROID_HOME must point to the Android SDK}"
BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-34.0.0}"
PLATFORM="${ANDROID_PLATFORM:-android-34}"
BT_DIR="$ANDROID_HOME/build-tools/$BUILD_TOOLS"
PLATFORM_JAR="$ANDROID_HOME/platforms/$PLATFORM/android.jar"

for tool in aapt2 d8 zipalign apksigner; do
  test -x "$BT_DIR/$tool" || { echo "missing $BT_DIR/$tool" >&2; exit 1; }
done
test -f "$PLATFORM_JAR" || { echo "missing $PLATFORM_JAR" >&2; exit 1; }

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/classes" "$BUILD_DIR/dex"

echo "[1/6] link resources + manifest"
"$BT_DIR/aapt2" link \
  -o "$BUILD_DIR/unsigned.apk" \
  -I "$PLATFORM_JAR" \
  --manifest "$SCRIPT_DIR/AndroidManifest.xml" \
  --min-sdk-version 24 \
  --target-sdk-version 34

echo "[2/6] compile java"
javac -source 17 -target 17 -classpath "$PLATFORM_JAR" -d "$BUILD_DIR/classes" \
  $(find "$SCRIPT_DIR/src" -name '*.java')

echo "[3/6] dex"
"$BT_DIR/d8" --lib "$PLATFORM_JAR" --output "$BUILD_DIR/dex" \
  $(find "$BUILD_DIR/classes" -name '*.class')

echo "[4/6] add classes.dex"
cp "$BUILD_DIR/unsigned.apk" "$BUILD_DIR/unaligned.apk"
(cd "$BUILD_DIR/dex" && zip -q "$BUILD_DIR/unaligned.apk" classes.dex)

echo "[5/6] zipalign"
"$BT_DIR/zipalign" -f 4 "$BUILD_DIR/unaligned.apk" "$BUILD_DIR/aligned.apk"

echo "[6/6] sign"
keytool -genkeypair -noprompt \
  -keystore "$BUILD_DIR/preview.keystore" \
  -storepass android -keypass android \
  -alias preview -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=EdgeEver Plugin Preview,O=EdgeEver,C=US"
"$BT_DIR/apksigner" sign \
  --ks "$BUILD_DIR/preview.keystore" \
  --ks-pass pass:android --key-pass pass:android \
  --out "$BUILD_DIR/edgeever-plugin-preview.apk" \
  "$BUILD_DIR/aligned.apk"
"$BT_DIR/apksigner" verify --print-certs "$BUILD_DIR/edgeever-plugin-preview.apk" | head -3
ls -lh "$BUILD_DIR/edgeever-plugin-preview.apk"
