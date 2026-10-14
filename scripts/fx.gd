## Cheap particles drawn by the world: dust, smoke, water spray and flying chips.
class_name FX
extends RefCounted

var puffs: Array = []             # [pos, vel, life, max_life, size, color, kind]

func puff(p: Vector2, v: Vector2, life: float, size: float, col: Color, kind := "dust") -> void:
	if puffs.size() > 1500: return
	puffs.append([p, v, life, life, size, col, kind])

func tick(dt: float) -> void:
	var keep := []
	for q in puffs:
		q[2] -= dt
		if q[2] <= 0.0: continue
		if q[6] == "bit": q[1].y += 520.0 * dt
		elif q[6] == "smoke": q[4] += dt * 7.0; q[1].y -= 6.0 * dt
		elif q[6] == "dust": q[1] *= 1.0 - dt * 1.5; q[4] += dt * 3.0
		elif q[6] == "spray": q[1].y += 60.0 * dt
		q[0] += q[1] * dt
		keep.append(q)
	puffs = keep

func draw(c: CanvasItem) -> void:
	for q in puffs:
		var a: float = q[2] / q[3]
		var col: Color = q[5]; col.a *= (a if q[6] != "bit" else 1.0) * 0.8
		if q[6] == "bit": c.draw_rect(Rect2(q[0].x - 1.0, q[0].y - 1.0, 2.0, 2.0), col)
		else: c.draw_circle(q[0], q[4], col)
