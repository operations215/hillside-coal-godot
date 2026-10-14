## The header: cash, pile, price, shift clock, speed, and the hire button.
extends CanvasLayer

@onready var cash: Label = $Top/Cash
@onready var pile: Label = $Top/Pile
@onready var price: Label = $Top/Price
@onready var day: Label = $Top/Day
@onready var crew: Label = $Top/Crew
@onready var toasts: VBoxContainer = $Toasts

func _process(_dt: float) -> void:
	var world: Node2D = get_parent()
	cash.text = "CASH  " + Game.money_text(Game.money)
	pile.text = "STOCKPILE  %d t" % int(Game.pile)
	price.text = "COAL  $%d/t" % int(Game.price)
	var f := fmod(Game.time, Game.DAY_LEN) / Game.DAY_LEN
	day.text = "DAY %d  %s%s" % [Game.day, ("PAUSED" if Game.paused else "%d×" % int(Game.speed)), ("  " + "▮".repeat(int(f * 10)) + "▯".repeat(10 - int(f * 10)))]
	crew.text = "CREW  %d miners" % world.workers.size()

func _on_hire() -> void:
	var world: Node2D = get_parent()
	if Game.spend(45.0):
		var w: Worker = world.hire()
		show_toast("%s joins the crew at $%d a shift." % [w.worker_name, int(w.wage)])

func _on_speed(k: int) -> void:
	if k == 0: Game.paused = not Game.paused
	else: Game.paused = false; Game.speed = float(k)

func show_toast(text: String) -> void:
	var l := Label.new()
	l.text = text; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.custom_minimum_size.x = 420
	l.add_theme_color_override("font_color", Color("f1efe6"))
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.08, 0.07, 0.05, 0.92); sb.border_color = Color("f2b705"); sb.set_border_width_all(1); sb.border_width_left = 4
	sb.set_content_margin_all(8)
	var pnl := PanelContainer.new(); pnl.add_theme_stylebox_override("panel", sb); pnl.add_child(l)
	toasts.add_child(pnl)
	while toasts.get_child_count() > 4: toasts.get_child(0).free()
	get_tree().create_timer(7.0).timeout.connect(func():
		if is_instance_valid(pnl): pnl.queue_free())
