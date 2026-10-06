# Outline fit (dev tool, not shipped)
Compares each replica's planform with the top view of the real type's three-view drawing (silhouette IoU after
normalising length and span). Reference images are NOT in the repo: fetch them from Wikimedia Commons into
`/tmp/claude-0/ref/` (see `REF` in fit.py for file names), dump the model planforms with
`godot --headless --path . res://tests/planform_dump.tscn -- /tmp/claude-0/fit/planforms.json`, then run
`python3 -I fit.py` (IoU table + overlay PNGs) or `opt.py` (bounded random search for wing/tailplane z, chord, sweep).
