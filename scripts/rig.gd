## A continuous miner: a tracked machine with a rotating cutter drum. A miner drives it to the face and it cuts
## six times faster than picks, with water sprays on the drum to hold the dust down.
class_name Rig
extends Node2D

const COST := 3500.0
const RUN_COST := 1.2             # dollars a second while cutting

var id := -1
var op := -1                      # worker id driving it, -1 parked
var seg := -1
var cutting := false
var dir := 1.0
var drum := 0.0

func _ready() -> void:
	z_index = 4

func _draw() -> void:
	var f := dir
	# tracks
	draw_rect(Rect2(-14.0, -5.0, 28.0, 5.0), Color("2b2a2e"))
	for k in 5: draw_circle(Vector2(-11.0 + k * 5.5, -2.5), 1.6, Color("4a4f55"))
	# body in company yellow, cab, cable
	draw_rect(Rect2(-13.0, -11.0, 24.0, 6.5), Color("e0a51c"))
	draw_rect(Rect2(-13.0, -11.0, 24.0, 1.2), Color("1d1c20"))
	draw_rect(Rect2(-12.0 * f - (0.0 if f > 0 else 4.0), -14.0, 4.0, 3.0), Color("2a2a30"))
	draw_line(Vector2(-14.0 * f, -8.0), Vector2(-30.0 * f, -4.0), Color("1a1a1e"), 1.2)
	# boom and cutter drum
	var boom := Vector2(11.0 * f, -9.0)
	var head := boom + Vector2(10.0 * f, 2.0)
	draw_line(boom, head, Color("b8871a"), 4.0)
	draw_circle(head, 5.0, Color("3a3a40"))
	for k in 8:
		var a := drum + k * TAU / 8.0
		draw_circle(head + Vector2(cos(a), sin(a)) * 4.6, 0.9, Color("8d9198") if cutting else Color("5a5d63"))
	# conveyor tail at the back
	draw_rect(Rect2(-24.0 * f - (0.0 if f > 0 else 10.0), -7.0, 10.0, 2.0), Color("4a4f55"))
	if cutting:
		draw_circle(Vector2(-12.0 * f, -13.0), 1.3, Color("ffb020") if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else Color("5a4a20"))
