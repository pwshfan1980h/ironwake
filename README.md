# Iron Wake

A first-person mech sim about the last four pilots of a hundred-year-old battalion. Built in Godot 4 and shipped to the web.

**Phase 0** is the tutorial, *Operation Dry Wash*: dropship intro, the Knife Cell Striker flown from its glass cockpit (throttle, leg steering, torso twist), telegraphed sabot fire you out-walk, chain-fire weapons, and a tac map for directing your lance. Instruments are split between the cockpit's own screens and the pilot's ocular implant overlay.

## Play

```sh
# build the web version (needs Godot 4.7.2 with web export templates)
godot --headless --path game --export-release Web ../build/web/index.html
python3 tools/serve_web.py          # http://localhost:8060
```

Deploy to GitHub Pages: `tools/deploy_web.sh`.

Or open `game/` in the Godot editor and press Play.

Deep links for testing: `#mission` skips the title screen; `#play` also skips the film and the drop.
Desktop: `godot --path game -- --play`. Run `godot --headless --path game --fixed-fps 30 -- --autopilot` to let a bot play the whole tutorial as a smoke test. Add `--shot=<prefix>,<t1>,<t2>` (windowed runs only) to save screenshots at those times, in seconds, and then quit.

## Controls

| Input | Action |
| --- | --- |
| W / S, mouse wheel | Throttle up / down (holds where you leave it; stops at zero before reverse) |
| X | All stop |
| A / D | Turn the legs |
| Mouse | Twist and pitch the torso: aim (no lock-on) |
| C | Centre the torso over the legs |
| Space / left mouse | Chain fire: RAC burst, laser, SRMs |
| Tab | Tac map: click a lancemate, then a drone |
| Esc | Pause |

## Layout

```
game/            Godot project (scripts, shaders, assets)
tools/blender/   procedural mech + dropship generators (Blender CLI)
tools/voice/     radio voice line script + generator
tools/film/      intro film audio + Godot Movie Maker encoder
assets/          source renders and exported GLBs
docs/            plan, story bible, art direction
```

See [docs/PLAN.md](docs/PLAN.md) for phases and the asset pipeline.
