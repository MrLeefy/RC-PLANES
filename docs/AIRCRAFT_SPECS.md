# Aircraft specifications (derived, fictional)

All 16 aircraft are fictional. Nothing here is an official manufacturer figure. The numbers are **derived from the
simulation's own geometry and models** by `scripts/aircraft/aircraft_specs.gd` (`AircraftSpecs.compute`) and are regenerated with:

    godot --headless --path . res://tests/spec_dump.tscn -- --md docs/AIRCRAFT_SPECS.md   # table only
    godot --headless --path . res://tests/spec_dump.tscn -- <aircraft id>                 # full sheet for one aircraft

## Assumptions

- Span, area, MAC, aspect ratio and static margin come from the lofted wing/tail panels (planform integration, neutral point
  from wing + tail lift slopes with a downwash factor).
- Ready mass = airframe mass in the database + battery or fuel + any payload + ballast. Radio gear (about 9 % of mass for
  fuel aircraft) is placed to reach the target CG, so ballast is a last resort and capped at 3 % of ready mass (the
  realism test fails otherwise; worst case today is 2.5 %).
- Inertia is the sum of point/box masses (wings, tail, fuselage, battery/fuel, engines, gear), so moving the battery, burning
  fuel or losing a wing changes CG and inertia at run time.
- Stall, cruise, top speed, climb and take-off roll are solved on the same force model the flight code uses (per-panel lift and
  drag with Reynolds scaling, flap CLmax, prop/EDF/turbine thrust curves, motor Kv/Rm/I0 for electrics).
  On the baseline Skylark the derived top speed (28.7 m/s) agrees with the measured value (28.5 m/s) in flight.
- Servo throws/speeds come from each aircraft's rate table; speeds in m/s, masses in kg.
- Power plants were retuned where the audit found an unbelievable thrust-to-weight or wing loading for the class.

## Derived table (default battery, prop, CG, high throws)

| Aircraft | Cat. | Span m | Length m | Area dm2 | MAC mm | AR | Ready kg | WL g/dm2 | CG %MAC | SM % | Ballast g |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Skylark 150 | Trainer | 1.52 | 1.17 | 33 | 220 | 7.0 | 1.46 | 44 | 27 | 38 | 0 |
| Tundra Cub | Bush / STOL | 1.30 | 0.83 | 26 | 200 | 6.5 | 1.24 | 48 | 34 | 21 | 0 |
| Ridgeline STOL | Bush / STOL | 1.50 | 1.10 | 33 | 220 | 6.8 | 1.66 | 50 | 30 | 35 | 33 |
| Vortex 540 | Aerobatic | 1.90 | 1.67 | 76 | 412 | 4.8 | 5.31 | 70 | 30 | 16 | 0 |
| Aerostar 330 | Aerobatic | 1.62 | 1.45 | 53 | 338 | 4.9 | 3.42 | 64 | 29 | 17 | 0 |
| Skipper Bipe | Biplane | 1.20 | 1.08 | 52 | 226 | 2.8 | 3.03 | 58 | 28 | 5 | 0 |
| Silver Belle 51 | Warbird | 1.62 | 1.42 | 48 | 307 | 5.5 | 4.46 | 93 | 27 | 17 | 0 |
| Valor 46 | Sport Trainer | 1.55 | 1.30 | 40 | 262 | 6.0 | 2.72 | 68 | 30 | 22 | 32 |
| Tiger 28 | Warbird | 1.40 | 1.11 | 34 | 253 | 5.7 | 3.32 | 97 | 29 | 21 | 0 |
| Viper 90 EDF | EDF Jet | 1.15 | 1.30 | 31 | 291 | 4.3 | 2.82 | 91 | 20 | 12 | 0 |
| Striker 16 | Turbine Jet | 1.70 | 2.40 | 82 | 553 | 3.5 | 12.74 | 155 | 25 | 12 | 0 |
| Specter 22 | EDF Jet | 0.88 | 1.20 | 32 | 423 | 2.4 | 3.02 | 95 | 24 | 10 | 0 |
| Brute 10 | EDF Jet | 1.45 | 1.30 | 35 | 245 | 6.0 | 3.74 | 107 | 26 | 26 | 15 |
| Cargomaster 130 | Multi-engine | 2.20 | 1.60 | 46 | 214 | 10.5 | 4.86 | 105 | 25 | 61 | 0 |
| Skyliner 74 | Airliner | 1.95 | 2.15 | 55 | 319 | 7.0 | 5.64 | 103 | 24 | 36 | 0 |
| Mach Arrow SST | Airliner | 0.92 | 2.05 | 51 | 702 | 1.7 | 4.46 | 87 | 17 | 10 | 0 |

| Aircraft | Power | Static thrust N | T/W | W/kg | Vs clean | Vs flaps | Vapp | Vcruise | Vtop | ROC m/s | Takeoff roll m | Endurance cruise min |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Skylark 150 | 326 W in x1 | 14.2 | 0.99 | 223 | 8.2 | 7.2 | 9.4 | 10.4 | 22.7 | 6.2 | 7 | 23.8 |
| Tundra Cub | 316 W in x1 | 14.5 | 1.19 | 255 | 8.5 | 7.3 | 9.5 | 8.6 | 18.2 | 5.8 | 6 | 13.0 |
| Ridgeline STOL | 528 W in x1 | 23.9 | 1.46 | 318 | 6.8 | 5.9 | 7.7 | 9.5 | 20.0 | 7.9 | 3 | 15.1 |
| Vortex 540 | 3.33 hp shaft x1 | 100.4 | 1.93 | 468 | 11.4 | 11.4 | 14.8 | 23.9 | 35.0 | 17.9 | 6 | 40.9 |
| Aerostar 330 | 1.44 hp shaft x1 | 45.9 | 1.37 | 313 | 11.0 | 11.0 | 14.4 | 23.8 | 36.3 | 13.0 | 8 | 25.5 |
| Skipper Bipe | 1.37 hp shaft x1 | 43.5 | 1.46 | 338 | 11.3 | 11.3 | 14.7 | 21.8 | 32.1 | 12.9 | 8 | 22.2 |
| Silver Belle 51 | 1.97 hp shaft x1 | 64.5 | 1.47 | 329 | 13.0 | 10.9 | 14.2 | 25.4 | 38.3 | 15.3 | 11 | 21.4 |
| Valor 46 | 1.31 hp shaft x1 | 34.5 | 1.29 | 358 | 10.5 | 9.4 | 12.2 | 26.5 | 31.7 | 10.9 | 8 | 17.2 |
| Tiger 28 | 1065 W in x1 | 42.5 | 1.31 | 321 | 12.7 | 10.9 | 14.2 | 12.9 | 28.8 | 9.9 | 13 | 15.8 |
| Viper 90 EDF | 2170 W in x1 | 31.4 | 1.14 | 769 | 12.6 | 10.9 | 14.1 | 29.7 | 41.0 | 12.4 | 13 | 6.4 |
| Striker 16 | turbine 120 N x1 | 120.0 | 0.96 | 377 | 13.5 | 13.5 | 17.6 | 39.2 | 74.1 | 14.4 | 15 | 18.4 |
| Specter 22 | 2601 W in x2 | 31.6 | 1.07 | 861 | 10.8 | 10.6 | 13.8 | 28.1 | 39.1 | 9.6 | 10 | 5.1 |
| Brute 10 | 2526 W in x2 | 31.8 | 0.87 | 676 | 12.7 | 10.8 | 14.1 | 22.9 | 31.9 | 7.4 | 19 | 5.3 |
| Cargomaster 130 | 1248 W in x4 | 53.4 | 1.12 | 257 | 11.7 | 9.9 | 12.9 | 11.9 | 26.5 | 7.7 | 13 | 15.8 |
| Skyliner 74 | 2138 W in x4 | 46.9 | 0.85 | 379 | 12.2 | 10.1 | 13.1 | 22.7 | 31.6 | 7.1 | 18 | 5.6 |
| Mach Arrow SST | 2675 W in x4 | 44.5 | 1.02 | 600 | 11.0 | 11.0 | 14.3 | 25.4 | 36.5 | 7.8 | 11 | 5.4 |

## Scale fidelity

The realism suite checks length/span of the replicas that copy a real type against published dimensions (within 8 %): Cessna 150, Super Cub, P-51D, F-22, A-10, F-16, Concorde, Boeing 747-400 and C-130H. The in-the-style-of aerobats, biplane, warbird and bush/sport trainers are checked against class references (Extra-type 0.88, Pitts-type 0.90, WWII radial fighter 0.79, light bush plane 0.70, light low-wing trainer 0.80); Vortex 540 and Tiger 28 bodies were shortened to match. Cargomaster uses the C-130 proportions (span 1.26 x length, engines at about 27 % and 56 % of the semispan, flight deck ahead of the propellers, gear sponsons against the fuselage); Skyliner is 1.10 x span long like the 747-400.

## Verification

`tests/realism_tests.gd` checks every aircraft against per-category envelopes (wing loading, T/W, stall speed, CG), mass
book-keeping, inertia triangle inequalities, ordering of stall/cruise/top speed, and then flies each one: rest on gear,
control polarity, retracts/flaps, take-off, stall, spin and recovery, hands-off cruise, landing and roll-out, damage and repair.
Run `godot --headless --path . -- --upgrade-test`.
