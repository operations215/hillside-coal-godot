## The sky, far ridges and the trees on the hill: drawn behind everything, with a little parallax on the ridges.
class_name Backdrop
extends Node2D

var trees: Array = []             # [x, kind, size]

func _ready() -> void:
	z_index = -20
	var x := Terrain.HILL + 40.0
	while x < Terrain.WX1 - 100:
		var h := fposmod(sin(x * 12.9898) * 43758.5453, 1.0)
		if h < 0.55: trees.append([x, 0 if h < 0.3 else 1, 0.7 + h])
		x += 26.0
	for k in 6: trees.append([200.0 + k * 170.0 + fposmod(k * 37.1, 40.0), 1, 1.1])

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null: return
	var z := cam.zoom.x
	var vs := get_viewport_rect().size / z
	var top := cam.position - vs * 0.5
	# sky, by day and by night
	var nf: float = Game.night_f()
	var c_top := Color("5b7fa8").lerp(Color("070b1c"), nf); var c_hor := Color("c9b6a0").lerp(Color("2a2742"), nf)
	draw_rect(Rect2(top, vs), c_top)
	var gy := 0.0
	for i in 40:
		var y0 := gy - 640.0 + i * 16.0
		draw_rect(Rect2(top.x, y0, vs.x, 16.5), c_top.lerp(c_hor, pow(i / 39.0, 1.6)))
	if nf > 0.15:
		for k in 90:
			var sx := top.x + fposmod(k * 977.3 + cam.position.x * 0.02, vs.x); var sy := top.y + fposmod(k * 613.7, vs.y * 0.6)
			if sy > gy - 60.0: continue
			var tw := 0.5 + 0.5 * sin(Game.time * 2.0 + k)
			draw_circle(Vector2(sx, sy), (0.6 + fposmod(k * 0.37, 0.9)) / z, Color(1.0, 1.0, 0.95, (nf - 0.15) * tw * 0.9))
		var mx := top.x + vs.x * 0.78; var my := gy - 520.0
		draw_circle(Vector2(mx, my), 14.0, Color(0.95, 0.95, 0.85, (nf - 0.15) * 0.9))
		draw_circle(Vector2(mx - 5.0, my - 3.0), 12.0, c_top.lerp(Color(0.95, 0.95, 0.85), 0.1 * (1.0 - nf)))
	# far ridges with a parallax slide, dark pines along them
	for layer in [[0.06, Color("8a7480"), 60.0, 300.0], [0.14, Color("6c5d6b"), 45.0, 220.0], [0.26, Color("4f4652"), 35.0, 150.0]]:
		var f: float = layer[0]; var col: Color = layer[1].darkened(0.65 * nf); var amp: float = layer[2]; var base: float = layer[3]
		var pts := PackedVector2Array()
		pts.append(Vector2(top.x - 50, 400))
		var x := top.x - 50.0
		while x < top.x + vs.x + 50.0:
			var wx := x + cam.position.x * f
			pts.append(Vector2(x, gy - base + sin(wx * 0.005 + base) * amp * 0.6 + sin(wx * 0.013) * amp * 0.35))
			x += 16.0
		pts.append(Vector2(top.x + vs.x + 50, 400))
		draw_colored_polygon(pts, col)
	# trees on the hill
	for t in trees:
		var x: float = t[0]
		if x < top.x - 40 or x > top.x + vs.x + 40: continue
		var y := Terrain.ground_y(x) + 1.0
		var s: float = t[2]
		if t[1] == 0:
			draw_rect(Rect2(x - 1.2 * s, y - 14.0 * s, 2.4 * s, 14.0 * s), Color("5a4028"))
			for k in 3:
				var w := (14.0 - k * 3.5) * s; var yy := y - (10.0 + k * 7.0) * s
				draw_colored_polygon(PackedVector2Array([Vector2(x - w, yy), Vector2(x, yy - 12.0 * s), Vector2(x + w, yy)]), Color("3f6b3a") if k % 2 == 0 else Color("4a7a42"))
		else:
			draw_rect(Rect2(x - 1.5 * s, y - 16.0 * s, 3.0 * s, 16.0 * s), Color("5a4028"))
			draw_circle(Vector2(x, y - 22.0 * s), 10.0 * s, Color("5f8f3e"))
			draw_circle(Vector2(x - 6.0 * s, y - 18.0 * s), 7.0 * s, Color("6a9a46"))
			draw_circle(Vector2(x + 6.0 * s, y - 19.0 * s), 7.5 * s, Color("557f38"))
