extends Camera2D

func _ready() -> void:
	position = Vector2(1500, -120)
	zoom = Vector2(0.9, 0.9)

func zoom_at(p: Vector2, k: float) -> void:
	var z := clampf(zoom.x * k, 0.3, 6.0)
	var before := get_global_mouse_position()
	zoom = Vector2(z, z)
	var after := get_global_mouse_position()
	position += before - after
