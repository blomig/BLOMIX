#!/usr/bin/env bash
# Export une capture d'écran iOS en App Preview App Store (iPhone portrait).
#
# Cible Apple : 886×1920, 30 fps constant, H.264 High@L4.0, AAC stéréo.
# Recadrage : scale + crop centré (pas de stretch).
#
# Usage:
#   ./scripts/export-app-preview.sh [entrée] [sortie]
#
# Exemples:
#   ./scripts/export-app-preview.sh
#   ./scripts/export-app-preview.sh capture_juillet.MP4
#   ./scripts/export-app-preview.sh capture_juillet.MP4 app-preview-iphone.mp4

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${1:-$ROOT/capture_juillet.MP4}"
OUTPUT="${2:-$ROOT/app-preview-iphone.mp4}"

TARGET_W=886
TARGET_H=1920
FPS=30
VIDEO_BITRATE="12M"
AUDIO_BITRATE="256k"

if [[ ! -f "$INPUT" ]]; then
  echo "Fichier introuvable: $INPUT" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ffmpeg est requis (brew install ffmpeg)." >&2
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ffprobe est requis (inclus avec ffmpeg)." >&2
  exit 1
fi

echo "==> Source"
ffprobe -v error \
  -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,avg_frame_rate,codec_name \
  -show_entries format=duration \
  -of default=noprint_wrappers=1 \
  "$INPUT"

DURATION="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$INPUT")"
DURATION_INT="${DURATION%.*}"
if (( DURATION_INT < 15 || DURATION_INT > 30 )); then
  echo "Attention: durée ${DURATION}s — App Store exige 15–30 s." >&2
fi

# scale pour couvrir 886×1920, puis crop centré ; fps constant 30.
VF="scale=${TARGET_W}:${TARGET_H}:force_original_aspect_ratio=increase,crop=${TARGET_W}:${TARGET_H},fps=${FPS}"

echo "==> Export → $OUTPUT (${TARGET_W}x${TARGET_H} @ ${FPS}fps)"
ffmpeg -y -i "$INPUT" \
  -vf "$VF" \
  -c:v libx264 \
  -profile:v high \
  -level:v 4.0 \
  -pix_fmt yuv420p \
  -r "$FPS" \
  -fps_mode cfr \
  -b:v "$VIDEO_BITRATE" \
  -maxrate "$VIDEO_BITRATE" \
  -bufsize 24M \
  -movflags +faststart \
  -c:a aac \
  -b:a "$AUDIO_BITRATE" \
  -ac 2 \
  -ar 44100 \
  "$OUTPUT"

echo "==> Résultat"
ffprobe -v error \
  -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,avg_frame_rate,codec_name,profile,level \
  -select_streams a:0 \
  -show_entries stream=codec_name,sample_rate,channels,bit_rate \
  -show_entries format=duration,size \
  -of default=noprint_wrappers=1 \
  "$OUTPUT"

echo "OK — prêt pour App Store Connect: $OUTPUT"
