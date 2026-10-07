# RCBeam native core

Small clean-room C++ node/beam structural solver for RC Park.

This first slice is intentionally independent of Godot so it can be unit-tested and profiled without engine overhead. The Godot GDExtension adapter comes next.

## Build smoke test

```bash
cmake -S native/rcbeam -B build/rcbeam -DRCBEAM_BUILD_TESTS=ON
cmake --build build/rcbeam --config Release
ctest --test-dir build/rcbeam --output-on-failure
```

The core has no third-party runtime dependency.
