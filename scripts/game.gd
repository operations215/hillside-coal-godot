## Company state shared by every scene: money, the clock, the market and the save file.
extends Node

signal money_changed
signal day_passed(day: int)
signal toast(text: String)

const DAY_LEN := 60.0            # seconds of game time in one shift
const START_MONEY := 6000.0

var money := START_MONEY
var earned := 0.0
var time := 0.0
var day := 1
var price := 85.0                # dollars a ton of coal
var speed := 1.0
var paused := false
var pile := 0.0                  # tons of coal on the stockpile
var piles := {}                  # other materials on the yard, by material id
var dug_ft := 0.0
var day_earn := 0.0
var day_money := START_MONEY

func reset() -> void:
	money = START_MONEY; earned = 0.0; time = 0.0; day = 1; price = 85.0; speed = 1.0; paused = false
	pile = 0.0; piles = {}; dug_ft = 0.0; day_earn = 0.0; day_money = START_MONEY

func tick(dt: float) -> void:
	time += dt
	var d := int(time / DAY_LEN) + 1
	if d != day:
		day = d
		# the market drifts a little every shift and is pulled back toward the long-run price
		price = clampf(price + (85.0 - price) * 0.05 + randf_range(-6.0, 6.0), 60.0, 125.0)
		day_passed.emit(day)
		var profit := money - day_money
		toast.emit("Day %d: sold $%s, profit $%s%s" % [day - 1, _money(day_earn), ("-" if profit < 0 else ""), _money(absf(profit))])
		day_earn = 0.0; day_money = money

func pay(amount: float) -> void:
	money += amount
	if amount > 0.0:
		earned += amount; day_earn += amount
	money_changed.emit()

func spend(amount: float) -> bool:
	if money < amount:
		toast.emit("Not enough cash: that costs $%s." % _money(amount))
		return false
	money -= amount
	money_changed.emit()
	return true

func _money(v: float) -> String:
	var s := str(int(round(v)))
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0: out = "," + out
	return out

func money_text(v: float) -> String:
	return "$" + _money(v)
