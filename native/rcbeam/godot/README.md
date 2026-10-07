# RCBeam Godot GDExtension bridge

This wrapper exposes the native RCBeam solver to Godot as `RCBeamSolver`.

It intentionally keeps the hot structural integration loop in C++. GDScript is used for orchestration, graph authoring, contact-to-node mapping and visual/replay glue.

## Build prerequisites

- Godot project target: 4.7
- current godot-cpp v10+ (supports `api_version=4.7`)
- SCons + a C++17 compiler
- Android NDK for Android builds

Clone `godotengine/godot-cpp` into this directory as `godot-cpp/` (or pass `godot_cpp_dir=/path`).

Linux smoke build:

```bash
cd native/rcbeam/godot
scons target=template_debug arch=x86_64
```

Android ARM64:

```bash
scons platform=android target=template_release arch=arm64 ANDROID_NDK_ROOT=/path/to/ndk
```

The descriptor is stored as `rcbeam.gdextension.example` until platform binaries are built and copied to `addons/rcbeam/bin/<platform>/`. Do not enable a live `.gdextension` descriptor with missing platform libraries.
