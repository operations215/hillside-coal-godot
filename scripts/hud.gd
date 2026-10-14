## The header: cash, pile, price, shift clock, speed, and the hire button.
extends CanvasLayer

@onready var cash: Label = $Top/Cash
@onready var pile: Label = $Top/Pile
@onready var price: Label = $Top/Price
@onready var day: Label = $Top/Day
@onready var crew: Label = $Top/Crew
@onready var toasts: VBoxContainer = $Toasts

func _process(dt: float) -> void:
	var world: World = get_parent()
	_info_t -= dt
	if _info_t <= 0.0: _info_t = 1.0; _refresh_info()
	cash.text = "CASH  " + Game.money_text(Game.money)
	pile.text = "STOCKPILE  %d t" % int(Game.pile)
	price.text = "COAL  $%d/t" % int(Game.price)
	var f := fmod(Game.time, Game.DAY_LEN) / Game.DAY_LEN
	day.text = "DAY %d  %s%s" % [Game.day, ("PAUSED" if Game.paused else "%d×" % int(Game.speed)), ("  " + "▮".repeat(int(f * 10)) + "▯".repeat(10 - int(f * 10)))]
	crew.text = "CREW  %d" % world.workers.size()

func _on_hire(role: int = 0) -> void:
	var world: World = get_parent()
	var cost: float = Worker.ROLE_WAGE[role]
	if Game.spend(cost):
		var w: Worker = world.hire(role)
		show_toast("%s joins the crew as a %s at $%d a shift." % [w.worker_name, Worker.ROLE_NAME[role], int(w.wage)])

func _on_scoop() -> void:
	get_parent().buy_scoop()

func _on_hand() -> void:
	var world: World = get_parent()
	world.hand_mode = not world.hand_mode
	$Panel/Box/Hand.text = "Hand mining: drag along a tunnel" if world.hand_mode else "Hand mining orders"
	if world.hand_mode: show_toast("Drag along a tunnel to mark its ribs for hand mining. Free miners dig out the coal the machine missed.")

func _on_car() -> void:
	get_parent().buy_car()

func _on_belt() -> void:
	var world: World = get_parent()
	world.plan_belt = not world.plan_belt
	$Panel/Box/Belt.text = "New tunnels: conveyor" if world.plan_belt else "New tunnels: bare (shuttle cars)"

func _on_rig() -> void:
	get_parent().buy_rig()

func _on_buy(key: String) -> void:
	Game.buy(key)
	_refresh_panel()

var view: OptionButton
var legend: Label
var _arm := -1                     # mine id whose Decommission link was tapped once

func _ready() -> void:
	_refresh_panel()
	view = OptionButton.new()
	for f in World.FILTERS: view.add_item(f)
	view.item_selected.connect(func(i): get_parent().view_filter = i; legend.visible = i > 0; legend.text = ["", "Green: methane. Above 1.5% nobody works the face, 5% can explode.", "Orange: a face with gas, cut coal or a machine running is where a fire starts.", "Red: unsupported roof under strain, or already down.", "Blue: standing water, flooded past 75%.", "Cyan: a long way from the fan; air is thin at the far end."][i])
	$Top.add_child(view)
	legend = Label.new(); legend.visible = false; legend.position = Vector2(12, 300); legend.add_theme_color_override("font_color", Color("f1efe6"))
	add_child(legend)
	$Info.meta_clicked.connect(_on_meta)

func _on_meta(meta: Variant) -> void:
	var world: World = get_parent()
	var parts: PackedStringArray = str(meta).split(":")
	var id := int(parts[1])
	match parts[0]:
		"find":
			var sg: Segment = world.segs[id]
			world.cam.position = sg.pos(minf(sg.prog, 40.0)); world.cam.zoom = Vector2(2.0, 2.0)
		"findw":
			world.cam.position = world.workers[id].position; world.cam.zoom = Vector2(2.5, 2.5)
		"decom":
			if _arm == id: world.decommission(world.segs[id]); _arm = -1
			else: _arm = id
		"salv": world.salvage(world.segs[id])
	_refresh_info()

func _refresh_panel() -> void:
	for key in ["roof", "pump", "vent"]:
		var b: Button = $Panel/Box.get_node(key)
		var tier: int = Game.up.get(key, 0)
		var next: int = tier + 1
		if next >= Game.UPGRADES[key].size():
			b.text = "%s: %s (top)" % [key.capitalize(), Game.UPGRADES[key][tier][0]]; b.disabled = true
		else:
			b.text = "%s → %s ($%d)" % [key.capitalize(), Game.UPGRADES[key][next][0], Game.UPGRADES[key][next][1]]
			b.tooltip_text = Game.UPGRADES[key][next][2]

func _on_speed(k: int) -> void:
	if k == 0: Game.paused = not Game.paused
	else: Game.paused = false; Game.speed = float(k)

var _info_t := 0.0
func _refresh_info() -> void:
	var world: World = get_parent()
	var lines := []
	var n := 0
	for sg in world.segs:
		if sg.dead or sg.parent >= 0 or sg.prog < 1.0: continue
		n += 1
		var worst := 0.0; var wet := 0.0; var rub := false; var faces := 0
		for c in world.segs:
			if c.dead or c.root_of(world.segs) != sg.id: continue
			worst = maxf(worst, c.stress); wet = maxf(wet, c.water); rub = rub or c.rubble.size() > 0
			if not c.done(): faces += 1
		var g: float = world.hazards.gas_of(sg)
		var act := ""
		if sg.decom:
			act = "[color=#ff8a73]closed[/color]" + ("  salvaging" if sg.salvage else ("" if world.salvage_target(sg) == null else "  [url=salv:%d]salvage belt[/url]" % sg.id))
		else:
			act = "[url=decom:%d]%s[/url]" % [sg.id, "tap again to close" if _arm == sg.id else "close"]
		lines.append(("[b]%s No.%d[/b]  CH4 %s%.1f%%[/color]  water %s%d%%[/color]  roof %s%s[/color]  faces %d  [url=find:" + str(sg.id) + "]find[/url]  " + act) % [
			"Shaft" if sg.is_shaft() else "Mine", n,
			"[color=#ff8a73]" if g >= 1.5 else ("[color=#f2b705]" if g >= 0.8 else "[color=#9be07a]"), g,
			"[color=#ff8a73]" if wet > 0.75 else ("[color=#f2b705]" if wet > 0.3 else "[color=#9be07a]"), int(wet * 100),
			"[color=#ff8a73]" if (rub or worst > 0.7) else ("[color=#f2b705]" if worst > 0.4 else "[color=#9be07a]"), ("caved in" if rub else ("working" if worst > 0.7 else ("strained" if worst > 0.4 else "sound"))), faces])
	if lines.is_empty(): lines.append("No mines open yet. Drag from the hillside into the ground.")
	lines.append("")
	for w in world.workers:
		lines.append("%s  [color=#9a948a]%s · %s · %d%%[/color]  [url=findw:%d]find[/url]" % [w.worker_name, Worker.ROLE_NAME[w.role], w.status(), int(w.energy), w.id])
	$Info.text = "\n".join(lines)

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
