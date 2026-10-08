class_name Enemies
extends RefCounted
## 敌人容器：面向数据的定长数组 + 空闲链表，无 Node / 无对象分配。

var n_alive: int = 0
var total_spawned: int = 0
var total_killed: int = 0
var total_leaked: int = 0

# ---- 定长数据表 ----
var pos: PackedVector2Array = PackedVector2Array()
var hp: PackedFloat32Array = PackedFloat32Array()
var max_hp: PackedFloat32Array = PackedFloat32Array()
var spd: PackedFloat32Array = PackedFloat32Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var etype: PackedByteArray = PackedByteArray()
var gold: PackedInt32Array = PackedInt32Array()
var life_dmg: PackedInt32Array = PackedInt32Array()
var slow_pct: PackedFloat32Array = PackedFloat32Array()
var slow_timer: PackedFloat32Array = PackedFloat32Array()
var flash: PackedFloat32Array = PackedFloat32Array()
var phase: PackedFloat32Array = PackedFloat32Array()
var alive: PackedByteArray = PackedByteArray()

var _high: int = 0
var _free: Array[int] = []

# 常量（与 MapGrid.Kind 对应，内联判定用，避免热循环里做 enum 查表）
const WALL_KIND := 1             # MapGrid.Kind.WALL
const GOAL_KIND := 3             # MapGrid.Kind.GOAL
const _SEP_CANDIDATE_CAP := 16   # 每敌每帧最多考察的邻居数：把分离力开销钉死为常数

# 上一帧事件（供 Game 记账/特效）
var leaked_indices: PackedInt32Array = PackedInt32Array()
var leaked_count: int = 0
var killed_indices: PackedInt32Array = PackedInt32Array()
var killed_count: int = 0


func _init() -> void:
	var cap := Cfg.MAX_ENEMIES
	pos.resize(cap)
	hp.resize(cap)
	max_hp.resize(cap)
	spd.resize(cap)
	radius.resize(cap)
	etype.resize(cap)
	gold.resize(cap)
	life_dmg.resize(cap)
	slow_pct.resize(cap)
	slow_timer.resize(cap)
	flash.resize(cap)
	phase.resize(cap)
	alive.resize(cap)
	alive.fill(0)
	# 事件表容量 = 敌人上限：一帧内最多这么多敌人离开/死亡，绝不会漏记
	leaked_indices.resize(cap)
	killed_indices.resize(cap)


## 生成一只敌人，返回下标；容量满返回 -1
func spawn(type_id: int, wave: int, at: Vector2) -> int:
	var i := -1
	if not _free.is_empty():
		i = _free.pop_back()
	elif _high < Cfg.MAX_ENEMIES:
		i = _high
		_high += 1
	else:
		return -1

	var def: Dictionary = Cfg.ENEMIES[type_id]
	pos[i] = at
	max_hp[i] = float(def["hp"]) * Cfg.hp_mult(wave)
	hp[i] = max_hp[i]
	spd[i] = float(def["speed"]) * Cfg.speed_mult(wave)
	radius[i] = float(def["radius"])
	etype[i] = type_id
	gold[i] = int(def["gold"])
	life_dmg[i] = int(def["life"])
	slow_pct[i] = 0.0
	slow_timer[i] = 0.0
	flash[i] = 0.0
	phase[i] = randf() * TAU
	alive[i] = 1
	n_alive += 1
	total_spawned += 1
	return i


func _release(i: int) -> void:
	alive[i] = 0
	_free.append(i)
	n_alive -= 1


func damage(i: int, amount: float) -> bool:
	if alive[i] == 0:
		return false
	hp[i] -= amount
	flash[i] = 1.0
	if hp[i] <= 0.0:
		hp[i] = 0.0
		if killed_count < killed_indices.size():
			killed_indices[killed_count] = i
			killed_count += 1
		total_killed += 1
		_release(i)
		return true
	return false


func apply_slow(i: int, pct: float, time: float) -> void:
	if alive[i] == 0 or pct <= 0.0:
		return
	if pct > slow_pct[i]:
		slow_pct[i] = pct
	elif slow_timer[i] <= 0.0:
		slow_pct[i] = pct
	if time > slow_timer[i]:
		slow_timer[i] = time


func current_speed(i: int) -> float:
	if slow_timer[i] > 0.0:
		return spd[i] * (1.0 - slow_pct[i])
	return spd[i]


func begin_frame() -> void:
	leaked_count = 0
	killed_count = 0


## 逐帧推进：沿流场移动、减速计时、到达终点判定。
## 这是全场最热的循环（每帧每敌一次），因此全部就地内联：
## 不调用 grid/hash 的方法，把 Packed 数组提到局部变量，避免 GDScript 的函数调用开销。
func update(dt: float, grid: MapGrid, field: FlowField, hash: SpatialHash) -> void:
	begin_frame()

	var gw: int = grid.w
	var gh: int = grid.h
	var kind: PackedByteArray = grid.kind
	var tower_at: PackedInt32Array = grid.tower_at
	var nxt_cell: PackedInt32Array = field.best
	var goal_c: Vector2 = field.goal_center

	var cell: float = float(Cfg.CELL)
	var inv: float = 1.0 / cell
	var world_w: float = float(gw) * cell
	var world_h: float = float(gh) * cell

	var hs: float = hash.cell_size
	var hcols: int = hash.cols
	var hrows: int = hash.rows
	var heads: PackedInt32Array = hash.heads
	var nexts: PackedInt32Array = hash.nexts

	var leak_cap: int = leaked_indices.size()

	for i in _high:
		if alive[i] == 0:
			continue

		var fl: float = flash[i]
		if fl > 0.0:
			flash[i] = maxf(0.0, fl - dt * 5.0)
		var st: float = slow_timer[i]
		if st > 0.0:
			st -= dt
			slow_timer[i] = st
			if st <= 0.0:
				slow_pct[i] = 0.0

		var p: Vector2 = pos[i]
		var cx: int = int(p.x * inv)
		var cy: int = int(p.y * inv)
		if cx < 0 or cy < 0 or cx >= gw or cy >= gh:
			cx = clampi(cx, 0, gw - 1)
			cy = clampi(cy, 0, gh - 1)
			p = Vector2((float(cx) + 0.5) * cell, (float(cy) + 0.5) * cell)
			pos[i] = p
		var cidx: int = cy * gw + cx

		# 到达终点 -> 漏怪
		if kind[cidx] == GOAL_KIND:
			if leaked_count < leak_cap:
				leaked_indices[leaked_count] = i
				leaked_count += 1
			total_leaked += 1
			_release(i)
			continue

		# 查流场得到"下一格的中心"，作为这一帧的移动目标
		var nc: int = nxt_cell[cidx]
		var tx: float
		var ty: float
		if nc >= 0:
			tx = (float(nc % gw) + 0.5) * cell
			ty = (float(nc / gw) + 0.5) * cell
		else:
			# 兜底"尽力场"：流场不可达时直接朝终点挤，不崩不卡死
			tx = goal_c.x
			ty = goal_c.y

		var dx: float = tx - p.x
		var dy: float = ty - p.y
		var dl: float = sqrt(dx * dx + dy * dy)
		if dl > 0.0001:
			dx /= dl
			dy /= dl

		# --- 分离力（内联空间哈希；最多考察 16 个邻居，开销与密度无关）---
		var r: float = radius[i]
		var qr: float = r * 2.6
		var x0: int = clampi(int((p.x - qr) / hs), 0, hcols - 1)
		var x1: int = clampi(int((p.x + qr) / hs), 0, hcols - 1)
		var y0: int = clampi(int((p.y - qr) / hs), 0, hrows - 1)
		var y1: int = clampi(int((p.y + qr) / hs), 0, hrows - 1)
		var sx: float = 0.0
		var sy: float = 0.0
		var seen: int = 0
		for by in range(y0, y1 + 1):
			var base: int = by * hcols
			for bx in range(x0, x1 + 1):
				var it: int = heads[base + bx]
				while it != -1:
					if seen >= _SEP_CANDIDATE_CAP:
						break
					seen += 1
					if it != i and alive[it] == 1:
						var ox: float = p.x - pos[it].x
						var oy: float = p.y - pos[it].y
						var d2: float = ox * ox + oy * oy
						var md: float = (r + radius[it]) * 0.92
						if d2 < md * md and d2 > 0.0001:
							var d: float = sqrt(d2)
							var w: float = (md - d) / md
							sx += (ox / d) * w
							sy += (oy / d) * w
					it = nexts[it]
			if seen >= _SEP_CANDIDATE_CAP:
				break

		var spd_i: float = spd[i]
		if st > 0.0:
			spd_i *= (1.0 - slow_pct[i])
		var step: float = spd_i * dt
		# 分离力必须归一化后再叠加：
		#  1) 先把分离向量限长到 0.70，叠加 0.85 系数后永远小于 1，
		#     保证合成方向始终保留 40% 以上的"朝路点"分量，敌人绝不会被挤得倒退或原地顶住；
		#  2) 合成向量再归一化，保证每帧位移严格等于 step（否则密度高时会被挤到几倍速）。
		# 这两条是"大量敌人挤在窄走廊里也能保证不漏、不卡死"的关键。
		var sl: float = sqrt(sx * sx + sy * sy)
		if sl > 0.70:
			sx = sx / sl * 0.70
			sy = sy / sl * 0.70
		var mx: float = dx + sx * 0.85
		var my: float = dy + sy * 0.85
		var ml: float = sqrt(mx * mx + my * my)
		if ml > 0.0001:
			mx /= ml
			my /= ml
		var nx_f: float = p.x + mx * step
		var ny_f: float = p.y + my * step
		if nx_f < 0.0:
			nx_f = 0.0
		elif nx_f > world_w - 0.5:
			nx_f = world_w - 0.5
		if ny_f < 0.0:
			ny_f = 0.0
		elif ny_f > world_h - 0.5:
			ny_f = world_h - 0.5

		# 逐轴回退：不允许走进墙 / 塔格
		var nx: int = int(nx_f * inv)
		var ny: int = int(ny_f * inv)
		var ni: int = ny * gw + nx
		if kind[ni] != WALL_KIND and tower_at[ni] < 0:
			pos[i] = Vector2(nx_f, ny_f)
		else:
			var ai: int = cy * gw + nx
			if kind[ai] != WALL_KIND and tower_at[ai] < 0:
				pos[i] = Vector2(nx_f, p.y)
			else:
				var bi: int = ny * gw + cx
				if kind[bi] != WALL_KIND and tower_at[bi] < 0:
					pos[i] = Vector2(p.x, ny_f)


## 半径内的敌人（供塔/溅射使用），返回数量写入 out
func query_radius(p: Vector2, radius: float, hash: SpatialHash, out: PackedInt32Array) -> int:
	var found := hash.query(p, radius, out)
	var n := 0
	for k in found:
		var j := out[k]
		if alive[j] == 0:
			continue
		if pos[j].distance_squared_to(p) <= radius * radius:
			out[n] = j
			n += 1
	return n


func count_alive_fast() -> int:
	return n_alive
