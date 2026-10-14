## Ground materials: what the hill is made of, what it is worth and how hard it digs.
extends Node

enum { AIR, SOIL, SAND, CLAY, SHALE, COAL, LIME, GRAN, BED, IRON, COPPER, GOLD }

const NAMES := ["Air", "Topsoil", "Sand", "Clay", "Shale", "Coal", "Limestone", "Granite", "Bedrock", "Iron ore", "Copper ore", "Gold quartz"]
const COLORS := [Color(0, 0, 0, 0), Color("6a4a30"), Color("c09a60"), Color("b3ab96"), Color("6d6e78"), Color("1d1c20"), Color("a9a59a"), Color("8a7276"), Color("3a3a40"), Color("8a4a30"), Color("4f9a7c"), Color("e8c24a")]
const HARD := [0.0, 1.0, 0.8, 1.2, 2.2, 1.0, 3.0, 4.5, 99.0, 3.2, 3.0, 3.4]
## Dollars a ton paid at the scale house for the non-coal materials (coal uses the live market price)
const VALUE := {SOIL: -1.0, CLAY: 4.0, SAND: 6.0, SHALE: -0.5, LIME: 9.0, GRAN: 7.0, IRON: 70.0, COPPER: 220.0, GOLD: 3200.0}
const TONS_COAL := 0.8   # tons in one dug coal cell
const TONS_ORE := 0.22
const TONS_ROCK := 0.05

static func is_ore(m: int) -> bool:
	return m == IRON or m == COPPER or m == GOLD

static func is_mineral(m: int) -> bool:
	return m == COAL or is_ore(m)

static func tons(m: int) -> float:
	if m == COAL: return TONS_COAL
	if is_ore(m): return TONS_ORE
	return TONS_ROCK
