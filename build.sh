#!/usr/bin/env bash
#
# Build LePlay/NeoTube di Termux tanpa mengubah source code proyek.
#
# Pemakaian:
#   bash build.sh              # build release (default, R8 + lint)
#   bash build.sh fast         # release signed, tanpa R8/lint (jauh lebih cepat)
#   bash build.sh debug        # build debug
#   bash build.sh release --offline
#
# Script ini hanya menyiapkan environment dan opsi Gradle. File source,
# build.gradle.kts, dan konfigurasi proyek tidak diubah permanen.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

info() { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[build]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. JDK
# ---------------------------------------------------------------------------
# gradle-wrapper.jar proyek ini butuh Java 21+. JDK 25 dari Termux sudah
# terbukti bisa dipakai; JDK 21 juga didukung kalau terpasang.
find_jdk() {
    local jdk version
    for jdk in "${JAVA_HOME:-}" \
               "$PREFIX/lib/jvm/java-21-openjdk" \
               "$PREFIX/lib/jvm/java-25-openjdk"; do
        [ -n "$jdk" ] || continue
        [ -x "$jdk/bin/java" ] && [ -x "$jdk/bin/javac" ] || continue
        version="$("$jdk/bin/java" -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')"
        case "$version" in
            2[1-9]*|[3-9][0-9]*) printf '%s\n' "$jdk"; return 0 ;;
        esac
    done
    return 1
}

JAVA_HOME="$(find_jdk || true)"
[ -n "$JAVA_HOME" ] || die "JDK 21+ tidak ditemukan. Jalankan: pkg install openjdk-25"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"
info "JDK        : $JAVA_HOME ($("$JAVA_HOME/bin/java" -version 2>&1 | head -n1))"

# ---------------------------------------------------------------------------
# 2. Android SDK
# ---------------------------------------------------------------------------
find_sdk() {
    local sdk
    for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" \
               "$HOME/android-sdk" "$HOME/Android/Sdk" \
               "/data/data/com.termux/files/home/android-sdk"; do
        [ -n "$sdk" ] && [ -d "$sdk/platforms" ] || continue
        # Proyek memakai compileSdk 37. SDK Termux biasanya menyimpan
        # platform sebagai android-37.0, SDK standar sebagai android-37.
        if [ -d "$sdk/platforms/android-37" ] || [ -d "$sdk/platforms/android-37.0" ]; then
            printf '%s\n' "$sdk"
            return 0
        fi
    done
    return 1
}

ANDROID_HOME="$(find_sdk || true)"
[ -n "$ANDROID_HOME" ] || die \
    "Android SDK platform 37 tidak ditemukan. Set ANDROID_HOME ke SDK yang berisi platforms/android-37."
export ANDROID_HOME
export ANDROID_SDK_ROOT="$ANDROID_HOME"

BUILD_TOOLS="$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | sort -V | tail -n1 || true)"
[ -n "$BUILD_TOOLS" ] || die "Build-tools Android tidak ditemukan di $ANDROID_HOME/build-tools"
info "Android SDK: $ANDROID_HOME (build-tools $(basename "$BUILD_TOOLS"))"

# ---------------------------------------------------------------------------
# 3. aapt2 native Termux
# ---------------------------------------------------------------------------
# aapt2 bawaan Android SDK adalah binary x86_64 dan tidak bisa jalan di
# Termux/ARM. Pakai aapt2 native Termux lewat override resmi AGP.
AAPT2="$(command -v aapt2 || true)"
[ -n "$AAPT2" ] || AAPT2="$PREFIX/bin/aapt2"
[ -x "$AAPT2" ] || die "aapt2 tidak ditemukan. Jalankan: pkg install aapt2"
info "aapt2      : $AAPT2 ($("$AAPT2" version 2>&1 | head -n1))"

# ---------------------------------------------------------------------------
# 4. Daemon JVM criteria
# ---------------------------------------------------------------------------
# gradle/gradle-daemon-jvm.properties meminta Eclipse Temurin 21. Gradle di
# Android tidak bisa mengunduh JDK itu (native integration Termux terbatas),
# dan JDK Termux bukan vendor Adoptium. File tersebut disembunyikan hanya
# selama build, lalu dikembalikan oleh trap di bawah.
CRITERIA="$PROJECT_DIR/gradle/gradle-daemon-jvm.properties"
HIDDEN="$PROJECT_DIR/gradle/.gradle-daemon-jvm.properties.termux"

restore_criteria() {
    if [ -f "$HIDDEN" ]; then
        mv -f "$HIDDEN" "$CRITERIA"
    fi
}
trap restore_criteria EXIT INT TERM HUP

# Pulihkan sisa build sebelumnya yang terhenti paksa.
if [ -f "$HIDDEN" ] && [ ! -f "$CRITERIA" ]; then
    mv -f "$HIDDEN" "$CRITERIA"
fi
if [ -f "$CRITERIA" ]; then
    mv -f "$CRITERIA" "$HIDDEN"
    info "Daemon JVM criteria dinonaktifkan sementara (memakai JDK Termux)."
fi

# ---------------------------------------------------------------------------
# 5. Build
# ---------------------------------------------------------------------------
MODE="${1:-release}"
FAST=0
case "$MODE" in
    release) TASK=":app:assembleRelease" ;;
    fast)    TASK=":app:assembleRelease"; FAST=1 ;;
    debug)   TASK=":app:assembleDebug" ;;
    *)       TASK="$MODE" ;;   # izinkan task Gradle lain, mis. :app:test
esac
if [ $# -gt 0 ]; then
    shift
fi

GRADLE_ARGS=(
    "$TASK"
    --console=plain
    --stacktrace
    "-Pandroid.aapt2FromMavenOverride=$AAPT2"
)

if [ "$FAST" = 1 ]; then
    # Release signed dengan keystore release, tetapi tanpa R8/resource shrink
    # dan lint. Cocok untuk uji cepat di HP; APK tetap bisa dipasang di atas
    # versi release sebelumnya. Build penuh tetap: bash build.sh
    INIT_SCRIPT="${TMPDIR:-$HOME/.cache}/neotube-fast-release.gradle"
    cat > "$INIT_SCRIPT" <<'EOF'
gradle.beforeProject { p ->
    p.plugins.withId('com.android.application') {
        p.androidComponents {
            beforeVariants(selector().withBuildType('release')) { variant ->
                variant.minifyEnabled = false
                variant.shrinkResources = false
            }
        }
    }
}
EOF
    GRADLE_ARGS+=(
        -I "$INIT_SCRIPT"
        -x lintVitalAnalyzeRelease
        -x lintVitalReportRelease
        -x lintVitalRelease
    )
    info "Mode FAST: R8/resource shrink/lint dilewati."
fi

info "Mulai build: $TASK"
set +e
bash "$PROJECT_DIR/gradlew" "${GRADLE_ARGS[@]}" "$@"
STATUS=$?
set -e

restore_criteria
trap - EXIT INT TERM HUP

if [ "$STATUS" -ne 0 ]; then
    die "Build gagal (exit $STATUS)."
fi

if [ "$TASK" = ":app:assembleRelease" ]; then
    APK="$PROJECT_DIR/app/build/outputs/apk/release/app-release.apk"
elif [ "$TASK" = ":app:assembleDebug" ]; then
    APK="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"
else
    APK=""
fi

if [ -n "$APK" ] && [ -f "$APK" ]; then
    info "Build berhasil."
    ls -lh "$APK"
else
    warn "Build selesai, tetapi APK tidak ditemukan di lokasi yang diperkirakan."
fi
