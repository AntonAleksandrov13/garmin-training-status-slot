#!/usr/bin/env bash
# Builds the watch face.
#
#   ./scripts/build.sh            debug .prg (one device) + release .iq (all)
#   ./scripts/build.sh --all-prg  one per-device .prg for every manifest device
#                                 into bin/prg/<device>.prg  (for USB sideload)
#
# A .prg is device-specific by design — there is no single universal .prg.
# The .iq bundle is the "all devices" artifact (store / Garmin Express pick
# the right binary per watch). Use --all-prg only if you sideload via USB.
#
# Env vars:
#   CIQ_SDK     Path to the Connect IQ SDK. Defaults to the latest installed
#               under ~/Library/Application Support/Garmin/ConnectIQ/Sdks/.
#   CIQ_KEY     Path to the developer key (.der). Defaults to ~/developer_key.der.
#   CIQ_DEVICE  Target device for the debug .prg. Defaults to epix2.

set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-default}"

# Auto-detect SDK location across macOS / Linux.
if [ -z "${CIQ_SDK:-}" ]; then
  case "$(uname)" in
    Darwin)
      CIQ_SDK=$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"/connectiq-sdk-mac-*/ 2>/dev/null | sort -r | head -n1)
      ;;
    Linux)
      CIQ_SDK=$(ls -d "$HOME/.cache/connectiq"/connectiq-sdk-lin-*/ 2>/dev/null | sort -r | head -n1)
      ;;
  esac
fi
SDK="${CIQ_SDK%/}"
KEY="${CIQ_KEY:-$HOME/developer_key.der}"
DEVICE="${CIQ_DEVICE:-epix2}"

if [ ! -d "$SDK" ]; then
  echo "Connect IQ SDK not found. Set CIQ_SDK or install via Garmin's SDK Manager." >&2
  exit 1
fi
if [ ! -f "$KEY" ]; then
  echo "Developer key not found at $KEY. Set CIQ_KEY or generate one:" >&2
  echo "  openssl genrsa | openssl pkcs8 -topk8 -outform DER -nocrypt -out developer_key.der" >&2
  exit 1
fi

mkdir -p bin

if [ "$MODE" = "--all-prg" ]; then
  mkdir -p bin/prg
  devices=$(grep -oE 'iq:product id="[^"]+"' manifest.xml | sed 's/.*id="//;s/"//')
  total=$(echo "$devices" | wc -w | tr -d ' ')
  n=0
  failed=""
  for d in $devices; do
    n=$((n + 1))
    printf '[%2d/%s] %s ... ' "$n" "$total" "$d"
    if "$SDK/bin/monkeyc" -d "$d" -f monkey.jungle \
         -o "bin/prg/${d}.prg" -y "$KEY" >/dev/null 2>&1; then
      echo "ok"
    else
      echo "FAILED"
      failed="$failed $d"
    fi
  done
  echo
  if [ -n "$failed" ]; then
    echo "Failed:$failed" >&2
    exit 1
  fi
  echo "Done. Per-device .prg files in bin/prg/ (sideload the one matching"
  echo "your watch to /Volumes/GARMIN/GARMIN/APPS/)."
  exit 0
fi

echo "Building debug .prg for $DEVICE..."
"$SDK/bin/monkeyc" -d "$DEVICE" -f monkey.jungle \
  -o bin/trainingstatusslot.prg -y "$KEY"

echo "Building release .iq (all devices)..."
"$SDK/bin/monkeyc" -e -f monkey.jungle \
  -o bin/trainingstatusslot.iq -y "$KEY" --release

echo
echo "Done."
echo "  bin/trainingstatusslot.prg  (sideload to /Volumes/GARMIN/GARMIN/APPS/)"
echo "  bin/trainingstatusslot.iq   (upload to Connect IQ developer dashboard)"
