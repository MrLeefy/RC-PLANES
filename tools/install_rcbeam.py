"""Install only a built host library; no missing libraries in the descriptor."""
import argparse
from pathlib import Path
import shutil

parser = argparse.ArgumentParser()
parser.add_argument("--platform", required=True, choices=["linux", "windows", "android"])
parser.add_argument("--arch", required=True, choices=["x86_64", "arm64"])
parser.add_argument("--target", default="template_debug", choices=["template_debug", "template_release"])
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
prefix, ext = ("", "dll") if args.platform == "windows" else ("lib", "so")
filename = f"{prefix}rcbeam.{args.platform}.{args.target}.{args.arch}.{ext}"
source = root / "native/rcbeam/godot/bin" / args.platform / filename
destination = root / "addons/rcbeam/bin" / args.platform / filename
destination.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(source, destination)
descriptor = root / "addons/rcbeam/rcbeam.gdextension"
entries = {}
if descriptor.exists():
    for line in descriptor.read_text().splitlines():
        if " = " in line and line.split(".")[0] in ("linux", "windows", "android"):
            key, value = line.split(" = ", 1)
            entries[key] = value
mode = "debug" if args.target == "template_debug" else "release"
entries[f"{args.platform}.{mode}.{args.arch}"] = f'"res://addons/rcbeam/bin/{args.platform}/{filename}"'
descriptor.write_text('[configuration]\nentry_symbol = "rcbeam_library_init"\ncompatibility_minimum = "4.7"\nreloadable = false\n\n[libraries]\n' + "\n".join(f"{k} = {v}" for k, v in sorted(entries.items())) + "\n")
print(f"Installed {destination}")
