#!/bin/bash
#
# resize-recipe-photos.sh — batch-shrink a folder of recipe photos (PNG or
# JPG) before importing them into the app, so PhotoStore isn't holding
# multi-MB originals for 500+ recipes.
#
# Defaults (1000px width, JPEG quality 78) were picked by comparing several
# width/quality combos against a real sample photo: no visible quality loss
# at normal viewing distance, ~85-90% smaller than the original PNGs. Sized
# for Recipe Detail's hero image (full-width, cropped to a fixed height —
# only the width dimension really matters for sharpness there) with some
# headroom for eventual AppleTV display.
#
# Usage:
#   ./resize-recipe-photos.sh <folder> [options]
#
# Options:
#   -o, --output <name>     Output subfolder name, created inside <folder>.
#                            Default: resized
#   -w, --width <px>        Target width in pixels (height scales to match).
#                            Default: 1000
#   -q, --quality <0-100>   JPEG quality. Default: 78
#   -s, --suffix <text>     Appended to each filename before the extension.
#                            Default: -resized
#   -p, --skip-pattern <glob>  Filenames matching this glob (checked
#                            against the basename) are left alone. Default:
#                            00-* — matches the contact-sheet/manifest
#                            naming convention these photo folders use
#                            (00-contact-sheet.jpg, 00-file-manifest.txt),
#                            so those don't get treated as recipe photos.
#                            Pass '' to disable and process everything.
#   -h, --help              Show this help and exit
#
# Originals are never modified or deleted — this only ever writes into the
# output subfolder. Only .png/.PNG/.jpg/.JPG/.jpeg/.JPEG files directly
# inside <folder> are processed (not subfolders), minus anything matching
# --skip-pattern.
#
# Example:
#   ./resize-recipe-photos.sh ~/Downloads/cookbook/menu/desserts-photos
#   ./resize-recipe-photos.sh ~/Downloads/some-folder -w 1200 -q 85

set -euo pipefail

output_name="resized"
width=1000
quality=78
suffix="-resized"
skip_pattern="00-*"
folder=""

print_usage() {
  sed -n '2,41p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output) output_name="$2"; shift 2 ;;
    -w|--width) width="$2"; shift 2 ;;
    -q|--quality) quality="$2"; shift 2 ;;
    -s|--suffix) suffix="$2"; shift 2 ;;
    -p|--skip-pattern) skip_pattern="$2"; shift 2 ;;
    -h|--help) print_usage; exit 0 ;;
    -*)
      echo "Unknown option: $1" >&2
      print_usage
      exit 1
      ;;
    *)
      if [ -n "$folder" ]; then
        echo "Unexpected extra argument: $1" >&2
        exit 1
      fi
      folder="$1"
      shift
      ;;
  esac
done

if [ -z "$folder" ]; then
  echo "Error: no folder given." >&2
  print_usage
  exit 1
fi
if [ ! -d "$folder" ]; then
  echo "Error: '$folder' is not a directory." >&2
  exit 1
fi
if ! command -v sips >/dev/null 2>&1; then
  echo "Error: sips not found (this script is macOS-only)." >&2
  exit 1
fi

folder="${folder%/}"
out_dir="$folder/$output_name"
mkdir -p "$out_dir"

shopt -s nullglob nocaseglob
images=("$folder"/*.png "$folder"/*.jpg "$folder"/*.jpeg)
shopt -u nocaseglob

if [ ${#images[@]} -eq 0 ]; then
  echo "No .png/.jpg/.jpeg files found directly in '$folder'."
  exit 0
fi

total_before=0
total_after=0
count=0
skipped=0
failed=0

for src in "${images[@]}"; do
  filename=$(basename "$src")

  if [ -n "$skip_pattern" ] && [[ "$filename" == $skip_pattern ]]; then
    skipped=$((skipped + 1))
    continue
  fi

  base="${filename%.*}"
  out="$out_dir/${base}${suffix}.jpg"

  if sips -s format jpeg -s formatOptions "$quality" --resampleWidth "$width" "$src" --out "$out" >/dev/null 2>&1; then
    before=$(stat -f%z "$src")
    after=$(stat -f%z "$out")
    total_before=$((total_before + before))
    total_after=$((total_after + after))
    count=$((count + 1))
  else
    echo "  failed: $filename" >&2
    failed=$((failed + 1))
  fi
done

echo ""
echo "Processed $count image(s) into: $out_dir"
if [ "$skipped" -gt 0 ]; then
  echo "Skipped (matched --skip-pattern '$skip_pattern'): $skipped"
fi
if [ "$failed" -gt 0 ]; then
  echo "Failed: $failed (see above)"
fi
if [ "$count" -gt 0 ]; then
  before_mb=$(( total_before / 1024 / 1024 ))
  after_mb=$(( total_after / 1024 / 1024 ))
  avg_before_kb=$(( total_before / count / 1024 ))
  avg_after_kb=$(( total_after / count / 1024 ))
  reduction=$(( 100 - (total_after * 100 / total_before) ))
  echo "Before: ${before_mb} MB total (${avg_before_kb} KB avg)"
  echo "After:  ${after_mb} MB total (${avg_after_kb} KB avg)"
  echo "Reduction: ${reduction}%"
fi
