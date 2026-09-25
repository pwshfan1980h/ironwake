# Iron Wake: story bible

## The battalion

Iron Wake was raised a hundred years ago to escort ore convoys across the Harrow Basin. The convoys stopped, the contracts dried up, and the battalion kept walking anyway. It is still called a battalion. Four machines answer the roll.

Motto, from the key art: **Steel people. Harder ground. Further tomorrow.**

## The enemy

**The Sable combine** is a corporate salvage-and-security outfit pushing hover-drone packs into the Basin's dry washes. Sable drones fire **sabots**: slow, glowing, armor-piercing rounds. They are deadly if you stand still and dodgeable if you watch for the charge glow.

## The lance

| Callsign | Name | Role | Voice (placeholder TTS) | Notes |
| --- | --- | --- | --- | --- |
| GIDEON | Gideon | Striker pilot (player) | none | The first recruit the Wake has taken in thirty years. Knife Cell Striker, unit 27. Keep Gideon's gender unstated so any player fits. |
| ANVIL | Col. Maren Hask, 95 | Commander | Grandma (UK) plus a metallic cyborg layer | Born in the Wake's field hospital five years after the battalion was raised. Spine, lungs, left arm and eyes are machine, salvaged from dead pilots' mechs. Dry and unhurried. Never raises her voice. |
| KESTREL | Lt. Ines Varro | Scout | Karen (AU) | Spots everything first and says so. Clipped, confident. |
| RATCHET | Sgt. Dov Okafor | Engineer | Rocko (US) | Keeps four machines walking on the parts of forty. Calls Gideon "kid". Talks to actuators. |
| LANTERN | none | Dropship | none | The Wake's last carrier, flown remotely by Anvil. |

The derelict hull near Nav Bravo is **Tomas**: nineteen years in the sand. Anvil's line about it is the tutorial's one quiet beat.

## Tutorial: Operation Dry Wash

Harrow Basin, 18:42 local, dusk.

1. **Drop.** Lantern brings Gideon in; Anvil calls the release ("Mark. Welcome to the Harrow Basin.").
2. **Nav Alpha.** Movement and aiming.
3. **First contact.** One Sable drone. Line up the reticle and chain-fire.
4. **Nav Bravo.** Pass Tomas's hull.
5. **Dodge drill.** Ratchet's drill drone fires training sabots. Dodge two with Shift + A/D, then kill it.
6. **Nav Charlie.** Four Sables in the wash. Anvil teaches the tac map: pick a lancemate, pick a drone.
7. **Nav Delta.** Extraction by Lantern. "A hundred years, and the Wake still walks."

All voice lines live in `tools/voice/lines.json`. Change the text there and rerun `make_voices.py`.
