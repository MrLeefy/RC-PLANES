"""Explicitly lock or verify the 16 premade scene/physics pairs."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--write", action="store_true", help="Accept an intentional offline art/blueprint revision")
args = parser.parse_args()
folder = Path(__file__).resolve().parents[1] / "assets/aircraft_baked"
manifest_path = folder / "baseline.json"
aircraft = {}
for scene in sorted(folder.glob("*.scn")):
    blueprint = scene.with_suffix(".res")
    if not blueprint.exists():
        raise SystemExit(f"FAIL: missing blueprint for {scene.stem}")
    aircraft[scene.stem] = {
        "scene_sha256": hashlib.sha256(scene.read_bytes()).hexdigest(),
        "physics_sha256": hashlib.sha256(blueprint.read_bytes()).hexdigest(),
    }
if len(aircraft) != 16:
    raise SystemExit(f"FAIL: expected 16 aircraft, found {len(aircraft)}")
manifest = {"format_version": 1, "aircraft": aircraft}
if args.write:
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("Locked 16 premade aircraft scene/blueprint pairs")
elif not manifest_path.exists() or json.loads(manifest_path.read_text(encoding="utf-8")) != manifest:
    raise SystemExit("FAIL: premade aircraft changed; review the offline revision before explicitly updating baseline.json")
else:
    print("PASS: all 16 premade aircraft match the locked baseline")
