# Iron Wake

A third-person mech shooter about the last four pilots of a hundred-year-old battalion. Built in Godot 4 and shipped to the web.

**Phase 0** is the tutorial, *Operation Dry Wash*: dropship intro, agile Knife Cell Striker, sideways dodges against telegraphed sabot fire, chain-fire weapons, and a tac map for directing your lance.

## Play

```sh
# build the web version (needs Godot 4.7.2 with web export templates)
godot --headless --path game --export-release Web ../build/web/index.html
python3 tools/serve_web.py          # http://localhost:8060
```

Deploy to GitHub Pages: `tools/deploy_web.sh`.

Or open `game/` in the Godot editor and press Play.

Deep links for testing: `#mission` skips the title screen; `#play` also skips the film and the drop.
Desktop: `godot --path game -- --play`. Run `godot --headless --path game --fixed-fps 30 -- --autopilot` to let a bot play the whole tutorial as a smoke test.

## Controls

| Input | Action |
| --- | --- |
| W A S D | Walk and strafe |
| Mouse | Aim (no lock-on) |
| Space / left mouse | Chain fire: RAC burst, laser, SRMs |
| Shift + A / D | Sideways dodge (2 charges) |
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
