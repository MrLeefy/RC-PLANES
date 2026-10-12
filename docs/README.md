# RC Park documentation

Start with the [project README](../README.md) for local setup, Android builds, controls and test commands. This page indexes the detailed project notes instead of duplicating those instructions.

## Understand the project

- [Architecture](ARCHITECTURE.md): application and simulation structure.
- [Aircraft data](AIRCRAFT_DATA.md) and [aircraft specifications](AIRCRAFT_SPECS.md): model reference material.
- [Assets and licenses](ASSETS_LICENSES.md): asset provenance and licensing notes.

## Changes and verification

- [Visual upgrade](VISUAL_UPGRADE.md): visual implementation notes.
- [Upgrade README](../UPGRADE_README.md): upgrade handoff.
- [Upgrade validation status](../UPGRADE_VALIDATION_STATUS.json): recorded validation status.
- [QA report](QA_REPORT.md): recorded checks and observations.
- [Unverified items](UNVERIFIED.md): outstanding validation limits.

Reports describe the revision and environment in which their checks were recorded. They are not fresh test results for every subsequent commit.

## Distribution

- [Play Store notes](PLAY_STORE.md): Android distribution preparation.
- [Export presets](../export_presets.cfg): repository export configuration.

Signing credentials and production distribution are separate from building or reviewing this source tree.

## AI work and handoffs

This repository owns the Godot simulation and Android export configuration. Start with [architecture](ARCHITECTURE.md): `scripts/game/main.gd` owns boot, `scripts/game/flight.gd` owns flight/replay transitions, and `scripts/autoload/settings.gd` owns save migration. Assign physics, controls, procedural rendering and save-format paths explicitly before parallel changes; coordinate shared physics-tick and save-version assumptions. No external companion-repository contract is established by these project docs.

Acceptance from the [root guide](../README.md): `godot --headless --fixed-fps 120 --path . -- --test` and `godot --headless --fixed-fps 120 --path . res://tests/flight_test.tscn`. Return the tested Godot version, commit, results and sanitized report references; keep Android/device/rendering checks separate. Historical QA and upgrade reports do not certify the new revision. Never share signing keys or personal saves.

For each handoff, record:
- Task ID, sender, intended recipient and next owner.
- Repository, branch, base SHA and current head SHA; owned paths and explicit out-of-scope work.
- Changed contract or dependency, with source links and both revisions for any cross-repository change; unresolved assumptions are blockers.
- Acceptance commands/checks and actual outcomes (`passed`, `failed`, `not run`), including environment and limitations.
- PR/commit and permitted artifact references, remaining blockers, and acknowledgment state (`pending`, `accepted`, `blocked`, `completed`).

The recipient should acknowledge scope and ownership before overlapping edits and report completion against the acceptance checks. A saved document is not a sent message or acknowledgment. Use only an authorized communication channel and preserve repository visibility; share the minimum source/contract context, never secrets or personal state.
