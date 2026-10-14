## A worker: miners dig and clear rubble, roof bolters follow the faces bolting the roof, safety men walk the
## mine checking gas, and the manager plans new headings from the office.
class_name Worker
extends Node2D

enum State { IDLE, WALK, DIG, WORK, REST }
enum Role { MINER, BOLTER, SAFETY, MANAGER }

const WALK_SPEED := 42.0
const BUNK_X := 1300.0
const OFFICE_X := 1180.0
const ROLE_NAME := ["miner", "roof bolter", "safety man", "manager"]
const ROLE_WAGE := [40.0, 52.0, 64.0, 90.0]
const NAMES_FIRST := ["Earl", "Dewey", "Lonnie", "Roy", "Clyde", "Vernon", "Ray", "Otis", "Wade", "Hollis", "June", "Darlene", "Opal", "Wanda"]
const NAMES_LAST := ["Hatfield", "Caudill", "Mullins", "Slone", "Combs", "Blankenship", "Adkins", "Vance", "Tackett", "Justice"]

var id := -1
var role := Role.MINER
var worker_name := ""
var skill := 1.0
var wage := 40.0
var energy := 100.0
var state := State.IDLE
var seg := -1
var s := 0.0
var face_dir := 1.0
var task := -1                    # segment being worked, -2 heading home
var clearing := false             # a miner digging out rubble rather than coal
var salvaging := false
var pocket: Dictionary = {}       # the rib pocket this miner is brushing out by hand            # a miner pulling a dead conveyor out of a closed mine
var path: Array = []
var think := 0.0
var anim := 0.0
var work_t := 0.0
var rig := -1                     # continuous miner this miner drives
var world: Node = null

func _ready() -> void:
	worker_name = NAMES_FIRST[randi() % NAMES_FIRST.size()] + " " + NAMES_LAST[randi() % NAMES_LAST.size()]
	position = Vector2(BUNK_X + randf_range(-20, 20), 0)
	wage = round(ROLE_WAGE[role] * (0.5 + skill * 0.55))
	z_index = 5

func status() -> String:
	match state:
		State.REST: return "Resting in the crew quarters"
		State.WALK: return "Walking home" if task == -2 else "Walking to work"
		State.DIG: return "Digging out a cave-in" if clearing else ("Hand mining the rib" if not pocket.is_empty() else "At the face")
		State.WORK: return "Pulling out the conveyor" if salvaging else ["", "Bolting the roof", "Checking the air", "Planning"][role]
	return "Waiting for work"

func tick(dt: float) -> void:
	anim += dt
	match state:
		State.REST:
			energy = minf(100.0, energy + dt * 6.0)
			if energy >= 100.0: state = State.IDLE
		State.WALK: _walk(dt)
		State.DIG: _dig(dt)
		State.WORK: _work(dt)
		State.IDLE:
			think -= dt
			if think > 0: return
			think = 0.5
			if energy < 15.0: _go_home(); return
			match role:
				Role.MINER:
					if not _find_salvage() and not _find_pocket(true): _find_face()
				Role.BOLTER: _find_bolting()
				Role.SAFETY: _find_round()
				Role.MANAGER:
					position = Vector2(OFFICE_X, 0.0); state = State.WORK; work_t = 8.0
	queue_redraw()

func leave_and_idle() -> void:
	_park_rig()
	if not pocket.is_empty(): pocket.crew = -1; pocket = {}
	world.leave_face(self); state = State.IDLE; think = 0.0; clearing = false; salvaging = false; path = []

func _go_home() -> void:
	_park_rig()
	world.leave_face(self)
	path = world.build_path(self, -1, BUNK_X + randf_range(-16, 16))
	state = State.WALK; task = -2; clearing = false

func _park_rig() -> void:
	if rig < 0: return
	var r: Rig = world.rigs[rig]
	r.op = -1; r.cutting = false
	if r.seg >= 0 and world.seg_alive(r.seg): world.segs[r.seg].rig = -1
	rig = -1

func _find_pocket(ordered_only: bool) -> bool:
	if ordered_only and world.workers.filter(func(o): return not o.pocket.is_empty() and o.pocket.ord).size() >= 2: return false
	var r: Dictionary = world.pick_pocket(self, ordered_only)
	if r.is_empty(): return false
	pocket = r.pk; pocket.crew = id; task = r.seg.id
	path = world.build_path(self, task, pocket.s + World.PK_W * 0.5)
	state = State.WALK
	return true

func _find_face() -> void:
	var best: Segment = world.pick_face(self)
	if best == null:
		_find_pocket(false); return
	best.crew.append(id); task = best.id
	clearing = best.rubble.size() > 0
	if not clearing and best.rig < 0 and rig < 0:
		for r in world.rigs:
			if r.op < 0: r.op = id; rig = r.id; best.rig = r.id; break
	var at: float = (maxf(0.0, best.rubble[0] - 5.0 - 7.0 * (best.crew.size() - 1))) if clearing else maxf(0.0, best.prog - 6.0 - 7.0 * (best.crew.size() - 1))
	path = world.build_path(self, best.id, at)
	state = State.WALK

func _find_salvage() -> bool:
	for root in world.segs:
		if root.dead or root.parent >= 0 or not root.salvage: continue
		if world.workers.any(func(o): return o != self and o.salvaging and o.task >= 0 and world.mine_root(world.segs[o.task]).id == root.id): continue
		var sg: Segment = world.salvage_target(root)
		if sg == null: root.salvage = false; continue
		task = sg.id; salvaging = true
		path = world.build_path(self, sg.id, maxf(0.0, sg.belt - 2.0))
		state = State.WALK
		return true
	return false

func _find_bolting() -> void:
	var best: Segment = null; var bs := 0.0
	for sg in world.segs:
		if sg.dead or sg.rubble.size() > 0 or world.hazards.flooded(sg) or world.mine_closed(sg): continue
		var U: float = sg.prog - sg.sup
		if U < 10.0: continue
		if world.workers.any(func(o): return o != self and o.role == Role.BOLTER and o.task == sg.id): continue
		var sc: float = U * 4.0 + sg.stress * 2000.0 - sg.pos(sg.sup).distance_to(position) * 0.2
		if sc > bs: bs = sc; best = sg
	if best == null: return
	task = best.id
	path = world.build_path(self, best.id, best.sup + 3.0)
	state = State.WALK

func _find_round() -> void:
	var live: Array = world.segs.filter(func(sg): return not sg.dead and sg.prog > 20.0 and sg.rubble.is_empty() and not world.mine_closed(sg))
	if live.is_empty() or randf() < 0.4: return
	var sg: Segment = live[randi() % live.size()]
	task = sg.id
	path = world.build_path(self, sg.id, randf() * sg.prog)
	state = State.WALK

func _walk(dt: float) -> void:
	var d := WALK_SPEED * dt * (0.7 if energy < 30.0 else 1.0)
	while d > 0.0 and not path.is_empty():
		var wp: Array = path[0]
		var target: Vector2 = world.waypoint_pos(wp)
		var to := target - position
		var L := to.length()
		if L <= d:
			position = target; seg = wp[0]; s = wp[1] if wp[0] >= 0 else 0.0
			path.pop_front(); d -= L
		else:
			position += to / L * d
			face_dir = 1.0 if to.x >= 0 else -1.0
			d = 0.0
	if path.is_empty():
		if task == -2:
			state = State.REST; task = -1; seg = -1
		elif task >= 0 and world.seg_alive(task):
			var sg: Segment = world.segs[task]
			face_dir = 1.0 if sg.u.x >= 0 else -1.0
			if role == Role.MINER and not salvaging: state = State.DIG; work_t = 0.0
			else: state = State.WORK; work_t = 6.0 + randf() * 6.0
		else:
			state = State.IDLE; task = -1

func _dig(dt: float) -> void:
	if not world.seg_alive(task):
		leave_and_idle(); return
	var sg: Segment = world.segs[task]
	var H = world.hazards
	if not pocket.is_empty():
		if H.flooded(sg) or H.gas_out(sg) or sg.rubble.size() > 0 or world.mine_closed(sg): leave_and_idle(); return
		var stand: float = pocket.s + World.PK_W * 0.5
		position = position.lerp(sg.floor_pos(stand), minf(1.0, dt * 4.0)); seg = sg.id; s = stand
		work_t -= dt
		if work_t <= 0.0:
			work_t = 0.7 / skill
			if not world.brush(sg, pocket):
				sg.pockets.erase(pocket); leave_and_idle(); return
		energy -= dt * 0.9
		if energy < 10.0: _go_home()
		return
	if clearing:
		if sg.rubble.is_empty(): leave_and_idle(); return
		var stand: float = maxf(0.0, sg.rubble[0] - 4.0 - 7.0 * maxi(0, sg.crew.find(id)))
		position = position.lerp(sg.floor_pos(stand), minf(1.0, dt * 4.0)); seg = sg.id; s = stand
		sg.rubble[0] += dt * 0.9 * skill
		if sg.rubble[0] >= sg.rubble[1]:
			sg.rubble = []; sg.stress = 0.2; Game.toast.emit("The cave-in in mine No.%d is cleared." % world.mine_no(sg))
			leave_and_idle(); return
	else:
		if sg.done() or H.flooded(sg) or H.gas_out(sg) or sg.rubble.size() > 0:
			leave_and_idle(); return
		var back: float = 60.0 if (not sg.soft and sg.bp >= 1) else 0.0
		var stand := maxf(0.0, sg.prog - 5.0 - back - 7.0 * maxi(0, sg.crew.find(id)))
		position = position.lerp(sg.floor_pos(stand), minf(1.0, dt * (1.5 if back > 0.0 else 4.0))); seg = sg.id; s = stand
		var ahead: Vector2 = sg.pos(sg.prog + 2.0)
		var m: int = world.terrain.mat_world(ahead.x, ahead.y)
		var hard: float = Mats.HARD[m]
		if hard > 50.0:
			world.stop_segment(sg); return
		sg.soft = m == Mats.COAL or m == Mats.SOIL or m == Mats.SAND or m == Mats.CLAY or m == Mats.AIR
		if rig >= 0:
			# the continuous miner does the cutting; the driver only steers
			var r: Rig = world.rigs[rig]
			r.seg = sg.id; r.cutting = true; r.dir = face_dir; r.drum += dt * 12.0
			r.position = sg.floor_pos(maxf(0.0, sg.prog - 14.0)) + Vector2(0, 0)
			r.rotation = sg.u.angle() if face_dir > 0 else sg.u.angle() + PI
			position = r.position - sg.u * 6.0; seg = sg.id; s = sg.prog - 20.0
			if sg.soft or hard < 3.5:
				world.advance(sg, dt * 9.0 * skill / pow(maxf(1.0, hard), 0.6))
				Game.pay(-Rig.RUN_COST * dt)
				var fp: Vector2 = sg.pos(sg.prog - 2.0)
				for k in 2: world.fx.puff(fp + Vector2(randf_range(-4, 4), randf_range(-8, 8)), -sg.u * randf_range(6, 16) + Vector2(0, randf_range(-3, 3)), 0.4, 0.8, Color(0.8, 0.88, 0.96, 0.7), "spray")
			else:
				world.stop_segment(sg); Game.toast.emit("The continuous miner can't cut that rock. Crews with drills and powder take it from here."); return
		elif sg.soft:
			if sg.crew.find(id) == 0:
				world.advance(sg, dt * 2.2 * skill / pow(maxf(1.0, hard), 0.8))
		else:
			_blast_cycle(sg, dt, hard)
	energy -= dt * 0.9
	if energy < 10.0: _go_home()

## Rock: the crew drills a round of holes, loads them, backs off and fires. Each shot pulls about 10 ft.
func _blast_cycle(sg: Segment, dt: float, hard: float) -> void:
	match sg.bp:
		0:
			if sg.crew.find(id) == 0: sg.dh += dt * 0.08 * skill / pow(hard, 0.5)
			if randf() < dt * 3.0:
				var fp: Vector2 = sg.pos(sg.prog - 1.0)
				world.fx.puff(fp + Vector2(randf_range(-3, 3), randf_range(-6, 6)), -sg.u * randf_range(5, 12), 0.6, 1.0, Color(0.55, 0.52, 0.5, 0.7))
			if sg.dh >= 1.0: sg.dh = 1.0; sg.bp = 1; sg.bt = 0.0
		1:
			sg.bt += dt
			if sg.bt > 3.0: sg.bp = 2; sg.bt = 0.0
		2:
			sg.bt += dt
			if sg.bt > 2.5:
				world.shoot(sg); sg.bp = 3; sg.bt = 0.0
		3:
			sg.bt += dt
			if sg.bt > 4.0: sg.bp = 0; sg.dh = 0.0

func _work(dt: float) -> void:
	work_t -= dt
	if salvaging:
		_salvage(dt); return
	match role:
		Role.BOLTER:
			if not world.seg_alive(task): leave_and_idle(); return
			var sg: Segment = world.segs[task]
			if sg.rubble.size() > 0 or sg.sup >= sg.prog - 1.0: task = -1; state = State.IDLE; think = 0.0; return
			world.hazards.bolt(sg, dt, skill)
			var p: Vector2 = sg.floor_pos(minf(sg.prog, sg.sup + 3.0))
			position = position.lerp(p, minf(1.0, dt * 4.0)); seg = sg.id; s = sg.sup + 3.0
			energy -= dt * 0.7
		Role.SAFETY:
			energy -= dt * 0.3
			if work_t <= 0.0: task = -1; state = State.IDLE; think = 0.0
		Role.MANAGER:
			if work_t <= 0.0:
				work_t = 8.0
				world.auto_plan()
	if energy < 10.0: _go_home()

func _salvage(dt: float) -> void:
	if not world.seg_alive(task): leave_and_idle(); return
	var sg: Segment = world.segs[task]
	var root: Segment = world.mine_root(sg)
	var ds: float = minf(sg.belt, dt * 2.5 * skill)
	sg.belt -= ds; Game.pay(-0.6 * ds)
	position = position.lerp(sg.floor_pos(maxf(0.0, sg.belt - 2.0)), minf(1.0, dt * 4.0)); seg = sg.id; s = sg.belt
	if randf() < dt * 2.0: world.fx.puff(position + Vector2(0, -3.0), Vector2(randf_range(-8, 8), randf_range(-12, -4)), 0.5, 0.8, Color(0.5, 0.45, 0.4, 0.6))
	energy -= dt * 0.6
	if sg.belt <= 0.0:
		sg.belt = 0.0
		if world.salvage_target(root) == null:
			root.salvage = false
			Game.toast.emit("The conveyor is out of mine No.%d." % world.mine_no(root))
		leave_and_idle()
	elif energy < 10.0: _go_home()

func _draw() -> void:
	if rig >= 0 and state == State.DIG: return
	var f := face_dir
	var walking := state == State.WALK
	var digging := state == State.DIG or (state == State.WORK and role == Role.BOLTER)
	var q := anim * (9.0 if walking else 5.5)
	var bob := absf(sin(q)) * 0.5 if walking else 0.0
	var hip := Vector2(0, -9.0 - bob)
	var suit: Color = [Color("2a3f6b"), Color("4a3a2a"), Color("2f6b3a"), Color("4a4a55")][role]
	var suit2: Color = suit.lightened(0.12)
	draw_rect(Rect2(-1.6, hip.y, 3.2, 1.2), Color("1d1c20"))
	for i in 2:
		var a: float
		if walking: a = sin(q + i * PI) * 0.5
		elif digging: a = -0.35 if i == 0 else 0.4
		else: a = -0.07 if i == 0 else 0.09
		var knee := hip + Vector2(sin(a) * 4.5 * f, cos(a) * 4.5)
		var foot := knee + Vector2(sin(a * 0.5) * 4.5 * f, cos(a * 0.5) * 4.5)
		draw_line(hip, knee, suit, 2.4)
		draw_line(knee, foot, suit, 2.2)
		draw_rect(Rect2(foot.x - 1.6, foot.y - 0.8, 3.2, 1.4), Color("1a1a1e"))
	var lean := 0.18 if digging else 0.06
	var shoulder := hip + Vector2(sin(lean) * 8.0 * f, -8.0)
	draw_line(hip, shoulder, suit2, 4.2)
	draw_rect(Rect2(shoulder.x - 2.6, shoulder.y + 1.0, 5.2, 1.4), Color("f2b705"))
	var swing := sin(q) * 0.45 if walking else 0.0
	var t := pow((sin(q) + 1.0) * 0.5, 1.4) if digging else 0.0
	var up := 1.15 + 1.75 * t
	if digging and not pocket.is_empty() and pocket.side < 0: up = 2.6 + 0.5 * t
	if role == Role.BOLTER and digging: up = 2.6 + sin(anim * 40.0) * 0.05
	var arm_a := up if digging else (0.3 + swing)
	var hand := shoulder + Vector2(sin(arm_a) * 6.5 * f, cos(arm_a) * 6.5)
	draw_line(shoulder, hand, suit2, 2.2)
	if digging or walking:
		if role == Role.BOLTER:
			draw_line(hand, hand + Vector2(0, -14.0 if digging else -6.0), Color("8a8f96"), 2.0)
		elif role == Role.MINER:
			var ta := (up + 0.45) if digging else 2.45
			var tip := hand + Vector2(sin(ta) * 9.0 * f, cos(ta) * 9.0)
			draw_line(hand, tip, Color("8a6a3a"), 1.4)
			draw_line(tip + Vector2(-2.5 * f, -1.5), tip + Vector2(2.5 * f, 1.5), Color("66686e"), 2.0)
		elif role == Role.SAFETY:
			draw_rect(Rect2(hand.x - 1.5, hand.y - 1.0, 3.0, 2.0), Color("f2b705"))
	var head := shoulder + Vector2(sin(lean) * 3.0 * f, -4.5)
	draw_circle(head, 2.6, Color("d9a977"))
	draw_rect(Rect2(head.x - 3.0, head.y - 3.6, 6.0, 2.2), [Color("f2b705"), Color("f2b705"), Color("e8e8e8"), Color("f1efe6")][role])
	draw_circle(head + Vector2(2.2 * f, -2.3), 0.9, Color("fff2b0"))
	if seg >= 0:
		var beam := PackedVector2Array([head + Vector2(2.5 * f, -2.3), head + Vector2(26.0 * f, -9.0), head + Vector2(28.0 * f, 6.0)])
		draw_colored_polygon(beam, Color(1.0, 0.95, 0.7, 0.10))
