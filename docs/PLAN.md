# Iron Wake: plan

First-person mech sim. You fly the mech from its cockpit: set the throttle, steer the legs, and twist the torso to aim with a reticle (no lock-on). The engine is Godot 4 (GL Compatibility renderer), shipped to the web first.

## Decisions so far

| Area | Decision |
| --- | --- |
| Camera | First person from the cockpit. The canopy is a thin frame with glass everywhere else, and it rides the torso (twist, pitch, footfall bob). |
| Instruments | Diegetic: three cockpit MFDs (SYS: armor, heat, weapons; TAC: radar; DRV: throttle, speed, twist, comms), a warning lamp row, and a throttle lever and stick that move with the controls. The pilot's ocular implant overlay adds the reticle, heat and armor arcs, a throttle tape, weapon pips, a compass, markers and comms. |
| Aiming | Reticle only. No lock-on or target cycling for the player. |
| Weapons | Space (or left mouse) chain-fires. The next ready weapon fires in order: RAC burst, medium laser, SRM pair. |
| Movement | Mech sim: a throttle that holds its setting (54 km/h full ahead, 22 km/h full reverse) with slow acceleration. A/D turn the legs; the torso twists ±110° independently. No strafe and no dodge. |
| Threats | Enemy rounds (sabots) are slow, glowing and telegraphed, so players can see them coming, walk out of the line of fire and return fire. |
| Lance | Three AI lancemates. The player assigns their targets on the top-down tac map (Tab). Time slows while it's open. |
| Mission start | Pre-rendered dropship film, then an in-engine drop: the dropship arrives, releases the mech, it lands, and control starts. |
| Comms | Voiced radio lines with subtitles. Placeholder TTS for now; keep the line ids when recording real VO. |
| Look | Knife Cell direction (see ART_DIRECTION.md), in a dusk desert. |
| Engine | Godot 4.7, GDScript. Web export uses the no-threads build so it runs without special server headers. |

## Phase 0: tutorial vertical slice (this build)

Goal: one polished tutorial that proves the core loop is fun: move, see the incoming round, walk out of its path, return fire, direct the lance.

- [x] Start screen with the Iron Wake story and roster
- [x] Dropship intro film, then the in-engine drop and landing
- [x] Knife Cell Striker: throttle and leg-steering locomotion, torso twist, procedural walk
- [x] First-person glass cockpit with MFDs, warning lamps, throttle and stick; ocular implant HUD
- [x] Chain-fire weapons with heat and overheat
- [x] Sable drones with telegraphed sabot fire
- [x] Desert terrain: dunes, ridges, mesas, a wash along the route, boulders, pebbles, scrub, hoodoos, a derelict Wake mech
- [x] Tac map with lancemate target assignment
- [x] Tutorial: Operation Dry Wash (4 waypoints, drone kill, evasion drill, tac-map drill, drone wave, extraction)
- [x] Radio voice lines and subtitles; system voice callouts (incoming, heat, armor)
- [x] Debrief screen, pause menu, restart
- [x] Web export, plus a local server script
- [x] Headless autopilot that plays the whole tutorial (`-- --autopilot`) as a smoke test

### Phase 0 polish backlog (next, still in scope)
- Playtest the tuning numbers: top speed, acceleration, leg turn and torso twist rates, sabot speed, drone fire rate
- Hit reactions on the mech (torso flinch, sparks from the hit side)
- Aim assist is off by design. Check reticle readability against bright sand.
- Gamepad support (left stick: throttle and legs; right stick: torso)
- Settings: mouse sensitivity, invert Y, volume sliders
- Loading screen art

## Phase 1: combat depth
- First enemy mech (Sable "Lancer") with a sabot cannon
- Damage zones (arms, legs, torso). Losing an arm loses its weapon.
- Hand-modeled Knife Cell hero mesh over the Blender blockout. Keep the pivot and material slot names.
- Proper VO recording session to replace TTS
- Audio pass: positional mix, music stingers

## Phase 2: first real mission
- Mission 1 in the Harrow Basin, built on the tutorial systems
- More lance orders: hold, follow, focus fire, spread
- Save and checkpoint system

## Phase 3: the lineup
- Scout, Assault, Artillery, Sniper and Support chassis from the key art
- Mech bay: pick a chassis and loadout before a drop

## Pipeline

| Asset | Source | Command |
| --- | --- | --- |
| Mechs | `tools/blender/build_striker.py` | `blender -b -P tools/blender/build_striker.py -- C game/assets/mechs` |
| Dropship + film frames | `tools/blender/build_dropship.py` | `blender -b -P tools/blender/build_dropship.py -- game/assets/mechs --film /tmp/frames` |
| Film encode (.ogv) | `tools/film/encoder` (Godot Movie Maker) | `godot --path tools/film/encoder --write-movie game/assets/video/dropship_intro.ogv --fixed-fps 24 -- /tmp/frames tools/film/film_audio.wav` |
| Voice lines | `tools/voice/lines.json` | `python3 tools/voice/make_voices.py` |
| Web build | `game/export_presets.cfg` | `godot --headless --path game --export-release Web ../build/web/index.html` |
| Run locally | `tools/serve_web.py` | `python3 tools/serve_web.py` then open http://localhost:8060 |
