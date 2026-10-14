## One straight tunnel: it starts at a point on the surface or on a parent tunnel and is driven toward its end.
class_name Segment
extends RefCounted

const R := 11.0                   # half height of a tunnel in feet

var id := -1
var a := Vector2.ZERO             # start
var b := Vector2.ZERO             # planned end
var u := Vector2.RIGHT            # unit direction
var n := Vector2.DOWN             # unit normal (points at the floor side)
var length := 0.0
var prog := 0.0                   # feet driven so far
var carved := 0.0                 # feet whose cells have been dug out of the grid
var parent := -1                  # parent segment id, or -1 for a portal
var pt := 0.0                     # position along the parent where this one branches
var crew: Array[int] = []         # worker ids at the face
var dead := false
var belt := 0.0                   # feet of conveyor laid from the start
var coal_cells := 0

func setup(p_a: Vector2, p_b: Vector2, p_parent: int, p_pt: float) -> void:
	a = p_a; b = p_b; parent = p_parent; pt = p_pt
	length = a.distance_to(b)
	u = (b - a) / maxf(length, 0.001)
	n = Vector2(-u.y, u.x)
	if n.y < 0.0: n = -n

func pos(s: float) -> Vector2:
	return a + u * clampf(s, 0.0, length)

func floor_pos(s: float) -> Vector2:
	return pos(s) + n * (R - 1.5)

func done() -> bool:
	return prog >= length - 0.01

func root_of(segs: Array) -> int:
	var cur := self
	while cur.parent >= 0:
		cur = segs[cur.parent]
	return cur.id
