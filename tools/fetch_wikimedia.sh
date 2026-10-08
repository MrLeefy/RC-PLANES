#!/bin/bash
# Download one Wikimedia Commons file (reference photo or drawing) for LOCAL comparison only; never ship it.
#   tools/fetch_wikimedia.sh "Cessna_172_3-view_line_drawing.png" out.png [width=1600]
# Retries with backoff on HTTP 429. Wait >= 6 s between files.
UA="RCPlanesDevReference/1.0 (personal hobby project; reference images for local comparison)"
for try in 1 2 3 4 5 6; do
  code=$(curl -sS -L -m 90 -A "$UA" -o "$2" -w "%{http_code}" "https://commons.wikimedia.org/wiki/Special:FilePath/$1?width=${3:-1600}")
  if [ "$code" = "200" ] && file "$2" | grep -qiE "image|SVG"; then echo "ok $2"; exit 0; fi
  echo "http $code (try $try) $1" >&2
  sleep $((12 * try))
done
rm -f "$2"; exit 1
