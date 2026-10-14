## Night: a dark wash over the world after the shift ends, with warm pools of light at the lamps,
## the portals, the yard and every headlamp underground. Drawn above the world and below the HUD.
class_name Night
extends Node2D

var world: Node
var glow: Node2D

func _ready() -> void:
	z_index = 15
	glow = Node2D.new()
	var m := CanvasItemMaterial.new(); m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = m
	glow.draw.connect(_draw_glow)
	add_child(glow)

func _process(_dt: float) -> void:
	queue_redraw(); glow.queue_redraw()

func _draw() -> void:
	var nf: float = Game.night_f()
	if nf <= 0.01: return
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null: return
	var vs := get_viewport_rect().size / cam.zoom.x
	draw_rect(Rect2(cam.position - vs * 0.5 - Vector2(40, 40), vs + Vector2(80, 80)), Color(0.02, 0.03, 0.09, 0.62 * nf))

func _pool(p: Vector2, r: float, a: float, col := Color(1.0, 0.82, 0.5)) -> void:
	glow.draw_circle(p, r, Color(col.r, col.g, col.b, a * 0.35))
	glow.draw_circle(p, r * 0.55, Color(col.r, col.g, col.b, a * 0.5))
	glow.draw_circle(p, r * 0.2, Color(col.r, col.g, col.b, a * 0.8))

func _draw_glow() -> void:
	var nf: float = Game.night_f()
	if nf <= 0.01: return
	# yard lights: office, quarters, the head of the conveyor
	for x in [1180.0, 1300.0, world.HEAD_X]:
		_pool(Vector2(x, -30.0), 45.0, nf * 0.4)
	for sg in world.segs:
		if sg.dead or sg.prog < 0.5: continue
		var root: Segment = world.segs[sg.root_of(world.segs)]
		if root.decom: continue
		if sg.parent < 0: _pool(sg.a + Vector2(0, -14.0), 40.0, nf * 0.7)
		var l := 35.0
		while l < sg.prog:
			_pool(sg.pos(l) - sg.n * (Segment.R - 2.5), 22.0, nf * 0.6, Color(1.0, 0.95, 0.75))
			l += 70.0
	for w in world.workers:
		if w.seg >= 0:
			_pool(w.position + Vector2(10.0 * w.face_dir, -22.0), 14.0, nf * 0.45, Color(1.0, 0.97, 0.85))
	for r in world.rigs:
		if r.cutting: _pool(r.position, 30.0, nf * 0.6)
