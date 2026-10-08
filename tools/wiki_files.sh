#!/bin/bash
# List the image files used by a Wikipedia article (reference photos and three-view drawings for model QA).
#   tools/wiki_files.sh Piper_PA-18_Super_Cub [grep-pattern]
# Be gentle with Wikimedia: one request per call; wait several seconds between calls; never use the API.
UA="RCPlanesDevReference/1.0 (personal hobby project; reference images for local comparison)"
out=$(mktemp)
curl -sS -L -m 60 -A "$UA" -o "$out" "https://en.wikipedia.org/wiki/$1" || exit 1
grep -o '/wiki/File:[^" ]*' "$out" | sort -u | sed 's#/wiki/File:##' | grep -viE "icon|logo|symbol|flag|commons-|wikiquote|wikisource|question|ambox|padlock|lock-|folder|edit|portal|increase|decrease|steady|wikt|wikibooks|mbox|nuvola|stub|OOjs|Operators|map" | grep -iE "${2:-.}"
rm -f "$out"
