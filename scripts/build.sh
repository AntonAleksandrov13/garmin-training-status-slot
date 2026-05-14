#!/usr/bin/env bash
# Builds the watch face for the simulator (.prg) and for the store (.iq).
#
# Env vars:
#   CIQ_SDK     Path to the Connect IQ SDK. Defaults to the latest installed
#               under ~/Library/Application Support/Garmin/ConnectIQ/Sdks/.
#   CIQ_KEY     Path to the developer key (.der). Defaults to ~/developer_key.der.
#   CIQ_DEVICE  Target device for the debug .prg. Defaults to epix2.

set -euo pipefail

cd "$(dirname "$0")/.."

DEFAULT_SDK=$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"/connectiq-sdk-mac-*/ 2>/dev/null | sort -r | head -n1)
SDK="${CIQ_SDK:-${DEFAULT_SDK%/}}"
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
