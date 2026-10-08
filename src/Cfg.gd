class_name Cfg
extends RefCounted
## 全局数值表（纯数据，无状态）。所有平衡性数字都集中在这里，方便调参。

# ---------------------------------------------------------------- 网格 / 窗口
const GW := 31            # 网格列数
const GH := 19            # 网格行数
const CELL := 40          # 格边长(px)
const VIEW_W := GW * CELL  # 1240
const VIEW_H := GH * CELL  # 760

const BLOCK_PITCH := 3    # 迷宫块间距：2 格地面 + 1 格墙
const BW := 10            # 迷宫块列数
const BH := 6             # 迷宫块行数

const SPAWN_CELLS: Array[Vector2i] = [Vector2i(0, 7), Vector2i(0, 8)]
const GOAL_CELLS: Array[Vector2i] = [Vector2i(30, 7), Vector2i(30, 8)]

const DEFAULT_SEED := 20261008

# 8 邻域代价（整数，避免浮点误差）
const COST_ORTHO := 100
const COST_DIAG := 141

# ---------------------------------------------------------------- 经济 / 生命
const START_GOLD := 320
const START_LIVES := 20
const SELL_RATIO := 0.70
const WAVE_PREP_TIME := 6.0

# ---------------------------------------------------------------- 容量（对象池定长）
const MAX_ENEMIES := 8192
const MAX_BULLETS := 20000
const MAX_TOWERS := 1024
const MAX_EFFECTS := 512

# ---------------------------------------------------------------- 速度档位
const SPEEDS: Array[float] = [1.0, 2.0, 3.0]

# ---------------------------------------------------------------- 塔定义
# 键位 1 / 2 / 3 对应下标 0 / 1 / 2
const TOWERS: Array[Dictionary] = [
	{
		"name": "弩塔",
		"desc": "单体速射",
		"cost": 50,
		"range": 116.0,
		"rate": 1.70,
		"damage": 11.0,
		"bullet_speed": 560.0,
		"bullet_radius": 3.0,
		"splash": 0.0,
		"slow": 0.0,
		"slow_time": 0.0,
		"bullet_kind": 0,
		"color": Color(0.384, 0.816, 1.0),      # #62d0ff
		"dark": Color(0.086, 0.243, 0.353),     # #163e5a
		"accent": Color(0.886, 0.965, 1.0),     # #e2f6ff
	},
	{
		"name": "炮塔",
		"desc": "范围爆破",
		"cost": 110,
		"range": 138.0,
		"rate": 0.72,
		"damage": 30.0,
		"bullet_speed": 340.0,
		"bullet_radius": 5.0,
		"splash": 46.0,
		"slow": 0.0,
		"slow_time": 0.0,
		"bullet_kind": 1,
		"color": Color(1.0, 0.702, 0.278),      # #ffb347
		"dark": Color(0.353, 0.196, 0.043),     # #5a320b
		"accent": Color(1.0, 0.941, 0.812),     # #fff0cf
	},
	{
		"name": "冰塔",
		"desc": "减速控场",
		"cost": 75,
		"range": 104.0,
		"rate": 1.15,
		"damage": 5.0,
		"bullet_speed": 430.0,
		"bullet_radius": 3.5,
		"splash": 0.0,
		"slow": 0.45,
		"slow_time": 1.80,
		"bullet_kind": 2,
		"color": Color(0.545, 0.914, 0.992),    # #8be9fd
		"dark": Color(0.086, 0.243, 0.302),     # #163e4d
		"accent": Color(0.918, 0.988, 1.0),     # #eafcff
	},
]
const TOWER_COUNT := 3
const MAX_TOWER_LEVEL := 3

# ---------------------------------------------------------------- 敌人定义
const ENEMIES: Array[Dictionary] = [
	{
		"name": "游荡者", "hp": 44.0, "speed": 58.0, "gold": 7, "life": 1,
		"radius": 8.5, "scale": 1.0, "color": Color(1.0, 0.482, 0.447),
	},
	{
		"name": "疾行者", "hp": 30.0, "speed": 104.0, "gold": 6, "life": 1,
		"radius": 7.0, "scale": 0.9, "color": Color(1.0, 0.847, 0.400),
	},
	{
		"name": "重甲兵", "hp": 190.0, "speed": 36.0, "gold": 19, "life": 2,
		"radius": 11.0, "scale": 1.2, "color": Color(0.655, 0.545, 0.980),
	},
	{
		"name": "首领", "hp": 1400.0, "speed": 30.0, "gold": 160, "life": 10,
		"radius": 16.0, "scale": 1.7, "color": Color(1.0, 0.176, 0.333),
	},
]
const ENEMY_COUNT := 4

# ---------------------------------------------------------------- 地图配色
const C_BG := Color(0.043, 0.051, 0.075)
const C_FLOOR := Color(0.090, 0.110, 0.163)
const C_FLOOR_EDGE := Color(0.133, 0.161, 0.227)
const C_FLOOR_LINE := Color(0.161, 0.196, 0.271)
const C_WALL := Color(0.043, 0.055, 0.086)
const C_WALL_FACE := Color(0.078, 0.098, 0.153)
const C_WALL_TOP := Color(0.176, 0.216, 0.318)
const C_SPAWN := Color(0.902, 0.290, 0.216)
const C_GOAL := Color(0.204, 0.816, 0.498)
const C_HOVER_OK := Color(0.31, 0.94, 0.66)
const C_HOVER_BAD := Color(1.0, 0.30, 0.36)
const C_PATH_HINT := Color(0.25, 0.55, 0.85)

# ---------------------------------------------------------------- 波次
const WAVE_COUNT := 12

## 第 w 波（1 起）的生成组：{type, count, interval, delay}
static func build_wave(w: int) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var iv: float = maxf(0.055, 0.50 - 0.036 * float(w))
	groups.append({"type": 0, "count": 14 + 10 * w, "interval": iv, "delay": 0.0})
	if w >= 3:
		groups.append({"type": 1, "count": 6 + 8 * w, "interval": iv, "delay": 0.9})
	if w >= 5:
		groups.append({"type": 2, "count": 3 + 6 * w, "interval": iv * 1.8, "delay": 1.8})
	if w == 8 or w == 10:
		groups.append({"type": 3, "count": 1, "interval": 1.0, "delay": 3.0})
	elif w >= 12:
		groups.append({"type": 3, "count": 3, "interval": 2.5, "delay": 2.0})
	return groups


static func wave_total(w: int) -> int:
	var n := 0
	for g in build_wave(w):
		n += int(g["count"])
	return n


## 第 w 波的敌人血量倍率
static func hp_mult(w: int) -> float:
	return 1.0 + 0.26 * float(w - 1)


## 第 w 波的敌人速度倍率
static func speed_mult(w: int) -> float:
	return 1.0 + 0.015 * float(w - 1)


# ---------------------------------------------------------------- 塔数值
## level -> level+1 的升级价格（满级返回 0）
static func upgrade_cost(t: int, level: int) -> int:
	var base: int = TOWERS[t]["cost"]
	if level == 1:
		return int(float(base) * 0.9)
	elif level == 2:
		return int(float(base) * 1.5)
	return 0


static func tower_damage(t: int, level: int) -> float:
	return float(TOWERS[t]["damage"]) * pow(1.62, level - 1)


static func tower_range(t: int, level: int) -> float:
	return float(TOWERS[t]["range"]) * pow(1.10, level - 1)


static func tower_rate(t: int, level: int) -> float:
	return float(TOWERS[t]["rate"]) * pow(1.16, level - 1)


static func tower_splash(t: int, level: int) -> float:
	var s: float = TOWERS[t]["splash"]
	if s <= 0.0:
		return 0.0
	return s * pow(1.15, level - 1)


static func tower_slow_time(t: int, level: int) -> float:
	var s: float = TOWERS[t]["slow_time"]
	if s <= 0.0:
		return 0.0
	return s * pow(1.15, level - 1)


## 建塔 + 升级的累计投入
static func tower_invested(t: int, level: int) -> int:
	var total: int = TOWERS[t]["cost"]
	for lv in range(1, level):
		total += upgrade_cost(t, lv)
	return total


## 卖出返还
static func sell_value(t: int, level: int) -> int:
	return int(float(tower_invested(t, level)) * SELL_RATIO)


static func cell_center(gx: int, gy: int) -> Vector2:
	return Vector2((float(gx) + 0.5) * CELL, (float(gy) + 0.5) * CELL)
