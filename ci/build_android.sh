#!/usr/bin/env bash
# Build a signed release APK. Used by .github/workflows/android.yml and runnable locally.
#
# Env:
#   GODOT             path to the Godot 4.7.2 editor binary            (default: godot)
#   ANDROID_SDK_ROOT  Android SDK with build-tools                     (required)
#   JAVA_HOME         JDK 17+                                          (required)
#   VERSION_CODE      Android versionCode, must grow with every build  (default: from export_presets.cfg)
#   VERSION_NAME      shown in Android settings                        (default: from export_presets.cfg)
#   RC_SIGNING_SEED   secret seed for the stable signing key; without it a throwaway key is used
#                     and the APK cannot update an install made from a seeded build.
#   OUT               output APK path                                  (default: build/RCPark.apk)
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
OUT="${OUT:-build/RCPark.apk}"
: "${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT must point at the Android SDK}"
: "${JAVA_HOME:?JAVA_HOME must point at a JDK}"
mkdir -p "$(dirname "$OUT")"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- editor settings: tell Godot where the SDK and JDK live
"$GODOT" --headless --editor --quit >/dev/null 2>&1 || true
SETTINGS="$(ls "$HOME"/.config/godot/editor_settings-4*.tres | head -n1)"
sed -i '/^export\/android\/android_sdk_path/d; /^export\/android\/java_sdk_path/d' "$SETTINGS"
printf 'export/android/android_sdk_path = "%s"\nexport/android/java_sdk_path = "%s"\n' "$ANDROID_SDK_ROOT" "$JAVA_HOME" >> "$SETTINGS"

# --- version
if [ -n "${VERSION_CODE:-}" ]; then
	sed -i "s/^version\/code=.*/version\/code=${VERSION_CODE}/" export_presets.cfg
fi
if [ -n "${VERSION_NAME:-}" ]; then
	sed -i "s/^version\/name=.*/version\/name=\"${VERSION_NAME}\"/" export_presets.cfg
	sed -i "s/^config\/version=.*/config\/version=\"${VERSION_NAME}\"/" project.godot
fi

# --- signing key
KS="$WORK/release.p12"
KS_PASS="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
if [ -n "${RC_SIGNING_SEED:-}" ]; then
	python3 ci/make_keystore.py "$KS" "$KS_PASS"
else
	echo "::warning::RC_SIGNING_SEED is not set - signing with a throwaway key (this APK cannot update other builds)"
	keytool -genkeypair -keystore "$KS" -storetype PKCS12 -alias rcpark -keyalg RSA -keysize 3072 -validity 365 \
		-storepass "$KS_PASS" -keypass "$KS_PASS" -dname "CN=RC Park throwaway" >/dev/null 2>&1
fi
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="rcpark"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KS_PASS"

# --- import + export
"$GODOT" --headless --editor --import --path . --quit 2>&1 | tee "$WORK/import.log" >/dev/null
"$GODOT" --headless --path . --export-release "Android" "$OUT" 2>&1 | tee "$WORK/export.log"
if grep -qE "SCRIPT ERROR|Parse Error|ERROR: .*[Ee]xport" "$WORK/import.log" "$WORK/export.log"; then
	echo "::error::Godot reported errors during import/export"; exit 1
fi
[ -s "$OUT" ] || { echo "::error::export produced no APK"; exit 1; }

# --- verify the result
APKSIGNER="$(ls "$ANDROID_SDK_ROOT"/build-tools/*/apksigner | sort -V | tail -n1)"
"$APKSIGNER" verify --print-certs "$OUT" | grep -E "certificate SHA-256|Signer #1 certificate DN"
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
