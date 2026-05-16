#!/usr/bin/env bash
# Capture the Connect IQ Device Simulator's window to a PNG file.
#
# Usage: capture.sh <output.png>
#
# Requires:
# - macOS (uses osascript + screencapture).
# - The simulator must be running with a watch face loaded and the window
#   must be on-screen (not minimized or behind another window).
# - The running terminal needs Accessibility permission to query System
#   Events (System Settings → Privacy & Security → Accessibility).

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <output.png>" >&2
    exit 2
fi
OUT="$1"

# Bring the simulator to the foreground so nothing overlaps before we capture.
osascript -e 'tell application "System Events" to set frontmost of (first process whose name is "simulator") to true' >/dev/null 2>&1 || true
# Tiny wait for the window manager to repaint.
sleep 0.3

# Ask System Events for the position+size of the simulator window whose title
# starts with "CIQ Simulator". Returns "x,y,w,h" or "" on failure.
bounds=$(osascript <<'EOF' 2>/dev/null
tell application "System Events"
    if not (exists process "simulator") then return ""
    tell process "simulator"
        repeat with w in windows
            try
                set t to name of w
                if t starts with "CIQ Simulator" then
                    set p to position of w
                    set s to size of w
                    return ((item 1 of p) as string) & "," & ((item 2 of p) as string) & "," & ((item 1 of s) as string) & "," & ((item 2 of s) as string)
                end if
            end try
        end repeat
        return ""
    end tell
end tell
EOF
)

if [ -z "$bounds" ]; then
    echo "Simulator window not found. Is the simulator running and a watch face loaded?" >&2
    exit 1
fi

# `screencapture -R x,y,w,h` rejects rects that touch the right/bottom edge of
# the display. Clamp the width/height to (screen_size - 1) when the rect would
# overflow. Screen size is the logical desktop bounds reported by Finder.
SCREEN=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null)
SW=$(echo "$SCREEN" | awk -F', ' '{print $3}')
SH=$(echo "$SCREEN" | awk -F', ' '{print $4}')

IFS=',' read -r X Y W H <<< "$bounds"
if [ -n "${SW:-}" ] && [ -n "${SH:-}" ]; then
    MAX_W=$((SW - X - 1))
    MAX_H=$((SH - Y - 1))
    if [ "$W" -gt "$MAX_W" ]; then W=$MAX_W; fi
    if [ "$H" -gt "$MAX_H" ]; then H=$MAX_H; fi
fi

mkdir -p "$(dirname "$OUT")"
# -x mutes shutter sound, -o disables window shadow, -R captures by rect.
screencapture -x -o -R "${X},${Y},${W},${H}" "$OUT"

# Crop off the macOS title bar (top) and the simulator status bar (bottom) so
# only the device render area remains. Bars are ~28pt / ~26pt; convert to
# pixels via the actual capture scale (retina = 2x) so it's resolution-safe.
if command -v magick >/dev/null 2>&1; then
    px_w=$(magick identify -format "%w" "$OUT" 2>/dev/null || echo 0)
    px_h=$(magick identify -format "%h" "$OUT" 2>/dev/null || echo 0)
    if [ "$px_w" -gt 0 ] && [ "$W" -gt 0 ]; then
        # Scale = captured pixels per logical point (×100 for integer math).
        scale100=$(( px_w * 100 / W ))
        TITLE_PT="${TITLE_BAR_PT:-28}"
        STATUS_PT="${STATUS_BAR_PT:-26}"
        crop_top=$(( TITLE_PT * scale100 / 100 ))
        crop_bot=$(( STATUS_PT * scale100 / 100 ))
        new_h=$(( px_h - crop_top - crop_bot ))
        if [ "$new_h" -gt 0 ]; then
            magick "$OUT" -crop "${px_w}x${new_h}+0+${crop_top}" +repage "${OUT}.c.png" \
                && mv "${OUT}.c.png" "$OUT"
        fi
    fi
fi

# Keep every screenshot under SIZE_LIMIT (default 150 KB). The raw retina
# capture is ~2 MB; resizing to a sane width + 256-colour palette + stripped
# metadata brings a watch screenshot to well under 60 KB while staying crisp.
# Steps down through widths/palettes if a busy frame is still too big.
SIZE_LIMIT="${SIZE_LIMIT:-153600}"   # 150 * 1024
fsize() { stat -f%z "$1" 2>/dev/null || echo 0; }

if command -v magick >/dev/null 2>&1; then
    for spec in "480 256" "420 256" "360 256" "320 128" "280 64"; do
        ww=${spec% *}; cc=${spec#* }
        magick "$OUT" -resize "${ww}x" -colors "$cc" -strip "${OUT}.tmp.png" 2>/dev/null || continue
        if [ "$(fsize "${OUT}.tmp.png")" -le "$SIZE_LIMIT" ]; then
            mv "${OUT}.tmp.png" "$OUT"
            break
        fi
        mv "${OUT}.tmp.png" "$OUT"   # keep the smallest attempt as fallback
    done
fi

echo "Wrote $OUT ($(fsize "$OUT") bytes, ${W}x${H} @ ${X},${Y})"
