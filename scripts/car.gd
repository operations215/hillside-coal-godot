## A shuttle car: a low electric car that hauls cut material from a bare face back to the nearest conveyor.
class_name Car
extends Node2D

const COST := 1200.0
const CAP := 40                   # cells a load
const SPEED := 55.0
const SCOOP_COST := 800.0

var kind := "car"                # car or scoop

var id := -1
var seg := -1                     # tunnel it is in
var s := 0.0
var state := "idle"               # idle, in, load, out, dump
var task := -1                    # bare segment being served
var cargo: Array = []             # items aboard
var t := 0.0
var hauled := 0                   # cells delivered to a belt, lifetime
var dir := 1.0
var world: Node

func tick(dt: float) -> void:
	match state:
		"idle":
			t -= dt
			if t > 0.0: return
			t = 1.0
			# a bare tunnel with muck waiting at its face
			var best := -1; var bn := 0
			for sg in world.segs:
				if sg.dead or sg.has_belt or sg.rubble.size() > 0 or world.mine_closed(sg): continue
				if world.cars.any(func(c): return c != self and c.task == sg.id): continue
				var n := 0
				for it in world.items:
					if it[0] == sg.id and it[4]: n += 1
				if n > bn: bn = n; best = sg.id
			if best >= 0 and bn >= (3 if kind == "scoop" else 6):
				task = best; seg = best; s = 0.0; state = "in"
		"in":
			var sg: Segment = world.segs[task]
			s = minf(sg.prog - 16.0, s + SPEED * (1.4 if kind == "scoop" else 1.0) * dt); dir = 1.0
			position = sg.floor_pos(s) - sg.n * 1.0; rotation = sg.u.angle()
			if s >= sg.prog - 16.0: state = "load"; t = 0.0
		"load":
			var sg: Segment = world.segs[task]
			t += dt
			if t > 0.25:
				t = 0.0
				var took := 0
				var keep := []
				for it in world.items:
					if it[0] == task and it[4] and took < 4 and cargo.size() < (CAP / 3 if kind == "scoop" else CAP):
						cargo.append(it); took += 1
					else: keep.append(it)
				world.items = keep
				if took == 0 or cargo.size() >= (CAP / 3 if kind == "scoop" else CAP): state = "out"
		"out":
			var sg: Segment = world.segs[task]
			s = maxf(0.0, s - SPEED * (1.4 if kind == "scoop" else 1.0) * dt); dir = -1.0
			position = sg.floor_pos(s) - sg.n * 1.0; rotation = sg.u.angle()
			if s <= 0.0: state = "dump"; t = 0.0
		"dump":
			var sg: Segment = world.segs[task]
			t += dt
			if t > 1.2:
				for it in cargo:
					it[4] = false
					if sg.parent >= 0: it[0] = sg.parent; it[1] = sg.pt
					else: it[0] = -1; it[1] = absf(sg.a.x - world.HEAD_X)
					world.items.append(it)
				hauled += cargo.size()
				cargo = []; state = "idle"; t = 0.5
	queue_redraw()

func _draw() -> void:
	if kind == "scoop":
		draw_rect(Rect2(-9.0, -6.0, 18.0, 5.0), Color("d9a21a"))
		draw_rect(Rect2(-9.0, -6.0, 18.0, 1.0), Color("1d1c20"))
		draw_rect(Rect2(-6.0 * dir - 2.0, -9.5, 4.0, 3.5), Color("2a2a30"))
		for wx in [-5.0, 5.0]: draw_circle(Vector2(wx, -1.0), 2.4, Color("1a1a1e"))
		var bx := 9.0 * dir
		draw_line(Vector2(bx, -5.0), Vector2(bx + 5.0 * dir, -2.0), Color("8a8f96"), 1.5)
		draw_rect(Rect2(bx + (2.0 if dir > 0 else -8.0), -3.0, 6.0, 3.0), Color("6a6f76"))
		if cargo.size() > 0: draw_rect(Rect2(bx + (2.0 if dir > 0 else -8.0), -5.0, 6.0, 2.0), Color("1d1c20"))
		return
	draw_rect(Rect2(-16.0, -6.0, 32.0, 5.5), Color("e0a51c"))
	draw_rect(Rect2(-16.0, -6.0, 32.0, 1.0), Color("1d1c20"))
	draw_rect(Rect2(14.0 * dir - (0.0 if dir > 0 else 5.0), -9.5, 5.0, 3.5), Color("2a2a30"))
	for wx in [-11.0, -4.0, 4.0, 11.0]: draw_circle(Vector2(wx, -1.0), 2.0, Color("1a1a1e"))
	if cargo.size() > 0:
		var h := 1.0 + 4.0 * cargo.size() / float(CAP)
		draw_rect(Rect2(-14.0, -6.0 - h, 28.0, h), Color("1d1c20"))
	draw_circle(Vector2(-14.0 * dir, -8.0), 1.1, Color("ffb020") if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else Color("5a4a20"))
