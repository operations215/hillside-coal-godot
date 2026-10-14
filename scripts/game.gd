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
var up := {"roof": 0, "pump": 0, "vent": 0}

const UPGRADES := {
	"roof": [["Timber props", 0, "The crew sets posts"], ["Resin roof bolts", 1800, "Bolting 50% faster, roof holds 60% longer"], ["Bolting machine", 5000, "Twice the bolting speed, roof holds twice as long"]],
	"pump": [["Bucket brigade", 0, "Water drains slowly"], ["Portable sump pumps", 1200, "Clears shallow water"], ["Main dewatering pump", 4000, "Keeps deep tunnels dry"]],
	"vent": [["Natural draught", 0, "Methane builds in long tunnels"], ["Portal fan", 900, "Clears a small mine"], ["Main fan house", 3600, "Keeps a big mine under 1%"]],
}

func buy(key: String) -> bool:
	var tier: int = up.get(key, 0) + 1
	if tier >= UPGRADES[key].size(): return false
	if not spend(UPGRADES[key][tier][1]): return false
	up[key] = tier
	toast.emit("%s: %s." % [UPGRADES[key][tier][0], UPGRADES[key][tier][2]])
	return true

func reset() -> void:
	money = START_MONEY; earned = 0.0; time = 0.0; day = 1; price = 85.0; speed = 1.0; paused = false
	pile = 0.0; piles = {}; dug_ft = 0.0; day_earn = 0.0; day_money = START_MONEY; up = {"roof": 0, "pump": 0, "vent": 0}

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

## 0 by day, 1 in the dead of night: the last quarter of each shift runs into the dark and the next dawns.
func night_f() -> float:
	var g := fmod(fmod(time, DAY_LEN) / DAY_LEN + 0.12, 1.0)
	return smoothstep(0.70, 0.84, g) * (1.0 - smoothstep(0.96, 1.0, g))

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
