## The hill: a grid of 4 ft cells with a material in each, rendered as one texture per 256 px chunk.
## x runs along the valley in feet, y is depth (down is positive, the valley floor is y = 0).
class_name Terrain
extends Node2D

const C := 4                      # cell size in feet / pixels
const CH := 256                   # chunk size in pixels
const WX0 := -200
const WX1 := 4400
const WY0 := -700
const WY1 := 700
const HILL := 1560.0              # the hill starts rising here; everything to the left is the flat yard

var GW: int = (WX1 - WX0) / C
var GH: int = (WY1 - WY0) / C
var gmat := PackedByteArray()
var gdug := PackedByteArray()
var _chunks := {}                 # Vector2i -> Sprite2D
var _dirty := {}                  # Vector2i -> true
var _noise := FastNoiseLite.new()
var _seam_noise := FastNoiseLite.new()

func _ready() -> void:
	_noise.seed = 7; _noise.frequency = 0.012
	_seam_noise.seed = 19; _seam_noise.frequency = 0.004
	gmat.resize(GW * GH); gdug.resize(GW * GH)
	for gx in GW:
		var x := WX0 + gx * C + C * 0.5
		for gy in GH:
			gmat[gy * GW + gx] = material_at(x, WY0 + gy * C + C * 0.5)
	for cy in range(WY0 / CH - 1, WY1 / CH + 1):
		for cx in range(WX0 / CH - 1, WX1 / CH + 1):
			_build_chunk(Vector2i(cx, cy))

## Surface height at x: flat yard, then a hill climbing to the right with a couple of shoulders.
static func ground_y(x: float) -> float:
	if x < HILL: return 0.0
	var t := x - HILL
	var y := -t * 0.42 + sin(t * 0.004) * 40.0 + sin(t * 0.011 + 1.0) * 14.0
	return maxf(y, -560.0)

## What lies at a point in the hill. Layers follow the surface, with coal seams and ore pods deeper down.
func material_at(x: float, y: float) -> int:
	var g := ground_y(x)
	if y < g: return Mats.AIR
	var d := y - g                               # depth below the surface
	if y > WY1 - 60: return Mats.BED
	if d < 10: return Mats.SOIL
	var n := _noise.get_noise_2d(x, y)
	# the main seam follows the hill 60 to 110 ft under the surface, 14 to 30 ft thick; a thinner one lies deeper
	var seam_d := 85.0 + _seam_noise.get_noise_1d(x) * 25.0
	var th := 22.0 + _seam_noise.get_noise_1d(x + 900.0) * 8.0
	if absf(d - seam_d) < th * 0.5: return Mats.COAL
	var seam2 := seam_d + 150.0 + _seam_noise.get_noise_1d(x + 3000.0) * 40.0
	if absf(d - seam2) < 7.0 + 4.0 * n: return Mats.COAL
	if d < 40 + 20.0 * n: return Mats.SAND if n > 0.2 else Mats.CLAY
	# ore pods
	var o := _noise.get_noise_2d(x * 0.7 + 5000.0, y * 0.7)
	if o > 0.62 and y > 120: return Mats.GOLD if o > 0.78 else Mats.COPPER
	if o < -0.6 and y > 60: return Mats.IRON
	if y > 420 + 40.0 * n: return Mats.GRAN
	if n > 0.3: return Mats.LIME
	return Mats.SHALE

func cell_at(x: float, y: float) -> int:
	var gx := int(floor((x - WX0) / C)); var gy := int(floor((y - WY0) / C))
	if gx < 0 or gy < 0 or gx >= GW or gy >= GH: return -1
	return gy * GW + gx

func mat_world(x: float, y: float) -> int:
	var i := cell_at(x, y)
	return Mats.AIR if i < 0 else gmat[i]

func is_dug(x: float, y: float) -> bool:
	var i := cell_at(x, y)
	return i >= 0 and gdug[i] == 1

## Dig every cell within a box around a point (half width hw along the tunnel direction u, half height hh across it).
## Returns the materials of the cells that came out, with their world positions.
func carve(px: float, py: float, u: Vector2, hw: float, hh: float) -> Array:
	var out := []
	var n := Vector2(-u.y, u.x)
	var e := maxf(hw, hh) * 1.42
	var gx0 := maxi(0, int((px - e - WX0) / C)); var gx1 := mini(GW - 1, int((px + e - WX0) / C))
	var gy0 := maxi(0, int((py - e - WY0) / C)); var gy1 := mini(GH - 1, int((py + e - WY0) / C))
	for gy in range(gy0, gy1 + 1):
		for gx in range(gx0, gx1 + 1):
			var cx := WX0 + gx * C + C * 0.5 - px
			var cy := WY0 + gy * C + C * 0.5 - py
			if absf(cx * u.x + cy * u.y) > hw or absf(cx * n.x + cy * n.y) > hh: continue
			var i := gy * GW + gx
			if gdug[i] == 1: continue
			var m := gmat[i]
			if m == Mats.BED: continue
			gdug[i] = 1
			_mark_dirty(gx, gy)
			if m != Mats.AIR: out.append([m, WX0 + gx * C + C * 0.5, WY0 + gy * C + C * 0.5])
	return out

func _mark_dirty(gx: int, gy: int) -> void:
	var x := WX0 + gx * C; var y := WY0 + gy * C
	_dirty[Vector2i(int(floor(float(x) / CH)), int(floor(float(y) / CH)))] = true

func _process(_dt: float) -> void:
	# rebuild a few dirty chunks a frame so a long dig never stalls the game
	var budget := 3
	for key in _dirty.keys():
		if budget <= 0: break
		_build_chunk(key); _dirty.erase(key); budget -= 1

func _build_chunk(key: Vector2i) -> void:
	var img := Image.create(CH, CH, false, Image.FORMAT_RGBA8)
	var x0 := key.x * CH; var y0 := key.y * CH
	var any := false
	for gy in range(CH / C):
		var y := y0 + gy * C
		var row := int(floor((y - WY0) / float(C)))
		if row < 0 or row >= GH: continue
		for gx in range(CH / C):
			var x := x0 + gx * C
			var col := int(floor((x - WX0) / float(C)))
			if col < 0 or col >= GW: continue
			var i := row * GW + col
			var m := gmat[i]
			if m == Mats.AIR: continue
			any = true
			var c: Color
			if gdug[i] == 1:
				c = Color(0.06, 0.05, 0.05)
			else:
				c = Mats.COLORS[m]
				# a little grain so the rock reads as rock, darker with depth
				var h := fposmod(sin(float(x) * 12.9898 + float(y) * 78.233) * 43758.5453, 1.0)
				c = c.darkened(0.08 * h + clampf((y - ground_y(x + 2)) / 1400.0, 0.0, 0.25))
				if m == Mats.COAL and h > 0.85: c = c.lightened(0.35)
			img.fill_rect(Rect2i(gx * C, gy * C, C, C), c)
	var spr: Sprite2D = _chunks.get(key)
	if not any:
		if spr: spr.queue_free(); _chunks.erase(key)
		return
	if spr == null:
		spr = Sprite2D.new(); spr.centered = false; spr.position = Vector2(x0, y0); spr.z_index = -10
		add_child(spr); _chunks[key] = spr
	spr.texture = ImageTexture.create_from_image(img)

func _draw() -> void:
	# the sky-side slope line and the valley floor, as a thin edge of grass
	var pts := PackedVector2Array()
	var x := float(WX0)
	while x <= WX1:
		pts.append(Vector2(x, ground_y(x) - 1.0)); x += 8.0
	draw_polyline(pts, Color("5f8f3e"), 3.0)
