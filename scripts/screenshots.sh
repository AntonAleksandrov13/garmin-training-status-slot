#!/usr/bin/env bash
# Launch the Connect IQ simulator on one or more devices, capture each as a
# PNG in docs/screenshots/, and regenerate docs/screenshots/INDEX.md.
#
# macOS only. The simulator GUI must be on-screen (not minimized, not behind
# another app) during capture.
#
# USAGE
#
#   ./scripts/screenshots.sh                              # devices from manifest.xml
#   ./scripts/screenshots.sh epix2 venu3 fr165            # named subset
#   ./scripts/screenshots.sh --list                       # show installed sim devices
#   ./scripts/screenshots.sh --installed                  # all SDK-installed devices
#   ./scripts/screenshots.sh --amoled                     # AMOLED devices only
#   ./scripts/screenshots.sh --device epix2 --no-loop     # one-shot, no kill loop
#   ./scripts/screenshots.sh --start-at 25                # resume from #25
#   ./scripts/screenshots.sh --from venu3                 # resume from a device
#
# RESUME
#   A batch prints "[N/TOTAL] <device>" per device. If it dies at #25, rerun
#   with --start-at 25 (or --from <that device id>) to continue from there.
#   Indices stay in the original numbering so the same number works again.
#
# ENV
#
#   CIQ_SDK         Connect IQ SDK path. Auto-detected from
#                   ~/Library/Application Support/Garmin/ConnectIQ/Sdks.
#   CIQ_KEY         Developer key (.der). Default: ~/garmin_dev_key.der,
#                   falling back to ~/developer_key.der.
#   WAIT_SECONDS    Seconds to wait after monkeydo before capture. Default 9.
#                   Reels stop at ~3s; the SDK + monkeydo cold-start adds a few
#                   more, so 9s gives margin. Bump higher on slow machines.
#   REBUILD         Set to 1 to always recompile, ignoring bin/prg/<device>.prg.
#
# PREBUILT REUSE
#   If `./scripts/build.sh --all-prg` has produced bin/prg/<device>.prg, this
#   script reuses it instead of recompiling — unless sources are newer than
#   the prebuilt (auto-detected) or REBUILD=1. Otherwise it builds on the fly.

set -euo pipefail
cd "$(dirname "$0")/.."

# ----- argument parsing ----------------------------------------------------

LIST_ONLY=0
USE_INSTALLED=0
USE_AMOLED=0
START_AT=""        # 1-based index to resume from
START_FROM=""      # device id to resume from
DEVICES=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            sed -n '2,34p' "$0" | sed 's/^# //; s/^#//'
            exit 0
            ;;
        --list)         LIST_ONLY=1 ;;
        --installed)    USE_INSTALLED=1 ;;
        --amoled)       USE_AMOLED=1 ;;
        --device)       shift; DEVICES+=("$1") ;;
        --start-at)     shift; START_AT="$1" ;;
        --from)         shift; START_FROM="$1" ;;
        --*)
            echo "unknown flag: $1" >&2
            exit 2
            ;;
        *)              DEVICES+=("$1") ;;
    esac
    shift
done

# ----- environment ---------------------------------------------------------

DEFAULT_SDK=$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"/connectiq-sdk-mac-*/ 2>/dev/null | sort -r | head -n1)
SDK="${CIQ_SDK:-${DEFAULT_SDK%/}}"
DEVICES_DIR="$HOME/Library/Application Support/Garmin/ConnectIQ/Devices"
WAIT_SECONDS="${WAIT_SECONDS:-9}"

# Pick the first key that exists, in this order.
if [ -z "${CIQ_KEY:-}" ]; then
    for candidate in "$HOME/garmin_dev_key.der" "$HOME/developer_key.der"; do
        if [ -f "$candidate" ]; then CIQ_KEY="$candidate"; break; fi
    done
fi

[ -d "$SDK" ] || { echo "Connect IQ SDK not found. Set CIQ_SDK." >&2; exit 1; }
[ -d "$DEVICES_DIR" ] || { echo "Devices dir not found at $DEVICES_DIR" >&2; exit 1; }

# ----- device discovery ----------------------------------------------------

# All devices the SDK can simulate.
all_installed_devices() {
    ls "$DEVICES_DIR"
}

# Subset of installed devices with AMOLED displays.
amoled_devices() {
    for d in $(all_installed_devices); do
        f="$DEVICES_DIR/$d/compiler.json"
        [ -f "$f" ] || continue
        if python3 -c "import json,sys; sys.exit(0 if json.load(open('$f')).get('displayType')=='amoled' else 1)" 2>/dev/null; then
            echo "$d"
        fi
    done
}

manifest_devices() {
    grep -oE 'iq:product id="[^"]+"' manifest.xml | sed 's/iq:product id="//; s/"//'
}

if [ $LIST_ONLY -eq 1 ]; then
    echo "Installed devices in $DEVICES_DIR:"
    all_installed_devices | column
    exit 0
fi

# Resolve the final device list.
if [ ${#DEVICES[@]} -eq 0 ]; then
    if [ $USE_INSTALLED -eq 1 ]; then
        mapfile -t DEVICES < <(all_installed_devices)
    elif [ $USE_AMOLED -eq 1 ]; then
        mapfile -t DEVICES < <(amoled_devices)
    else
        mapfile -t DEVICES < <(manifest_devices)
    fi
fi

[ ${#DEVICES[@]} -gt 0 ] || { echo "No devices to process" >&2; exit 1; }
[ -f "${CIQ_KEY:-}" ] || { echo "Developer key not found. Set CIQ_KEY." >&2; exit 1; }

# Resume support: --from <device> or --start-at <N> (1-based) drops the
# devices before that point so a failed batch can continue where it stopped.
# RESUME_OFFSET keeps the printed [N/TOTAL] in the original numbering.
RESUME_OFFSET=0
ORIG_TOTAL=${#DEVICES[@]}
if [ -n "$START_FROM" ] || [ -n "$START_AT" ]; then
    idx=0
    found=-1
    for i in "${!DEVICES[@]}"; do
        n=$((i + 1))
        if [ -n "$START_AT" ] && [ "$n" -eq "$START_AT" ]; then found=$i; break; fi
        if [ -n "$START_FROM" ] && [ "${DEVICES[$i]}" = "$START_FROM" ]; then found=$i; break; fi
    done
    if [ "$found" -lt 0 ]; then
        echo "Resume target not found (--from='$START_FROM' --start-at='$START_AT')." >&2
        echo "Full list:" >&2
        for i in "${!DEVICES[@]}"; do echo "  $((i + 1))) ${DEVICES[$i]}" >&2; done
        exit 2
    fi
    echo "Resuming at #$((found + 1)) (${DEVICES[$found]}); skipping the first $found."
    DEVICES=("${DEVICES[@]:$found}")
    RESUME_OFFSET=$found
fi

echo "Devices (${#DEVICES[@]}):" "${DEVICES[@]}"
echo "SDK: $SDK"
echo "Key: $CIQ_KEY"
echo

mkdir -p bin docs/screenshots

# ----- simulator lifecycle -------------------------------------------------

wait_for_sim() {
    local tries=0
    until pgrep -x simulator > /dev/null || [ $tries -ge 40 ]; do
        sleep 0.5
        tries=$((tries + 1))
    done
    sleep 3   # window draw + JVM warm-up
}

ensure_sim_running() {
    if ! pgrep -x simulator > /dev/null; then
        echo ">> Launching Connect IQ simulator..."
        open -a "$SDK/bin/ConnectIQ.app"
        wait_for_sim
    fi
}

# A long-lived simulator accumulates state across many device-profile switches
# and intermittently fails to load the app (blank/idle screen — seen on
# instinct3amoled after ~40 switches). Restarting it per device makes every
# capture deterministic. Costs ~5s/device but removes the flakiness.
restart_sim() {
    pkill -f monkeydo 2>/dev/null || true
    pkill -x simulator 2>/dev/null || true
    local tries=0
    while pgrep -x simulator > /dev/null && [ $tries -lt 20 ]; do
        sleep 0.3
        tries=$((tries + 1))
    done
    open -a "$SDK/bin/ConnectIQ.app"
    wait_for_sim
}

# Title of the simulator's main window, or "" if none. A loaded device makes
# the title "CIQ Simulator - <Device> (<ver>)"; an idle sim is just
# "CIQ Simulator".
sim_window_title() {
    osascript -e 'tell application "System Events" to get name of window 1 of process "simulator"' 2>/dev/null || true
}

# Push the app and wait until the simulator window title shows a device (" - ").
# Retries monkeydo a few times because a freshly-launched simulator may not be
# ready to accept the push immediately. Returns the monkeydo PID, or empty on
# total failure.
push_and_verify() {
    local prg="$1" device="$2"
    local attempt mpid title
    for attempt in 1 2 3 4 5; do
        "$SDK/bin/monkeydo" "$prg" "$device" >/dev/null 2>&1 &
        mpid=$!
        sleep "$WAIT_SECONDS"
        title=$(sim_window_title)
        case "$title" in
            *" - "*)
                echo "$mpid"
                return 0
                ;;
        esac
        # Not loaded yet — kill this attempt and retry.
        kill "$mpid" 2>/dev/null || true
        wait "$mpid" 2>/dev/null || true
        echo "   (attempt $attempt: app not loaded, retrying)" >&2
        sleep 2
    done
    return 1
}

stop_monkeydo() {
    local pid="$1"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    fi
}

# ----- main loop -----------------------------------------------------------
# Each device gets a freshly restarted simulator (see restart_sim).

FAILED=()
COUNT=0
for device in "${DEVICES[@]}"; do
    COUNT=$((COUNT + 1))
    echo
    echo "── [$((COUNT + RESUME_OFFSET))/$ORIG_TOTAL] $device ──"

    if [ ! -d "$DEVICES_DIR/$device" ]; then
        echo "   SKIP: device $device not installed in the SDK"
        FAILED+=("$device:not-installed")
        continue
    fi

    out="docs/screenshots/${device}.png"

    # Prefer a pre-built per-device .prg from `build.sh --all-prg`
    # (bin/prg/<device>.prg). Fall back to building on the fly if it is
    # missing or stale relative to the sources. Set REBUILD=1 to force.
    prebuilt="bin/prg/${device}.prg"
    prg="bin/${device}.prg"
    src_newer=0
    if [ -f "$prebuilt" ]; then
        if [ -n "$(find source resources manifest.xml monkey.jungle -newer "$prebuilt" 2>/dev/null | head -1)" ]; then
            src_newer=1
        fi
    fi

    if [ "${REBUILD:-0}" != "1" ] && [ -f "$prebuilt" ] && [ "$src_newer" -eq 0 ]; then
        echo "   using prebuilt $prebuilt"
        prg="$prebuilt"
    else
        if [ -f "$prebuilt" ] && [ "$src_newer" -eq 1 ]; then
            echo "   prebuilt is stale (sources changed) — rebuilding"
        else
            echo "   building $prg"
        fi
        if ! "$SDK/bin/monkeyc" -d "$device" -f monkey.jungle -o "$prg" -y "$CIQ_KEY" 2>&1 | tail -3; then
            echo "   BUILD FAILED"
            FAILED+=("$device:build")
            continue
        fi
    fi

    echo "   restarting simulator (clean state)"
    restart_sim

    echo "   pushing to simulator"
    if ! monkey_pid=$(push_and_verify "$prg" "$device"); then
        echo "   LOAD FAILED (app never loaded after retries)"
        FAILED+=("$device:load")
        continue
    fi

    if scripts/lib/capture.sh "$out"; then
        echo "   captured -> $out"
    else
        echo "   CAPTURE FAILED"
        FAILED+=("$device:capture")
    fi

    stop_monkeydo "$monkey_pid"
done

# ----- gallery -------------------------------------------------------------

{
    echo "# Device gallery"
    echo
    echo "_Auto-generated by \`scripts/screenshots.sh\`. Do not edit by hand._"
    echo
    for png in docs/screenshots/*.png; do
        [ -f "$png" ] || continue
        name=$(basename "$png" .png)
        echo "### $name"
        echo
        echo "![$name]($name.png)"
        echo
    done
} > docs/screenshots/INDEX.md

echo
echo "Wrote docs/screenshots/INDEX.md"
if [ ${#FAILED[@]} -gt 0 ]; then
    echo
    echo "Failures:"
    printf '  %s\n' "${FAILED[@]}"
    exit 1
fi
