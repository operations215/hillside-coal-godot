## A miner: walks from the crew quarters to a face, digs, and goes home to rest when worn out.
class_name Worker
extends Node2D

enum State { IDLE, WALK, DIG, REST }

const WALK_SPEED := 42.0
const BUNK_X := 1300.0
const NAMES_FIRST := ["Earl", "Dewey", "Lonnie", "Roy", "Clyde", "Vernon", "Ray", "Otis", "Wade", "Hollis", "June", "Darlene", "Opal", "Wanda"]
const NAMES_LAST := ["Hatfield", "Caudill", "Mullins", "Slone", "Combs", "Blankenship", "Adkins", "Vance", "Tackett", "Justice"]

var id := -1
var worker_name := ""
var skill := 1.0
var wage := 40.0                  # dollars a shift
var energy := 100.0
var state := State.IDLE
var seg := -1                     # tunnel the worker stands in, -1 on the surface
var s := 0.0                      # feet along that tunnel
var face_dir := 1.0
var task := -1                    # segment being dug
var path: Array = []              # waypoints [seg, s] or [-1, x]
var think := 0.0
var anim := 0.0
var world: Node = null

func _ready() -> void:
	worker_name = NAMES_FIRST[randi() % NAMES_FIRST.size()] + " " + NAMES_LAST[randi() % NAMES_LAST.size()]
	position = Vector2(BUNK_X + randf_range(-20, 20), 0)
	z_index = 5

func tick(dt: float) -> void:
	anim += dt
	match state:
		State.REST:
			energy = minf(100.0, energy + dt * 6.0)
			if energy >= 100.0: state = State.IDLE
		State.WALK:
			_walk(dt)
		State.DIG:
			_dig(dt)
		State.IDLE:
			think -= dt
			if think > 0: return
			think = 0.5
			if energy < 15.0:
				_go_home(); return
			var best: Segment = world.pick_face(self)
			if best:
				best.crew.append(id); task = best.id
				path = world.build_path(self, best.id, maxf(0.0, best.prog - 6.0 - 7.0 * (best.crew.size() - 1)))
				state = State.WALK
	queue_redraw()

func _go_home() -> void:
	world.leave_face(self)
	path = world.build_path(self, -1, BUNK_X + randf_range(-16, 16))
	state = State.WALK
	task = -2                     # heading home

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
			state = State.DIG
			var sg: Segment = world.segs[task]
			face_dir = 1.0 if sg.u.x >= 0 else -1.0
		else:
			state = State.IDLE; task = -1

func _dig(dt: float) -> void:
	if not world.seg_alive(task) or world.segs[task].done():
		world.leave_face(self); state = State.IDLE; think = 0.0; return
	var sg: Segment = world.segs[task]
	# stand just behind the face, on the floor
	var stand := maxf(0.0, sg.prog - 5.0 - 7.0 * maxi(0, sg.crew.find(id)))
	var p: Vector2 = sg.floor_pos(stand)
	position = position.lerp(p, minf(1.0, dt * 4.0)); seg = sg.id; s = stand
	var hard: float = Mats.HARD[world.terrain.mat_world(sg.pos(sg.prog + 2.0).x, sg.pos(sg.prog + 2.0).y)]
	if hard > 50.0:
		world.stop_segment(sg); return
	if sg.crew.find(id) == 0:
		world.advance(sg, dt * 2.2 * skill / pow(maxf(1.0, hard), 0.8))
	energy -= dt * 0.9
	if energy < 10.0:
		_go_home()

func _draw() -> void:
	# a stick miner in the company blue, with a cap lamp. Legs and arms swing with the work.
	var f := face_dir
	var walking := state == State.WALK
	var digging := state == State.DIG
	var q := anim * (9.0 if walking else 5.5)
	var bob := absf(sin(q)) * 0.5 if walking else 0.0
	var hip := Vector2(0, -9.0 - bob)
	draw_rect(Rect2(-1.6, hip.y, 3.2, 1.2), Color("1d1c20"))
	# legs
	for i in 2:
		var a := sin(q + i * PI) * (0.5 if walking else 0.08) if (walking or not digging) else (-0.35 if i == 0 else 0.4)
		var knee := hip + Vector2(sin(a) * 4.5 * f, cos(a) * 4.5)
		var foot := knee + Vector2(sin(a * 0.5) * 4.5 * f, cos(a * 0.5) * 4.5)
		draw_line(hip, knee, Color("2a3f6b"), 2.4)
		draw_line(knee, foot, Color("2a3f6b"), 2.2)
		draw_rect(Rect2(foot.x - 1.6, foot.y - 0.8, 3.2, 1.4), Color("1a1a1e"))
	# torso
	var lean := 0.18 if digging else 0.06
	var shoulder := hip + Vector2(sin(lean) * 8.0 * f, -8.0)
	draw_line(hip, shoulder, Color("2d4a7a"), 4.2)
	draw_rect(Rect2(shoulder.x - 2.6, shoulder.y + 1.0, 5.2, 1.4), Color("f2b705"))   # reflective stripe
	# arms and the pick
	var swing := sin(q) * 0.45 if walking else 0.0
	var t := pow((sin(q) + 1.0) * 0.5, 1.4) if digging else 0.0
	var up := 1.15 + 1.75 * t
	var arm_a := up if digging else (0.3 + swing)
	var hand := shoulder + Vector2(sin(arm_a) * 6.5 * f, cos(arm_a) * 6.5)
	draw_line(shoulder, hand, Color("2d4a7a"), 2.2)
	if digging or walking:
		var ta := (up + 0.45) if digging else 2.45
		var tip := hand + Vector2(sin(ta) * 9.0 * f, cos(ta) * 9.0)
		draw_line(hand, tip, Color("8a6a3a"), 1.4)
		draw_line(tip + Vector2(-2.5 * f, -1.5), tip + Vector2(2.5 * f, 1.5), Color("66686e"), 2.0)
	# head and hard hat with the lamp
	var head := shoulder + Vector2(sin(lean) * 3.0 * f, -4.5)
	draw_circle(head, 2.6, Color("d9a977"))
	draw_rect(Rect2(head.x - 3.0, head.y - 3.6, 6.0, 2.2), Color("f2b705"))
	draw_circle(head + Vector2(2.2 * f, -2.3), 0.9, Color("fff2b0"))
	if seg >= 0 or digging:
		var beam := PackedVector2Array([head + Vector2(2.5 * f, -2.3), head + Vector2(26.0 * f, -9.0), head + Vector2(28.0 * f, 6.0)])
		draw_colored_polygon(beam, Color(1.0, 0.95, 0.7, 0.10))
