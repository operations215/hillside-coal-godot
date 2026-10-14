## Roof, water and gas for every tunnel, and the upgrades that hold them back.
## Attached to the World; it reads and writes the segments directly.
class_name Hazards
extends Node

const BOLT_GAP := 6.0
const GAS_BOOM := 5.0            # percent methane where a spark can set it off

var world: World
var rain := 0.0
var weather_t := 20.0
var gas := {}                     # root segment id -> percent CH4

func _init(w: World) -> void:
	world = w

func tick(dt: float) -> void:
	# weather: dry spells and rain, a few shifts each
	weather_t -= dt
	if weather_t <= 0.0:
		weather_t = randf_range(25.0, 70.0)
		var was := rain
		rain = 0.0 if rain > 0.0 else randf_range(0.4, 1.0)
		if rain > 0.0 and was == 0.0: Game.toast.emit("Rain is starting. Keep an eye on the water in shallow tunnels.")
	for sg in world.segs:
		if sg.dead or sg.prog < 4.0: continue
		if not sg.is_shaft(): _roof(sg, dt)              # a timbered shaft does not fall in like a roof
		_water(sg, dt)
	_gas(dt)

# ---------- roof ----------
func _roof(sg: Segment, dt: float) -> void:
	var U := sg.prog - sg.sup
	if U < 8.0:
		sg.stress = maxf(0.0, sg.stress - dt * 0.05); return
	var m := world.terrain.mat_world(sg.pos(sg.prog - 4.0).x, sg.pos(sg.prog - 4.0).y - Segment.R - 4.0)
	var weak := 1.6 if (m == Mats.SOIL or m == Mats.SAND or m == Mats.CLAY or m == Mats.COAL) else (1.0 if m == Mats.SHALE else 0.5)
	var wet := 1.0 + sg.water * 1.5 + rain * 0.3
	sg.stress += dt * 0.00012 * U * weak * wet / (1.0 + 0.6 * float(Game.up.get("roof", 0)))
	if sg.rubble.size() > 0: sg.stress = minf(sg.stress, 0.95)
	if sg.stress >= 1.0:
		cave_in(sg, sg.sup + randf() * U, 10.0 + randf() * 14.0)

func cave_in(sg: Segment, s0: float, L: float) -> void:
	var a := clampf(s0, 2.0, sg.prog - 2.0); var b := minf(sg.prog, a + L)
	sg.rubble = [a, b]; sg.stress = 0.0; sg.sup = minf(sg.sup, a)
	world.shake = 1.0
	var trapped := 0
	for w in world.workers:
		if w.seg == sg.id and w.s > b: trapped += 1
	Game.toast.emit("Cave-in in mine No.%d! %d ft of roof came down%s." % [world.mine_no(sg), int(b - a), (" with %d trapped behind it" % trapped) if trapped > 0 else ""])
	for w in world.workers:
		if w.task == sg.id and w.s <= b: w.leave_and_idle()

func blocked(sg: Segment, s: float) -> bool:
	return sg.rubble.size() > 0 and s > sg.rubble[0] + 0.5

## Bolting: each roof bolter adds support behind the face; machines (upgrade) bolt faster.
func bolt(sg: Segment, dt: float, skill: float) -> void:
	sg.sup = minf(sg.prog, sg.sup + dt * 2.0 * skill * (1.0 + 0.5 * float(Game.up.get("roof", 0))))
	Game.pay(-dt * 0.4)

# ---------- water ----------
func _water(sg: Segment, dt: float) -> void:
	var depth := sg.pos(sg.prog).y - Terrain.ground_y(sg.pos(sg.prog).x)
	var inflow := 0.0
	if sg.parent < 0: inflow += rain * 0.006                    # rain runs in at the portal
	if depth > 60.0: inflow += 0.0006 + 0.0025 * clampf((depth - 60.0) / 300.0, 0.0, 1.0)   # groundwater seeps in below 60 ft
	if sg.is_shaft(): inflow *= 0.35                               # a shaft sump is bailed by the cage
	elif sg.u.y > 0.05: inflow *= 1.0 + sg.u.y * 3.0              # a tunnel dipping away from the portal holds its water
	else: inflow *= 0.25                                           # one rising toward daylight drains itself
	var pump: float = 0.0015 + 0.004 * Game.up.get("pump", 0)
	sg.water = clampf(sg.water + (inflow - pump) * dt, 0.0, 1.0)

func flooded(sg: Segment) -> bool:
	return sg.water > 0.75

# ---------- gas ----------
func _gas(dt: float) -> void:
	for sg in world.segs:
		if sg.dead or sg.parent >= 0: continue
		var r: int = sg.id
		var cut := 0
		var vol := 0.0
		for c in world.segs:
			if c.dead or c.root_of(world.segs) != r: continue
			cut += c.coal_cells; vol += c.prog
		var g: float = gas.get(r, 0.0)
		# methane bleeds from the cut coal and the fans pull it out; a bigger mine needs more fan
		var seep := 0.25 * cut / maxf(200.0, vol) * dt
		var vent: float = (0.03 + 0.11 * Game.up.get("vent", 0)) * dt * 200.0 / maxf(200.0, vol)
		g = maxf(0.0, g + seep - vent)
		if g >= GAS_BOOM and randf() < dt * (0.01 if world.has_role("safety") else 0.03):
			_explode(sg, g)
			g = 0.5
		gas[r] = g

func gas_of(sg: Segment) -> float:
	return gas.get(sg.root_of(world.segs), 0.0)

func gas_out(sg: Segment) -> bool:
	return gas_of(sg) >= 1.5    # nobody digs at the face over 1.5 percent

func _explode(root: Segment, g: float) -> void:
	# the blast runs through the longest tunnel in the mine and drops the roof there
	var worst: Segment = root
	for c in world.segs:
		if not c.dead and c.root_of(world.segs) == root.id and c.prog > worst.prog: worst = c
	Game.toast.emit("Methane explosion in mine No.%d at %.1f%%! The roof came down and every face in there is shut." % [world.mine_no(root), g])
	cave_in(worst, worst.prog * 0.5, 30.0)
	for w in world.workers:
		if w.seg >= 0 and world.segs[w.seg].root_of(world.segs) == root.id:
			w.energy = maxf(5.0, w.energy - 40.0)
