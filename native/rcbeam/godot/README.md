# RCBeam Godot GDExtension bridge

This wrapper exposes the native RCBeam solver to Godot as `RCBeamSolver`.

It intentionally keeps the hot structural integration loop in C++. GDScript is used for orchestration, graph authoring, contact-to-node mapping and visual/replay glue.

## Build prerequisites

- Godot project target: 4.7
- godot-cpp commit `ed672dc12ed37c8b361fe077285a094882ad0543` (v10 API targeting 4.7)
- SCons + a C++17 compiler
- Android NDK for Android builds

Clone `godotengine/godot-cpp` into this directory as `godot-cpp/` (or pass `godot_cpp_dir=/path`), then check out the commit above. The API version is explicitly selected in SConstruct. The reduced bindings profile includes OS because godot-cpp's core print implementation needs it.

Linux smoke build:

```bash
cd native/rcbeam/godot
python -m SCons platform=linux target=template_debug -j2
```

Omit `arch=` for a native Linux build: godot-cpp detects x86_64 or ARM64. Forcing `arch=x86_64` with an ARM64 compiler causes the rejected `-m64` flag. Do not remove architecture flags to disguise a mismatched toolchain. SConstruct now probes the selected compiler with its target flags before compiling.

Windows (LLVM-MinGW on PATH):

```powershell
python -m SCons platform=windows target=template_debug use_mingw=yes use_llvm=yes -j8
```

Android ARM64 (SDK-managed NDK; use your installed version):

```bash
python -m SCons platform=android target=template_release arch=arm64 ANDROID_HOME=/path/to/sdk ndk_version=25.2.9519653 -j8
```

From the repository root, install a built library and generate a descriptor containing only installed platform entries:

```bash
python tools/install_rcbeam.py --platform linux --arch arm64
godot --headless --path . --editor --import
godot --headless --fixed-fps 120 --path . res://tests/rcbeam_test.tscn
```

Use `--target template_release` for the Android release library. Generated libraries/descriptors are ignored; projects without them keep the legacy path. A distributable Android package still needs debug/release libraries for its export preset and device validation.

Run the normal game with `godot --path . -- --rcbeam-proof`, then fly a model to opt into the structural proof. All 16 baked models accept the generic cages; Skylark has the destructive regression coverage. Without the flag or `cfg.rcbeam=true`, flight behavior remains on the legacy path.

`step_fast`, indexed node access, indexed break events and `clear_break_events` avoid allocating result arrays/dictionaries in the integration bridge. The native core's step/event path has a zero-allocation regression. Diagnostic array-returning APIs intentionally allocate. GDScript cage/visual/aero orchestration still needs Android allocation and frame-time profiling before production enablement.

CI builds and runs Godot 4.7.2 extension tests on both x86_64 and ARM64 Linux. See [the Godot version compatibility guidance](https://github.com/godotengine/godot-cpp#compatibility) and `docs/RCBEAM_VALIDATION.md` for measured results and limitations.
