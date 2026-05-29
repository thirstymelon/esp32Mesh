#!/usr/bin/env bash
# ── ESP32 Mesh Chat — build.sh ─────────────────────────────────────────────
# Compiles SCSS → CSS, gzips HTML and CSS for LittleFS upload.
# Prerequisites: sass (npm install -g sass)  and  gzip (built-in on macOS/Linux)
#
# Usage:
#   chmod +x build.sh
#   ./build.sh
#
# Then upload the filesystem:
#   pio run -t uploadfs
# ──────────────────────────────────────────────────────────────────────────

set -e

DATA="$(dirname "$0")/data"
SCSS="$DATA/scss"
CSS="$DATA/style"
TMPL="$DATA/template"
GZ="$DATA/html_gz"

echo "── Mesh Build ─────────────────────────────────────────"

# 1. Compile SCSS → CSS (skip if sass not installed)
# if command -v sass &>/dev/null; then
#   echo "[1/3] Compiling SCSS..."
#   sass "$SCSS/index.scss:$CSS/index.css"   --style=compressed --no-source-map
#   sass "$SCSS/nodes.scss:$CSS/nodes.css"   --style=compressed --no-source-map  2>/dev/null || \
#     cp "$CSS/nodes.css" "$CSS/nodes.css"   # nodes.scss is docs-only, CSS already good
#   sass "$SCSS/update.scss:$CSS/update.css" --style=compressed --no-source-map 2>/dev/null || \
#     cp "$CSS/update.css" "$CSS/update.css"
#   echo "    SCSS compiled."
# else
#   echo "[1/3] sass not found — skipping SCSS compilation (CSS already up to date)"
# fi

# 2. Gzip HTML templates → html_gz/
mkdir -p "$GZ"
echo "[2/3] Gzipping HTML..."
for page in index nodes update; do
  SRC="$TMPL/$page.html"
  DST="$GZ/$page.html.gz"
  if [ -f "$SRC" ]; then
    gzip -c -9 "$SRC" > "$DST"
    echo "    $page.html → html_gz/$page.html.gz  ($(du -h "$DST" | cut -f1))"
  else
    echo "    WARNING: $SRC not found, skipping"
  fi
done

# 3. Gzip CSS → style/*.css.gz  (ESPAsyncWebServer can serve pre-gzipped statics)
echo "[3/3] Gzipping CSS..."
for page in index nodes update; do
  SRC="$CSS/$page.css"
  DST="$CSS/$page.css.gz"
  if [ -f "$SRC" ]; then
    gzip -c -9 "$SRC" > "$DST"
    echo "    $page.css  → style/$page.css.gz  ($(du -h "$DST" | cut -f1))"
  else
    echo "    WARNING: $SRC not found, skipping"
  fi
done

echo ""
echo "── Build complete ─────────────────────────────────────"
echo "  Next step: pio run -t uploadfs"
echo ""

# Print LittleFS data/ size summary
echo "── data/ size summary ─────────────────────────────────"
du -sh "$DATA/html_gz" "$DATA/style" 2>/dev/null || true
echo ""
