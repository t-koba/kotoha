#!/usr/bin/env bash
# Dedicated hosted-emulator lifetime. Never run against an existing device/AVD.
set -euo pipefail
for name in ENGINE_BUILD_ROOT ENGINE_TEMP_ROOT ENGINE_BUILD_JOBS ENGINE_NDK_VERSION \
  ENGINE_API ENGINE_ABI ENGINE_SYSTEM_IMAGE ENGINE_AVD_DEVICE ENGINE_EMULATOR_PORT \
  ENGINE_BOOT_SECONDS ENGINE_BOOT_POLL_SECONDS ENGINE_ADB_SECONDS ENGINE_PROBE_SECONDS \
  ENGINE_OUTPUT_BYTES ENGINE_TOKENS ENGINE_DOWNLOAD_SECONDS ENGINE_DEVICE_ROOT ANDROID_HOME FLUTTER_ROOT \
  ENGINE_ACCEPT_TERMS_SHA256 ENGINE_LINKER_MAP_MAX_BYTES ENGINE_NDK_TERMS_MAX_FILES \
  ENGINE_NDK_TERMS_MAX_BYTES ENGINE_NDK_PATCH_MAX_BYTES ENGINE_NDK_PATCH_FETCH_SECONDS \
  ENGINE_NDK_MEMBER_MAX_MEMBERS ENGINE_NDK_MEMBER_MAX_BYTES \
  ENGINE_NDK_MEMBER_MAX_TOOL_OUTPUT_BYTES ENGINE_NDK_MEMBER_SECONDS; do
  test -n "${!name:?required probe configuration}"
done
python3 - <<'PY'
import math, os, re, sys
from pathlib import Path
sys.path.insert(0, 'tools/engine_probe')
from android import device_root
device_root(os.environ['ENGINE_DEVICE_ROOT'])
for name in ('ENGINE_BUILD_ROOT', 'ENGINE_TEMP_ROOT'):
    path = Path(os.environ[name])
    if '..' in path.parts or path.resolve().parent == path.resolve():
        raise SystemExit('invalid root: ' + name)
for key in ('BUILD_JOBS', 'API', 'EMULATOR_PORT', 'OUTPUT_BYTES', 'TOKENS',
            'LINKER_MAP_MAX_BYTES', 'NDK_TERMS_MAX_FILES', 'NDK_TERMS_MAX_BYTES',
            'NDK_PATCH_MAX_BYTES', 'NDK_PATCH_FETCH_SECONDS', 'NDK_MEMBER_MAX_MEMBERS',
            'NDK_MEMBER_MAX_BYTES', 'NDK_MEMBER_MAX_TOOL_OUTPUT_BYTES'):
    value = os.environ['ENGINE_' + key]
    if not value.isascii() or not value.isdigit() or int(value) <= 0:
        raise SystemExit('invalid positive integer: ' + key)
port = int(os.environ['ENGINE_EMULATOR_PORT'])
# Android emulator protocol permits even console ports 5554 through 5682.
if port % 2 or not 5554 <= port <= 5682:
    raise SystemExit('invalid emulator console port')
for key in ('BOOT_SECONDS', 'BOOT_POLL_SECONDS', 'ADB_SECONDS', 'PROBE_SECONDS',
            'DOWNLOAD_SECONDS', 'NDK_MEMBER_SECONDS'):
    value = float(os.environ['ENGINE_' + key])
    if not math.isfinite(value) or value <= 0:
        raise SystemExit('invalid finite positive timeout: ' + key)
if (os.environ['ENGINE_API'] != '35' or os.environ['ENGINE_ABI'] != 'x86_64'
    or os.environ['ENGINE_SYSTEM_IMAGE'] != 'system-images;android-35;default;x86_64'
    or os.environ['ENGINE_NDK_VERSION'] != '28.2.13676358'):
    raise SystemExit('unreviewed native target/toolchain')
if not re.fullmatch('[0-9a-f]{64}', os.environ['ENGINE_ACCEPT_TERMS_SHA256']):
    raise SystemExit('invalid acceptance digest')
PY
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH"
# Refuse to guess SDK defaults; read the pinned Flutter SDK without bootstrapping it.
grep -F 'val ndkVersion: String = "'"$ENGINE_NDK_VERSION"'"' \
  "$FLUTTER_ROOT/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt"
python3 - <<'PY'
import json, os
from pathlib import Path
version = json.loads((Path(os.environ['FLUTTER_ROOT']) / 'bin/cache/flutter.version.json').read_text())
if version['frameworkRevision'] != 'c197ca5199e9ee5661e865596c9c07294dfab51c':
    raise SystemExit('unexpected Flutter source revision')
PY
test ! -e "$ENGINE_BUILD_ROOT" # clean Ninja dependency database, not stale history
mkdir -p "$ENGINE_BUILD_ROOT"
build=$(realpath "$ENGINE_BUILD_ROOT")
owner=$(mktemp -d "$ENGINE_TEMP_ROOT/kotoha-engine-XXXXXX")
emulator_pid=''
cleanup() {
  status=$?
  trap - EXIT
  set +e
  if [[ -n "$emulator_pid" ]]; then
    # Kill only the owned session/process group. setsid isolates the emulator
    # (and any children it forks) in its own group; a negative PID addresses
    # that group alone, never an unrelated process. SIGKILL is deliberate: no
    # inherited-group process survives even if ADB/device cleanup has failed.
    # Detached helpers, cancellation and runner loss rely on runner teardown.
    kill -KILL -- -"$emulator_pid"
    killed=$?
    wait "$emulator_pid"
    waited=$?
    if [[ "$killed" != 0 || "$waited" != 137 ]]; then status=1; fi
    tail -c "$ENGINE_OUTPUT_BYTES" "$build/emulator.log"
    if [[ $? != 0 ]]; then status=1; fi
  fi
  rm -r "$owner"
  if [[ $? != 0 ]]; then status=1; fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 1' INT TERM
export ANDROID_AVD_HOME="$owner/avd"
avd_name="kotoha-engine-${owner##*/}"
mkdir "$ANDROID_AVD_HOME"
ndk="$ANDROID_HOME/ndk/$ENGINE_NDK_VERSION"
sdkmanager "platform-tools" "emulator" "ndk;$ENGINE_NDK_VERSION" "$ENGINE_SYSTEM_IMAGE" > "$build/sdk.log" 2>&1
cp "$ndk/source.properties" "$build/ndk.properties"
python3 tools/engine_probe/capture_ndk_terms.py --ndk "$ndk" \
  --expected-version "$ENGINE_NDK_VERSION" --max-files "$ENGINE_NDK_TERMS_MAX_FILES" \
  --max-bytes "$ENGINE_NDK_TERMS_MAX_BYTES" --output "$build/ndk-terms"
patch_capture_status=0
python3 tools/engine_probe/capture_android_patch_sources.py \
  --output "$build/ndk-patch-sources" --max-bytes "$ENGINE_NDK_PATCH_MAX_BYTES" \
  --fetch-timeout-seconds "$ENGINE_NDK_PATCH_FETCH_SECONDS" \
  > "$build/patch-source-capture.log" 2>&1 || patch_capture_status=$?
cat "$build/patch-source-capture.log"
cmake -S tools/engine_probe -B "$build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ndk/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ENGINE_ABI" -DANDROID_PLATFORM="android-$ENGINE_API" \
  -DANDROID_STL=c++_static -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  > "$build/configure.log" 2>&1
cmake --build "$build" --target llama-simple --parallel "$ENGINE_BUILD_JOBS" --verbose > "$build/build.log" 2>&1
python3 tools/engine_probe/linker_map.py "$build/llama-simple.map.pending" \
  --max-bytes "$ENGINE_LINKER_MAP_MAX_BYTES" --output-dir "$build/validated-linker-map" \
  --build-root "$build" --ndk-root "$ndk"
llvm="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
member_capture_status=0
python3 tools/engine_probe/capture_ndk_member_debug.py \
  --archive-manifest "$build/validated-linker-map/llama-simple.map.archives.json" \
  --linker-map "$build/validated-linker-map/llama-simple.map" --ndk-root "$ndk" \
  --llvm-ar "$llvm/llvm-ar" --llvm-readelf "$llvm/llvm-readelf" \
  --temp-root "$owner" --output "$build/ndk-member-debug/ndk-member-debug.json" \
  --max-members "$ENGINE_NDK_MEMBER_MAX_MEMBERS" \
  --max-object-bytes "$ENGINE_NDK_MEMBER_MAX_BYTES" \
  --max-tool-output-bytes "$ENGINE_NDK_MEMBER_MAX_TOOL_OUTPUT_BYTES" \
  --max-diagnostic-bytes "$ENGINE_OUTPUT_BYTES" \
  --timeout-seconds "$ENGINE_NDK_MEMBER_SECONDS" \
  > "$build/ndk-member-debug-capture.log" 2>&1 || member_capture_status=$?
cat "$build/ndk-member-debug-capture.log"
ninja -C "$build" -t deps > "$build/ninja-deps.txt"
ninja -C "$build" -t commands llama-simple > "$build/selected-commands.txt"
ninja -C "$build" -t query bin/llama-simple > "$build/link-inputs.txt"
capture_status=0
python3 tools/engine_probe/ninja_reads.py --build "$build" --source "$build/_deps/llama_cpp-src" \
  --ndk "$ndk" --probe "$PWD/tools/engine_probe" || capture_status=$?
"$llvm/clang" --version > "$build/compiler.log"
"$llvm/llvm-readelf" -h -l -d "$build/bin/llama-simple" > "$build/linkage.log"
sha256sum "$build/bin/llama-simple" "$llvm/clang" "$llvm/llvm-readelf" > "$build/executable-tool-sha256.txt"
# Total download deadline in addition to per-network-I/O timeout. No retries.
timeout "${ENGINE_DOWNLOAD_SECONDS}s" python3 tools/engine_probe/acquire.py \
  --directory "$owner/model" --accept-terms-sha256 "$ENGINE_ACCEPT_TERMS_SHA256" \
  --timeout-seconds "$ENGINE_DOWNLOAD_SECONDS" > "$build/acquire.log" 2>&1
test -c /dev/kvm
sudo chmod a+rw /dev/kvm
# Refuse occupied console/ADB ports before launch; never attach to another AVD.
python3 - <<'PYPORT'
import os, socket
sockets = []
for port in (int(os.environ['ENGINE_EMULATOR_PORT']), int(os.environ['ENGINE_EMULATOR_PORT']) + 1):
    sock = socket.socket()
    sock.bind(('127.0.0.1', port))
    sockets.append(sock)
PYPORT
echo no | avdmanager create avd --name "$avd_name" --package "$ENGINE_SYSTEM_IMAGE" \
  --device "$ENGINE_AVD_DEVICE" > "$build/avd.log" 2>&1
test -s "$ANDROID_AVD_HOME/$avd_name.ini"
# Disable job control so the background child is not already a group leader:
# setsid then execs without forking and its group ID is exactly $!.
set +m
# Cleanup kills this group, not unrelated processes.
setsid emulator -avd "$avd_name" -port "$ENGINE_EMULATOR_PORT" -no-window -no-audio \
  -no-boot-anim -no-snapshot -gpu swiftshader_indirect -accel on > "$build/emulator.log" 2>&1 &
emulator_pid=$!
export ENGINE_SERIAL="emulator-$ENGINE_EMULATOR_PORT"
export emulator_pid
# Every ADB command selects the owned emulator, including the boot poll.
timeout "${ENGINE_BOOT_SECONDS}s" bash -c '
  until [[ "$(timeout "${ENGINE_ADB_SECONDS}s" adb -s "$ENGINE_SERIAL" shell -T getprop sys.boot_completed | tr -d "\r")" == 1 ]]; do
    kill -0 "$emulator_pid" || exit 1
    sleep "$ENGINE_BOOT_POLL_SECONDS"
  done'
python3 tools/engine_probe/android.py --adb "$ANDROID_HOME/platform-tools/adb" \
  --serial "$ENGINE_SERIAL" --avd-name "$avd_name" --device-root "$ENGINE_DEVICE_ROOT" \
  --executable "$build/bin/llama-simple" --fixture-dir "$owner/model" \
  --accept-terms-sha256 "$ENGINE_ACCEPT_TERMS_SHA256" --tokens "$ENGINE_TOKENS" \
  --timeout-seconds "$ENGINE_PROBE_SECONDS" --adb-timeout-seconds "$ENGINE_ADB_SECONDS" \
  --output-bytes "$ENGINE_OUTPUT_BYTES" > "$build/smoke.log" 2>&1
if [[ "$capture_status" != 0 ]]; then exit "$capture_status"; fi
if [[ "$patch_capture_status" != 0 ]]; then exit "$patch_capture_status"; fi
if [[ "$member_capture_status" != 0 ]]; then exit "$member_capture_status"; fi
cat "$build/android-compiler-summary.txt"
