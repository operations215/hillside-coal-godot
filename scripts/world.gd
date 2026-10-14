## The mine: tunnels, the conveyor flow, the crew, the stockpile and the trucks. Everything ticks from here.
class_name World
extends Node2D

const PORTAL_FT := 20.0           # a tunnel must reach this far before it counts as a mine
const COST_PER_FT := 0.2          # conveyor structure per foot driven
const PILE_X := 440.0
const HEAD_X := 1236.0            # head of the overland conveyor above the stockpile
const BELT_SPEED := 30.0
const TRUCK_LOAD := 20.0

var terrain: Terrain
var segs: Array = []              # Segment, by id
var workers: Array = []           # Worker, by id
var items: Array = []             # [seg, s, mat, tons] riding the belts, seg -1 = overland with s = feet to the head
var trucks: Array = []            # dictionaries {x, state, t, load}
var drag_start := {}              # {seg, s, pos} while planning
var drag_plan := {}               # the planned segment while dragging
var hover := Vector2.ZERO
var sold_tons := 0.0
var toasts: Array = []
var hazards: Hazards
var fx := FX.new()
var rigs: Array = []
var cars: Array = []
var plan_belt := true
var view_filter := 0              # 0 normal, 1 gas, 2 fire, 3 roof, 4 water, 5 air
const FILTERS := ["Normal view", "Methane", "Fire risk", "Roof", "Water", "Air supply"]
var night: Night             # new tunnels get a conveyor, or go bare for shuttle cars
var shake := 0.0
var plan_wait := 0.0

@onready var cam: Camera2D = $Camera2D
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	terrain = Terrain.new()
	add_child(terrain)
	move_child(terrain, 0)
	hazards = Hazards.new(self)
	var bd := Backdrop.new(); add_child(bd); move_child(bd, 0)
	night = Night.new(); night.world = self; add_child(night)
	for i in 2: hire(Worker.Role.MINER)
	Game.toast.connect(func(t): hud.show_toast(t))
	if OS.get_cmdline_user_args().has("--smoke"):
		call_deferred("_smoke")
	if OS.get_cmdline_user_args().has("--shot"):
		call_deferred("_shot")
	hud.show_toast("Drag from the hillside into the ground to start a tunnel. Coal rides the conveyor out to the stockpile and trucks haul it to market.")

# ---------- crew ----------
func hire(role: int) -> Worker:
	var w := Worker.new()
	w.id = workers.size(); w.world = self; w.skill = randf_range(0.8, 1.3); w.role = role
	workers.append(w); add_child(w)
	return w

func has_role(name: String) -> bool:
	var r := Worker.ROLE_NAME.find(name) if name != "safety" else Worker.Role.SAFETY
	return workers.any(func(w): return w.role == r)

func buy_car() -> void:
	if not Game.spend(Car.COST): return
	var c := Car.new(); c.id = cars.size(); c.world = self; c.position = Vector2(1120.0 + cars.size() * 40.0, 0.0)
	cars.append(c); add_child(c)
	Game.toast.emit("A shuttle car is delivered. It hauls from any tunnel driven without a conveyor back to the belt.")

func buy_rig() -> void:
	if not Game.spend(Rig.COST): return
	var r := Rig.new(); r.id = rigs.size(); r.position = Vector2(1180.0 + rigs.size() * 50.0, 0.0)
	rigs.append(r); add_child(r)
	Game.toast.emit("A continuous miner is delivered to the yard. The next miner heading to a face drives it in.")

## A round goes off: ten feet of rock comes down at once, with smoke, a thump and a shake of the ground.
func shoot(sg: Segment) -> void:
	var fp: Vector2 = sg.pos(sg.prog)
	advance(sg, 10.0)
	shake = 0.6
	for k in 40: fx.puff(fp + Vector2(randf_range(-6, 6), randf_range(-8, 8)), -sg.u * randf_range(10, 60) + Vector2(randf_range(-10, 10), randf_range(-10, 10)), randf_range(2.0, 4.0), randf_range(2.0, 4.0), Color(0.35, 0.33, 0.32, 0.9), "smoke")
	for k in 30: fx.puff(fp, -sg.u * randf_range(20, 90) + Vector2(randf_range(-30, 30), randf_range(-60, 10)), 1.5, 1.0, Color("8d9198"), "bit")
	# a shot in a gassy mine is how disasters start
	if hazards.gas_of(sg) > 2.5 and randf() < 0.35:
		hazards._explode(segs[sg.root_of(segs)], hazards.gas_of(sg))

func mine_root(sg: Segment) -> Segment:
	return segs[sg.root_of(segs)]

func mine_closed(sg: Segment) -> bool:
	return mine_root(sg).decom

## Close a mine: the crews walk out, the belts stop with whatever is on them, and the roof is left to itself.
func decommission(root: Segment) -> void:
	if root.decom: return
	root.decom = true
	for w in workers:
		if w.task >= 0 and seg_alive(w.task) and mine_root(segs[w.task]).id == root.id: w.leave_and_idle()
	for c in cars:
		if c.task >= 0 and mine_root(segs[c.task]).id == root.id: c.state = "idle"; c.task = -1; c.cargo = []
	Game.toast.emit("Mine No.%d is decommissioned. The conveyor sits idle in there; salvage it or leave it to the roof." % mine_no(root))

func salvage(root: Segment) -> void:
	if not root.decom or root.salvage: return
	root.salvage = true
	Game.toast.emit("A miner will pull the conveyor out of mine No.%d at $0.60 a foot." % mine_no(root))

## A segment in a closed mine still holding belt to salvage, nearest the portal first.
func salvage_target(root: Segment) -> Segment:
	var best: Segment = null
	for sg in segs:
		if sg.dead or mine_root(sg).id != root.id or not sg.has_belt or sg.belt < 0.5: continue
		if best == null or sg.id < best.id: best = sg
	return best

func filter_value(sg: Segment) -> float:
	match view_filter:
		1: return clampf(hazards.gas_of(sg) / 5.0, 0.0, 1.0)
		2: return clampf(hazards.gas_of(sg) / 3.5 + (0.25 if sg.coal_cells > 0 else 0.0) + (0.3 if sg.rig >= 0 else 0.0), 0.0, 1.0)
		3: return 1.0 if sg.rubble.size() > 0 else clampf(sg.stress, 0.0, 1.0)
		4: return clampf(sg.water / 0.75, 0.0, 1.0)
		5: return clampf((sg.pt + sg.prog) / (260.0 * (1.0 + 1.2 * float(Game.up.get("vent", 0)))), 0.0, 1.0)
	return 0.0

func mine_no(sg: Segment) -> int:
	var root := sg.root_of(segs)
	var n := 0
	for s in segs:
		if s.parent < 0 and s.id <= root: n += 1
	return n

func pick_face(w: Worker) -> Segment:
	var best: Segment = null; var bs := INF
	for sg in segs:
		if sg.dead or sg.crew.size() >= 2 or mine_closed(sg): continue
		var rub: bool = sg.rubble.size() > 0
		if hazards.flooded(sg) or hazards.gas_out(sg): continue
		if not rub and sg.done(): continue
		var f: Vector2 = sg.pos(sg.rubble[0] if rub else sg.prog)
		var sc: float = f.distance_to(w.position) + sg.crew.size() * 700.0 - (1500.0 if rub else 0.0)
		if sc < bs: bs = sc; best = sg
	return best

func leave_face(w: Worker) -> void:
	if w.task >= 0 and w.task < segs.size():
		segs[w.task].crew.erase(w.id)
	w.task = -1

func seg_alive(id: int) -> bool:
	return id >= 0 and id < segs.size() and not segs[id].dead

## Waypoints from where a worker stands to a point in a tunnel (or to an x on the surface when seg is -1):
## out through the parent chain to the surface, along the hill, and in through the target's chain.
func build_path(w: Worker, seg: int, s: float) -> Array:
	var out: Array = []
	var chain_from := _chain(w.seg)
	var chain_to := _chain(seg)
	# common ancestor lets a worker switch between branches without surfacing
	var common := -1
	for id in chain_from:
		if chain_to.has(id): common = id; break
	if common >= 0:
		var cur := w.seg
		while cur != common:
			var sg: Segment = segs[cur]
			out.append([cur, 0.0]); out.append([sg.parent, sg.pt]); cur = sg.parent
		var ids := []
		var c2 := seg
		while c2 != common:
			ids.push_front(c2); c2 = segs[c2].parent
		for id in ids:
			var sg: Segment = segs[id]
			out.append([sg.parent, sg.pt]); out.append([id, 0.0])
		out.append([seg, s])
		return out
	# walk out to daylight
	var cur := w.seg
	while cur >= 0:
		var sg: Segment = segs[cur]
		out.append([cur, 0.0])
		if sg.parent >= 0: out.append([sg.parent, sg.pt])
		cur = sg.parent
	if seg < 0:
		out.append([-1, s]); return out
	# then in through the target chain
	var ids := []
	var c3 := seg
	while c3 >= 0:
		ids.push_front(c3); c3 = segs[c3].parent
	var root: Segment = segs[ids[0]]
	out.append([-1, root.a.x])
	for id in ids:
		var sg: Segment = segs[id]
		if sg.parent >= 0: out.append([sg.parent, sg.pt])
		out.append([id, 0.0])
	out.append([seg, s])
	return out

func _chain(seg: int) -> Array:
	var ids := []
	var cur := seg
	while cur >= 0:
		ids.append(cur); cur = segs[cur].parent
	return ids

func waypoint_pos(wp: Array) -> Vector2:
	if wp[0] < 0: return Vector2(wp[1], Terrain.ground_y(wp[1]))
	return segs[wp[0]].floor_pos(wp[1])

# ---------- tunnels ----------
func nearest_seg(p: Vector2, within: float) -> Dictionary:
	var best := {}; var bd := within
	for sg in segs:
		if sg.dead or sg.prog < 1.0: continue
		var s := clampf((p - sg.a).dot(sg.u), 0.0, sg.prog)
		var d: float = p.distance_to(sg.pos(s))
		if d < bd: bd = d; best = {"seg": sg, "s": s}
	return best

## Where a drag may start: on the hillside surface (a new portal) or on an existing tunnel (a branch).
func snap_start(p: Vector2) -> Dictionary:
	var n := nearest_seg(p, Segment.R + 6.0)
	if not n.is_empty():
		return {"seg": n.seg.id, "s": n.s, "pos": n.seg.pos(n.s)}
	if p.x > Terrain.HILL - 200.0 and absf(p.y - Terrain.ground_y(p.x)) < 18.0:
		return {"seg": -1, "s": 0.0, "pos": Vector2(p.x, Terrain.ground_y(p.x) + Segment.R)}
	return {}

## A straight plan from the start toward the pointer, stopped by bedrock, the sky or another tunnel.
func plan_to(st: Dictionary, p: Vector2) -> Dictionary:
	var a: Vector2 = st.pos
	var dir := (p - a)
	var L := minf(dir.length(), 900.0)
	if L < 24.0: return {}
	var u := dir / dir.length()
	if st.seg < 0 and u.y < 0.12: return {}      # a portal has to go into the hill, not up into the air
	if st.seg < 0 and absf(u.x) < 0.4: u = Vector2(0, 1)   # a near-vertical start becomes a true shaft
	var tons := 0.0; var cells := 0
	var s := 0.0
	while s < L:
		var q := a + u * s
		var m := terrain.mat_world(q.x, q.y)
		if m == Mats.BED or (s > 20.0 and m == Mats.AIR and q.y < Terrain.ground_y(q.x) - 2.0): break
		if s > 2 * Segment.R + 6 and _clash(q, st.seg, s): break
		if m == Mats.COAL and not terrain.is_dug(q.x, q.y): tons += Mats.TONS_COAL * 5.0
		cells += 1; s += 4.0
	L = s
	if L < 24.0: return {}
	return {"a": a, "b": a + u * L, "len": L, "tons": round(tons), "cost": round(L * COST_PER_FT), "parent": st.seg, "pt": st.s}

func _clash(q: Vector2, parent: int, s: float) -> bool:
	for sg in segs:
		if sg.dead: continue
		var t := clampf((q - sg.a).dot(sg.u), 0.0, sg.length)
		var d: float = q.distance_to(sg.pos(t))
		if sg.id == parent:
			if s > 70.0 and d < 2 * Segment.R + 4: return true
		elif d < 2 * Segment.R + 4: return true
	return false

func make_segment(pl: Dictionary) -> Segment:
	var sg := Segment.new()
	sg.id = segs.size()
	sg.setup(pl.a, pl.b, pl.parent, pl.pt)
	sg.has_belt = plan_belt or sg.is_shaft()
	segs.append(sg)
	return sg

func stop_segment(sg: Segment) -> void:
	sg.length = maxf(sg.prog, 1.0); sg.b = sg.a + sg.u * sg.length
	hud.show_toast("Bedrock. That tunnel stops at %d ft." % int(sg.prog))

## Drive the face forward: dig the cells out of the grid and put what came out onto the belt.
func advance(sg: Segment, ds: float) -> void:
	var old := sg.prog
	sg.prog = minf(sg.length, sg.prog + ds)
	while sg.carved < sg.prog:
		sg.carved = minf(sg.prog, sg.carved + 2.0)
		var p := sg.pos(sg.carved)
		for cell in terrain.carve(p.x, p.y, sg.u, Segment.R * 0.9, Segment.R):
			var m: int = cell[0]
			if m == Mats.COAL: sg.coal_cells += 1
			items.append([sg.id, sg.carved, m, Mats.tons(m), not sg.has_belt])
	if sg.has_belt: sg.belt = maxf(sg.belt, sg.prog - 4.0)
	Game.pay(-COST_PER_FT * (sg.prog - old))
	Game.dug_ft += sg.prog - old

# ---------- the flow of material ----------
func _tick_items(dt: float) -> void:
	var keep := []
	for it in items:
		if it[4]: keep.append(it); continue
		if it[0] >= 0:
			var sg: Segment = segs[it[0]]
			if mine_closed(sg) or sg.belt < it[1]: keep.append(it); continue
			it[1] -= BELT_SPEED * (3.0 if sg.is_shaft() else 1.0) * dt
			if it[1] <= 0.0:
				if sg.parent >= 0:
					it[0] = sg.parent; it[1] = sg.pt
				else:
					it[0] = -1; it[1] = absf(sg.a.x - HEAD_X)
		else:
			it[1] -= BELT_SPEED * 1.6 * dt
			if it[1] <= 0.0:
				var m: int = it[2]
				if m == Mats.COAL: Game.pile += it[3]
				else: Game.piles[m] = Game.piles.get(m, 0.0) + it[3]
				continue
		keep.append(it)
	items = keep

func _tick_trucks(dt: float) -> void:
	# a contract truck comes for every 20 t on the pile
	if Game.pile >= TRUCK_LOAD and trucks.size() < 3 and (trucks.is_empty() or trucks.back().x > -200.0):
		trucks.append({"x": -600.0, "state": "in", "t": 0.0, "load": 0.0})
	for t in trucks:
		match t.state:
			"in":
				t.x = minf(PILE_X - 70.0, t.x + dt * 110.0)
				if t.x >= PILE_X - 70.0: t.state = "load"; t.t = 0.0
			"load":
				t.t += dt
				var q := minf(Game.pile, dt * 6.0)
				Game.pile -= q; t.load += q
				if t.load >= TRUCK_LOAD or (Game.pile <= 0.0 and t.t > 2.0):
					t.state = "out"
			"out":
				t.x -= dt * 110.0
				if t.x < -400.0:
					var pay: float = t.load * Game.price
					Game.pay(pay); sold_tons += t.load
					t.state = "gone"
	trucks = trucks.filter(func(t): return t.state != "gone")

func _tick_wages(dt: float) -> void:
	var w := 0.0
	for m in workers: w += m.wage
	Game.pay(-w * dt / Game.DAY_LEN)
	# sell the other materials straight off the yard
	for m in Game.piles.keys():
		var t: float = Game.piles[m]
		if t >= 1.0:
			var q := minf(t, dt * 0.5)
			Game.piles[m] = t - q
			Game.pay(q * Mats.VALUE.get(m, 0.0))

func _process(delta: float) -> void:
	if not Game.paused:
		var dt := minf(delta, 0.05) * Game.speed
		var steps := int(ceil(dt / 0.05))
		for i in steps:
			var sub := dt / steps
			Game.tick(sub)
			for w in workers: w.tick(sub)
			for c in cars: c.tick(sub)
			_tick_items(sub); _tick_trucks(sub); _tick_wages(sub); hazards.tick(sub); fx.tick(sub)
	shake = maxf(0.0, shake - delta)
	cam.offset = Vector2(randf_range(-6, 6), randf_range(-6, 6)) * shake if shake > 0.0 else Vector2.ZERO
	queue_redraw()

# ---------- input ----------
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var p := get_global_mouse_position()
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				var st := snap_start(p)
				if not st.is_empty():
					drag_start = st; drag_plan = {}
					get_viewport().set_input_as_handled()
			elif not drag_start.is_empty():
				if not drag_plan.is_empty():
					if Game.money >= drag_plan.cost:
						make_segment(drag_plan)
					else:
						hud.show_toast("That tunnel needs $%d of conveyor and you have $%d." % [int(drag_plan.cost), int(Game.money)])
				drag_start = {}; drag_plan = {}
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: cam.zoom_at(p, 1.15)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: cam.zoom_at(p, 1.0 / 1.15)
	elif e is InputEventMouseMotion:
		hover = get_global_mouse_position()
		if not drag_start.is_empty():
			drag_plan = plan_to(drag_start, hover)
		elif e.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT):
			cam.position -= e.relative / cam.zoom.x
	elif e.is_action_pressed("pause"):
		Game.paused = not Game.paused

# ---------- drawing ----------
func _draw() -> void:
	_draw_yard()
	for sg in segs:
		if sg.dead or sg.prog < 0.5: continue
		_draw_tunnel(sg)
	for sg in segs:
		if sg.dead or sg.parent >= 0 or sg.prog < 0.5: continue
		if sg.is_shaft(): _draw_headframe(sg)
		else: _draw_portal(sg)
		_draw_gantry(sg)
	# material riding the belts
	for it in items:
		var p: Vector2
		if it[4]:
			var sgw: Segment = segs[it[0]]
			var k: int = hash(it) % 100
			p = sgw.floor_pos(maxf(0.0, sgw.prog - 3.0 - (k % 10) * 1.6)) - sgw.n * (1.0 + (k / 10) * 1.2)
		elif it[0] >= 0:
			var sg: Segment = segs[it[0]]
			p = sg.floor_pos(it[1]) - sg.n * 2.0
		else:
			var root := _root_for_overland(it)
			if root == null: continue
			var t: float = it[1] / maxf(1.0, absf(root.a.x - HEAD_X))
			p = Vector2(HEAD_X, -118.0).lerp(Vector2(root.a.x, Terrain.ground_y(root.a.x) - 6.0), t)
		draw_rect(Rect2(p.x - 1.4, p.y - 2.8, 2.8, 2.8), Mats.COLORS[it[2]].lightened(0.15))
	for t in trucks: _draw_truck(t)
	if view_filter > 0:
		var fc: Color = [Color.WHITE, Color(0.55, 0.95, 0.35), Color(1.0, 0.5, 0.15), Color(1.0, 0.25, 0.2), Color(0.3, 0.6, 1.0), Color(0.4, 0.9, 0.95)][view_filter]
		for sg in segs:
			if sg.dead or sg.prog < 0.5: continue
			var v := filter_value(sg)
			draw_line(sg.pos(0.0), sg.pos(sg.prog), Color(fc.r, fc.g, fc.b, 0.18 + 0.62 * v), Segment.R * 2.0)
	fx.draw(self)
	# the plan being dragged
	if not drag_plan.is_empty():
		draw_line(drag_plan.a, drag_plan.b, Color(0.52, 0.72, 0.42, 0.35), Segment.R * 2.0)
		draw_line(drag_plan.a, drag_plan.b, Color("86b86a"), 2.0)
		draw_circle(drag_plan.a, 3.5, Color("86b86a")); draw_circle(drag_plan.b, 3.5, Color("86b86a"))
	elif not drag_start.is_empty():
		draw_circle(drag_start.pos, 4.0, Color("86b86a"))
	else:
		var st := snap_start(hover)
		if not st.is_empty(): draw_arc(st.pos, 6.0, 0.0, TAU, 24, Color(0.95, 0.72, 0.02, 0.95), 1.5)

func _root_for_overland(it: Array) -> Segment:
	# overland items carry no root; use the nearest portal by remaining distance (good enough for one mine, refined later)
	var best: Segment = null
	for sg in segs:
		if sg.dead or sg.parent >= 0: continue
		if best == null or absf(absf(sg.a.x - HEAD_X) - it[1]) < absf(absf(best.a.x - HEAD_X) - it[1]): best = sg
	return best

func _draw_tunnel(sg: Segment) -> void:
	var a := sg.pos(0.0); var b := sg.pos(sg.prog)
	var closed := mine_closed(sg)
	# broken rim, then the dark interior, then the back wall showing the rock it was cut through
	draw_line(a - sg.u * (Segment.R if sg.parent < 0 else 0.0), b, Color("130e0c"), Segment.R * 2.0 + 6.0)
	var s := 0.0
	while s < sg.prog:
		var p := sg.pos(s + 2.0)
		var m := terrain.mat_world(p.x, p.y)
		draw_line(sg.pos(s), sg.pos(minf(sg.prog, s + 4.0)), Mats.COLORS[m].darkened(0.55), Segment.R * 2.0)
		s += 4.0
	# the conveyor along the floor
	if sg.is_shaft():
		draw_line(sg.pos(0.0) - sg.n * 7.0, b - sg.n * 7.0, Color("5a5d63"), 1.0)
		draw_line(sg.pos(0.0) + sg.n * 7.0, b + sg.n * 7.0, Color("5a5d63"), 1.0)
	elif sg.has_belt and sg.belt > 1.0:
		var f0 := sg.floor_pos(0.0); var f1 := sg.floor_pos(sg.belt)
		draw_line(f0, f1, Color("5a3a28") if closed else Color("2a2a2e"), 2.2)
		var k := 0.0
		var ph := 0.0 if closed else fmod(Game.time * BELT_SPEED, 14.0)
		while k < sg.belt:
			draw_circle(sg.floor_pos(k) + sg.n * 1.4, 0.9, Color("8d9198")); k += 14.0
		var m2 := fmod(-ph, 14.0)
		while m2 < sg.belt:
			if m2 >= 0.0: draw_line(sg.floor_pos(m2) - sg.n * 0.8, sg.floor_pos(minf(sg.belt, m2 + 4.0)) - sg.n * 0.8, Color("3f3f45"), 1.0)
			m2 += 14.0
	# lamps every 70 ft
	var l := 35.0
	while l < sg.prog:
		var lp := sg.pos(l) - sg.n * (Segment.R - 2.5)
		draw_circle(lp, 1.2, Color("fff2b0"))
		draw_circle(lp, 10.0, Color(1.0, 0.9, 0.6, 0.07))
		l += 70.0
	# roof bolts (or timber posts on the first tier) as far as the roof is supported
	var k2 := 6.0
	var tier: int = Game.up.get("roof", 0)
	while k2 < sg.sup:
		var rp := sg.pos(k2) - sg.n * (Segment.R - 0.5)
		if tier == 0:
			draw_line(sg.pos(k2) - sg.n * Segment.R, sg.pos(k2) + sg.n * Segment.R, Color("7a5a3a"), 1.8)
		else:
			draw_rect(Rect2(rp.x - 1.5, rp.y - 0.6, 3.0, 1.2), Color("8a8f96"))
		k2 += 12.0
	# the unsupported span shows its strain
	if sg.stress > 0.3:
		draw_line(sg.pos(sg.sup) - sg.n * Segment.R, sg.pos(sg.prog) - sg.n * Segment.R, Color(1.0, 0.3, 0.2, (sg.stress - 0.3) * 0.9), 2.0)
	# water standing on the floor
	if sg.water > 0.02:
		var wd := sg.water * 2.0 * Segment.R
		var p0 := sg.pos(0.0); var p1 := sg.pos(sg.prog)
		draw_colored_polygon(PackedVector2Array([p0 + sg.n * Segment.R, p1 + sg.n * Segment.R, p1 + sg.n * (Segment.R - wd), p0 + sg.n * (Segment.R - wd)]), Color(0.3, 0.5, 0.8, 0.55))
	# rubble from a cave-in
	if sg.rubble.size() > 0:
		var ra := sg.pos(sg.rubble[0]); var rb := sg.pos(sg.rubble[1])
		draw_line(ra, rb, Color("3a3338"), Segment.R * 2.0)
		var j: float = sg.rubble[0]
		while j < sg.rubble[1]:
			var rp := sg.pos(j) + sg.n * (Segment.R - 3.0 - fposmod(j * 7.3, 9.0))
			draw_circle(rp, 2.0 + fposmod(j * 3.1, 2.0), Color("55505a")); j += 5.0
	# methane haze near the roof
	var g := hazards.gas_of(sg)
	if g > 0.3:
		draw_line(a - sg.n * (Segment.R - 3.0), b - sg.n * (Segment.R - 3.0), Color(0.6, 0.9, 0.5, minf(0.35, g * 0.08)), 6.0)
	# the face
	if not sg.done():
		draw_line(b - sg.n * Segment.R, b + sg.n * Segment.R, Color("0a0806"), 2.0)

func _draw_portal(sg: Segment) -> void:
	var x := sg.a.x; var gy := Terrain.ground_y(x)
	var o := -signf(sg.u.x)
	# timber portal set and the mine sign
	draw_rect(Rect2(x - 7.0, gy - 26.0, 14.0, 28.0), Color("6b4a2c"))
	draw_rect(Rect2(x - 5.0, gy - 23.0, 10.0, 25.0), Color("0d0a08"))
	_sign(Vector2(x + o * 10.0, gy - 36.0), "MINE No.%d" % mine_no(sg))
	if sg.decom:
		# boarded over, with a CLOSED board nailed across the posts
		for k in 3: draw_line(Vector2(x - 6.0, gy - 20.0 + k * 7.0), Vector2(x + 6.0, gy - 17.0 + k * 7.0), Color("7a5a3a"), 2.0)
		draw_rect(Rect2(x - 15.0, gy - 12.0, 30.0, 7.0), Color("c9c2b3"))
		draw_rect(Rect2(x - 15.0, gy - 12.0, 30.0, 7.0), Color("7a3a2a"), false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(x - 12.0, gy - 6.5), "CLOSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("7a3a2a"))

func _draw_headframe(sg: Segment) -> void:
	var x := sg.a.x; var gy := Terrain.ground_y(x)
	# an A-frame headframe with the sheave wheel on top and the hoist house beside it
	draw_line(Vector2(x - 16.0, gy), Vector2(x, gy - 58.0), Color("3a3d44"), 3.0)
	draw_line(Vector2(x + 16.0, gy), Vector2(x, gy - 58.0), Color("3a3d44"), 3.0)
	draw_line(Vector2(x + 30.0, gy), Vector2(x + 2.0, gy - 56.0), Color("4a4f55"), 2.0)
	for k in 4: draw_line(Vector2(x - 12.0 + k * 3.0, gy - 10.0 - k * 12.0), Vector2(x + 12.0 - k * 3.0, gy - 10.0 - k * 12.0), Color("4a4f55"), 1.2)
	draw_circle(Vector2(x, gy - 58.0), 6.0, Color("2f3238")); draw_circle(Vector2(x, gy - 58.0), 2.0, Color("8a8f96"))
	draw_rect(Rect2(x + 26.0, gy - 18.0, 26.0, 18.0), Color("8c6640")); draw_rect(Rect2(x + 24.0, gy - 21.0, 30.0, 4.0), Color("4a3a2a"))
	draw_line(Vector2(x + 2.0, gy - 58.0), Vector2(x + 40.0, gy - 18.0), Color("1d1c20"), 1.0)
	# the cage on its rope, running the shaft
	var depth: float = sg.prog
	var cs := fposmod(Game.time * 25.0, maxf(2.0, depth * 2.0))
	if cs > depth: cs = depth * 2.0 - cs
	var cp := sg.pos(cs)
	draw_line(Vector2(x, gy - 58.0), cp + Vector2(0, -8.0), Color("1d1c20"), 1.0)
	draw_rect(Rect2(cp.x - 7.0, cp.y - 8.0, 14.0, 12.0), Color("e0a51c"))
	draw_rect(Rect2(cp.x - 6.0, cp.y - 7.0, 12.0, 10.0), Color(0.1, 0.1, 0.12))
	for k in 3: draw_line(Vector2(cp.x - 6.0, cp.y - 5.0 + k * 3.0), Vector2(cp.x + 6.0, cp.y - 5.0 + k * 3.0), Color("e0a51c"), 0.8)
	_sign(Vector2(x - 26.0, gy - 24.0), "SHAFT No.%d" % mine_no(sg))

func _draw_gantry(sg: Segment) -> void:
	# the overland conveyor from the portal down to the head tower above the stockpile
	var a := Vector2(sg.a.x, Terrain.ground_y(sg.a.x) - 6.0)
	var b := Vector2(HEAD_X, -118.0)
	draw_line(a, b, Color("1d1c20"), 3.0)
	draw_line(a + Vector2(0, -3), b + Vector2(0, -3), Color("4a4f55"), 1.0)
	var L := a.distance_to(b)
	var k := 0.0
	while k < L:
		var p := a.lerp(b, k / L)
		draw_line(p, Vector2(p.x, Terrain.ground_y(p.x)), Color("3a3d44"), 1.2)
		k += 60.0

func _draw_yard() -> void:
	# head tower: a braced steel frame with the drive house on top
	var hx := HEAD_X
	draw_rect(Rect2(hx - 9.0, -118.0, 18.0, 118.0), Color("2f3238"))
	for k in 9:
		var y := -110.0 + k * 13.0
		draw_line(Vector2(hx - 9.0, y), Vector2(hx + 9.0, y + 13.0), Color("4a4f55"), 1.0)
		draw_line(Vector2(hx + 9.0, y), Vector2(hx - 9.0, y + 13.0), Color("4a4f55"), 1.0)
	draw_rect(Rect2(hx - 14.0, -132.0, 28.0, 14.0), Color("8a8f96"))
	draw_rect(Rect2(hx - 14.0, -134.0, 28.0, 2.5), Color("1d1c20"))
	draw_circle(Vector2(hx - 6.0, -118.0), 4.5, Color("1d1c20"))
	# stacker belt out over the stockpile and the surge bin under the head
	draw_rect(Rect2(hx - 16.0, -104.0, 20.0, 16.0), Color("3f454c"))
	draw_line(Vector2(hx - 6.0, -116.0), Vector2(PILE_X + 40.0, -72.0), Color("1d1c20"), 3.5)
	draw_line(Vector2(hx - 6.0, -119.5), Vector2(PILE_X + 40.0, -75.5), Color("6a6f78"), 1.0)
	for k in 6:
		var px := PILE_X + 40.0 + k * ((hx - 6.0) - (PILE_X + 40.0)) / 6.0
		var py := -72.0 + k * (-116.0 + 72.0) / 6.0
		draw_line(Vector2(px, py), Vector2(px, 0.0), Color("3a3d44"), 1.5)
	var r := minf(70.0, 10.0 + sqrt(maxf(0.0, Game.pile)) * 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(PILE_X - r, 0), Vector2(PILE_X - r * 0.3, -r * 0.62), Vector2(PILE_X + r * 0.2, -r * 0.6), Vector2(PILE_X + r, 0)]), Color("1d1c20"))
	draw_colored_polygon(PackedVector2Array([Vector2(PILE_X - r * 0.6, 0), Vector2(PILE_X - r * 0.25, -r * 0.5), Vector2(PILE_X, 0)]), Color("2a292e"))
	var ox := PILE_X + 110.0
	for m in Game.piles.keys():
		var t: float = Game.piles[m]
		var rr := minf(30.0, 3.0 + sqrt(t) * 5.0)
		draw_colored_polygon(PackedVector2Array([Vector2(ox - rr, 0), Vector2(ox, -rr * 0.6), Vector2(ox + rr, 0)]), Mats.COLORS[m])
		ox += 70.0
	# scale house and the weighbridge
	draw_rect(Rect2(-64.0, -1.5, 90.0, 3.0), Color("6a6f78"))
	draw_rect(Rect2(-60.0, -26.0, 36.0, 26.0), Color("8c6640"))
	draw_rect(Rect2(-63.0, -30.0, 42.0, 5.0), Color("4a3a2a"))
	draw_rect(Rect2(-52.0, -20.0, 8.0, 8.0), Color("f2d36b"))
	draw_rect(Rect2(-36.0, -20.0, 8.0, 8.0), Color("f2d36b"))
	_sign(Vector2(-42.0, -36.0), "SCALE HOUSE")
	# crew quarters: a long bunkhouse with a porch and windows
	var bx := Worker.BUNK_X
	draw_rect(Rect2(bx - 36.0, -24.0, 72.0, 24.0), Color("cfc9bd"))
	draw_rect(Rect2(bx - 39.0, -29.0, 78.0, 6.0), Color("5a4028"))
	for k in 4: draw_rect(Rect2(bx - 30.0 + k * 18.0, -18.0, 7.0, 7.0), Color("7fa6c9"))
	draw_rect(Rect2(bx + 16.0, -14.0, 9.0, 14.0), Color("4a3a2a"))
	draw_rect(Rect2(bx - 40.0, -1.0, 80.0, 1.5), Color("8c8c8c"))
	_sign(Vector2(bx, -36.0), "CREW QUARTERS")
	# the manager's office trailer
	draw_rect(Rect2(Worker.OFFICE_X - 22.0, -18.0, 44.0, 18.0), Color("e8e4d8"))
	draw_rect(Rect2(Worker.OFFICE_X - 24.0, -21.0, 48.0, 3.0), Color("4a4a55"))
	draw_rect(Rect2(Worker.OFFICE_X - 14.0, -14.0, 8.0, 7.0), Color("7fa6c9"))
	_sign(Vector2(Worker.OFFICE_X, -28.0), "OFFICE")
	# the haul road out to the highway
	draw_line(Vector2(-700.0, 1.5), Vector2(Terrain.HILL, 1.5), Color("4a3f36"), 3.0)
	var dx := -680.0
	while dx < Terrain.HILL:
		draw_line(Vector2(dx, 1.5), Vector2(dx + 14.0, 1.5), Color("c9b86a"), 0.8); dx += 40.0

func _sign(at: Vector2, text: String) -> void:
	var w := text.length() * 4.2 + 8.0
	draw_rect(Rect2(at.x - w * 0.5, at.y - 6.0, w, 9.0), Color("2b2a2e"))
	draw_rect(Rect2(at.x - w * 0.5, at.y - 6.0, 2.0, 9.0), Color("f2b705"))
	draw_string(ThemeDB.fallback_font, Vector2(at.x - w * 0.5 + 4.0, at.y + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color("f1efe6"))

func _draw_truck(t: Dictionary) -> void:
	var x: float = t.x
	var d := 1.0 if t.state == "in" else -1.0
	draw_rect(Rect2(x - 22.0, -14.0, 36.0, 10.0), Color("8a2f23"))
	draw_rect(Rect2(x + 14.0 * d - (0.0 if d > 0 else 12.0), -16.0, 12.0, 12.0), Color("b23a2a"))
	var f: float = t.load / TRUCK_LOAD
	if f > 0.05: draw_rect(Rect2(x - 20.0, -14.0 - 5.0 * f, 32.0, 5.0 * f), Color("1d1c20"))
	for wx in [-14.0, 0.0, 14.0]: draw_circle(Vector2(x + wx, -3.0), 3.2, Color("1a1a1e"))

# ---------- headless smoke test: godot --headless --path . -- --smoke ----------
func _smoke() -> void:
	var st := snap_start(Vector2(2200.0, Terrain.ground_y(2200.0)))
	var pl := plan_to(st, Vector2(2200.0 + 300.0, Terrain.ground_y(2200.0) + 90.0))
	if pl.is_empty():
		print("FAIL: no plan"); get_tree().quit(1); return
	var sg := make_segment(pl)
	Game.money = 20000.0
	buy_rig()
	# a second heading steeply down into rock, so drilling and blasting gets exercised
	var st2 := snap_start(Vector2(2600.0, Terrain.ground_y(2600.0)))
	var pl2 := plan_to(st2, Vector2(2800.0, Terrain.ground_y(2600.0) + 330.0))
	var sg2: Segment = make_segment(pl2) if not pl2.is_empty() else null
	plan_belt = false
	var st3 := {"seg": sg.id, "s": 120.0, "pos": sg.pos(120.0)}
	var pl3 := plan_to(st3, sg.pos(120.0) + Vector2(-200.0, 60.0))
	var sg3: Segment = make_segment(pl3) if not pl3.is_empty() else null
	plan_belt = true
	buy_car()
	for i in 5: hire(Worker.Role.MINER)
	hire(Worker.Role.BOLTER)
	var frames := 0
	var ok := true
	while frames < 6000 and Game.day < 4:
		Game.tick(0.05)
		for w in workers: w.tick(0.05)
		for c in cars: c.tick(0.05)
		_tick_items(0.05); _tick_trucks(0.05); _tick_wages(0.05); hazards.tick(0.05); fx.tick(0.05)
		frames += 1
		if frames == 2400 and sg2: decommission(sg2); salvage(sg2)
		if frames % 600 == 0:
			var ws := ""
			for w in workers: ws += "%d:%s/%d/%d/%.0f " % [w.role, ["I","W","D","K","R"][w.state], w.task, w.path.size(), w.energy]
			print("t=%d prog=%d/%d crew=%s items=%d pile=%.1f money=%d sold=%.1f  %s" % [int(Game.time), int(sg.prog), int(sg.length), str(sg.crew), items.size(), Game.pile, int(Game.money), sold_tons, ws])
	if sg.prog < 40.0: ok = false; print("FAIL: face barely moved")
	if sold_tons <= 0.0 and Game.pile <= 0.0 and items.size() == 0: ok = false; print("FAIL: nothing came out")
	print("RESULT %s prog=%d money=%d sold=%.1f coalcells=%d sup=%d stress=%.2f water=%.2f gas=%.2f rig=%d car=%s rock=%s" % [("OK" if ok else "FAIL"), int(sg.prog), int(Game.money), sold_tons, sg.coal_cells, int(sg.sup), sg.stress, sg.water, hazards.gas_of(sg), sg.rig, ("%s/%d/h%d prog=%d" % [cars[0].state, cars[0].cargo.size(), cars[0].hauled, int(sg3.prog)]) if sg3 else "none", ("%d/%d soft=%s bp=%d decom=%s belt=%.0f salv=%s" % [int(sg2.prog), int(sg2.length), sg2.soft, sg2.bp, sg2.decom, sg2.belt, sg2.salvage]) if sg2 else "none"])
	if sg2 and sg2.belt > 1.0: ok = false; print("FAIL: belt not salvaged")
	get_tree().quit(0 if ok else 1)

# ---------- screenshot for the build log: godot --path . -- --shot (needs a display, e.g. xvfb-run) ----------
func _shot() -> void:
	var st := snap_start(Vector2(2200.0, Terrain.ground_y(2200.0)))
	var sg := make_segment(plan_to(st, Vector2(2500.0, Terrain.ground_y(2200.0) + 90.0)))
	Game.money = 20000.0; buy_rig()
	var st2 := snap_start(Vector2(2600.0, Terrain.ground_y(2600.0)))
	var pl2 := plan_to(st2, Vector2(2800.0, Terrain.ground_y(2600.0) + 330.0))
	if not pl2.is_empty(): make_segment(pl2)
	# a bare branch for a shuttle car, and a shaft sunk from the hilltop
	plan_belt = false
	var pl3 := plan_to({"seg": sg.id, "s": 100.0, "pos": sg.pos(100.0)}, sg.pos(100.0) + Vector2(-220.0, 50.0))
	if not pl3.is_empty(): make_segment(pl3)
	plan_belt = true
	buy_car()
	var st4 := snap_start(Vector2(1900.0, Terrain.ground_y(1900.0)))
	var pl4 := plan_to(st4, Vector2(1905.0, Terrain.ground_y(1900.0) + 240.0))
	var sg4: Segment = make_segment(pl4) if not pl4.is_empty() else null
	for i in 6: hire(Worker.Role.MINER)
	hire(Worker.Role.BOLTER)
	for f in 2400:
		Game.tick(0.05)
		for w in workers: w.tick(0.05)
		for c in cars: c.tick(0.05)
		_tick_items(0.05); _tick_trucks(0.05); _tick_wages(0.05); hazards.tick(0.05); fx.tick(0.05)
	cam.position = sg.pos(60.0); cam.zoom = Vector2(2.5, 2.5)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shot1.png")
	cam.position = Vector2(1500.0, -140.0); cam.zoom = Vector2(0.75, 0.75)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shot2.png")
	if segs.size() > 1:
		var s2: Segment = segs[1]
		cam.position = s2.pos(maxf(0.0, s2.prog - 30.0)); cam.zoom = Vector2(3.0, 3.0)
		for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://shot3.png")
	if sg4:
		cam.position = sg4.pos(20.0) + Vector2(0, -30.0); cam.zoom = Vector2(2.2, 2.2)
		for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://shot4.png")
	# night over the yard, then the methane filter
	Game.time = floorf(Game.time / Game.DAY_LEN) * Game.DAY_LEN + Game.DAY_LEN * 0.78
	cam.position = Vector2(1900.0, -150.0); cam.zoom = Vector2(0.9, 0.9)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shot6.png")
	Game.time = floorf(Game.time / Game.DAY_LEN) * Game.DAY_LEN + 5.0
	view_filter = 1; hud.view.select(1); hud.view.item_selected.emit(1)
	cam.position = sg.pos(80.0); cam.zoom = Vector2(1.4, 1.4)
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://shot7.png")
	view_filter = 0; hud.view.select(0); hud.view.item_selected.emit(0)
	if cars.size() > 0 and cars[0].task >= 0:
		cam.position = cars[0].position; cam.zoom = Vector2(3.0, 3.0)
		for i in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://shot5.png")
	print("SHOTS ", OS.get_user_data_dir())
	get_tree().quit()

# ---------- the manager: new headings toward coal whenever the crews are short of faces ----------
func auto_plan() -> void:
	var miners := workers.filter(func(w): return w.role == Worker.Role.MINER).size()
	var open := segs.filter(func(sg): return not sg.dead and not mine_closed(sg) and sg.prog < sg.length - 40.0 and sg.rubble.is_empty()).size()
	var want := maxi(1, int(ceil(miners / 2.0)))
	if open >= want or Game.money < 400.0: return
	var starts := []
	for sg in segs:
		if sg.dead or not sg.done() or sg.rubble.size() > 0 or mine_closed(sg): continue
		var s := 24.0
		while s < sg.prog - 8.0:
			starts.append({"seg": sg.id, "s": s, "pos": sg.pos(s)}); s += 26.0
	if segs.filter(func(sg): return not sg.dead and sg.parent < 0).size() < 3:
		for k in 8:
			var x := Terrain.HILL + 300.0 + k * 220.0
			if not segs.any(func(sg): return sg.parent < 0 and absf(sg.a.x - x) < 120.0):
				starts.append({"seg": -1, "s": 0.0, "pos": Vector2(x, Terrain.ground_y(x) + Segment.R)})
	var best := {}; var bv := 0.0
	for st in starts:
		for dir in [-1.0, 1.0]:
			var ang := -0.4
			while ang <= 0.7:
				var pl := plan_to(st, st.pos + Vector2(cos(ang) * dir, sin(ang)) * 400.0)
				ang += 0.1
				if pl.is_empty() or pl.len < 60.0 or pl.tons < 30.0: continue
				var val: float = pl.tons * Game.price - pl.cost * 14.0
				if val > bv: bv = val; best = pl
	if best.is_empty(): return
	make_segment(best)
	Game.toast.emit("The manager laid out a new %d ft heading toward about %d t of coal." % [int(best.len), int(best.tons)])
