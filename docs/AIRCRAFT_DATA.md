# Aircraft data

All aircraft are defined as plain data in `scripts/aircraft/aircraft_db.gd` (one dictionary each) and turned into
meshes, physics panels, mass properties and collision by `AircraftBuilder`. All designs, names and liveries are
original "in the style of" types; no manufacturer names, trademarks or real registrations are used.

## Roster (mass = listed airframe mass before battery/fuel; span = main wing)
| Name | id | Category | Mass | Span | Length | Power | Gear |
|---|---|---|---|---|---|---|---|
| Skylark 150 | skylark | Trainer | 1.12 kg | 1.52 m | 1.17 m | 1× electric | tricycle |
| Tundra Cub | tundra_cub | Bush / STOL | 1.05 kg | 1.30 m | 0.93 m | 1× electric | taildragger |
| Ridgeline STOL | ridgeline | Bush / STOL | 1.30 kg | 1.50 m | 1.10 m | 1× electric | taildragger |
| Vortex 540 | vortex540 | Aerobatic | 4.90 kg | 1.90 m | 1.80 m | 1× gas2 | taildragger |
| Aerostar 330 | aerostar | Aerobatic | 3.10 kg | 1.62 m | 1.45 m | 1× glow2 | taildragger |
| Skipper Bipe | skipper | Biplane | 2.75 kg | 1.20 m | 1.08 m | 1× glow4 | taildragger |
| Silver Belle 51 | belle51 | Warbird | 4.10 kg | 1.62 m | 1.42 m | 1× glow4 | taildragger (retract) |
| Valor 46 | valor | Sport Trainer | 2.45 kg | 1.55 m | 1.30 m | 1× glow2 | tricycle |
| Tiger 28 | tiger28 | Warbird | 2.70 kg | 1.40 m | 1.22 m | 1× electric | tricycle (retract) |
| Viper 90 EDF | viper90 | EDF Jet | 2.10 kg | 1.15 m | 1.30 m | 1× edf | tricycle (retract) |
| Striker 16 | striker16 | Turbine Jet | 10.50 kg | 1.50 m | 2.40 m | 1× turbine | tricycle (retract) |
| Specter 22 | specter22 | EDF Jet | 2.30 kg | 0.88 m | 1.20 m | 2× edf | tricycle (retract) |
| Brute 10 | brute10 | EDF Jet | 3.00 kg | 1.45 m | 1.30 m | 2× edf | tricycle |
| Cargomaster 130 | cargo130 | Multi-engine | 4.00 kg | 2.05 m | 1.60 m | 4× electric | tricycle |
| Skyliner 74 | skyliner | Airliner | 4.90 kg | 1.95 m | 1.90 m | 4× edf | tricycle (retract) |
| Mach Arrow SST | macharrow | Airliner | 3.60 kg | 0.92 m | 2.05 m | 4× edf | tricycle (retract) |

## Definition fields
- `fuselage`: loft stations `[z, half-width, half-height, y-offset, superellipse exponent]` (z aft from the nose, metres).
- `wings` / `htail` / `vtails`: position, span, root/tip chord, sweep, dihedral, incidence, washout, thickness, camber, stall angle, aileron / flap / elevator / rudder chord fractions and span ranges, elevons, struts, tip style.
- `engines`: `electric` (Kv, Rm, i0, mass), `glow2`/`glow4`/`gas2` (peak torque, rpm curve, idle, starter), `edf` (fan Ø, static thrust, exit velocity), `turbine` (thrust, spool times, idle, burn rate).
- `gear`: `tricycle`/`taildragger`, wheels with position, radius, leg length, style (spring, wire, oleo, bogie), steer, brake, pants, retract. The builder auto-places main gear relative to the computed CG and guarantees hull and prop ground clearance.
- `cg` (fraction of MAC), `rates` (max surface throws °), `servo_speed` (°/s), `strength`, `material` (foam, film, fabric, composite, painted/metal), `body_cd`, `batteries`, `props`, `tank`, `fuel_type`, `livery`, `labels`.

## Workshop (per-aircraft, saved)
Battery pack, propeller, CG shift, throws, fuel load and engine tuning are stored per aircraft in the save file and applied at spawn (`Settings.aircraft_cfg(id)`).

## Adding an aircraft
Append a new `_base({...})` entry to `_build()`. Run `tests/flight_test.tscn` to check rest on gear, take-off, static margin, stall, loop, spin and hands-off stability.

## Flight-envelope notes (headless test, `tests/flight_test.gd`)
All 16 aircraft rest on their gear and take off. Stalls, spins and snap rolls are emergent; e.g. holding full up elevator over the top of a loop at low energy in the Viper 90 produces an accelerated-stall snap (70 % elevator loops cleanly) — this is intended, not clamped.