# Hillside Coal Co. (Godot)

A side-scrolling coal mining tycoon: run a company digging into an Appalachian hillside.
Godot 4.3, GDScript, no plugins.

This is the engine rewrite of the single-file web version. Open the folder in Godot 4.3 and press Play.

## Layout
- `scenes/main.tscn` – the world, camera and HUD
- `scripts/terrain.gd` – the hill as a grid of 4 ft cells (materials, seams, ore), rendered per 256 px chunk
- `scripts/segment.gd` – one straight tunnel
- `scripts/world.gd` – tunnels, digging, conveyor flow, trucks, wages, input and drawing
- `scripts/worker.gd` – a miner: walk, dig, rest
- `scripts/game.gd` – money, clock, market (autoload `Game`)
- `scripts/mats.gd` – material table (autoload `Mats`)

## Headless checks
```
godot --headless --path . -- --smoke          # digs a tunnel for three shifts and prints RESULT OK/FAIL
xvfb-run -a godot --path . -- --shot          # renders shot1.png / shot2.png into the user data folder
```
