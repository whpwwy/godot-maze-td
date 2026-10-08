class_name Towers
extends RefCounted
## 塔容器：锁敌 -> 开火 -> 升级 -> 卖出。

var n_alive: int = 0
var total_built: int = 0

var cx: PackedInt32Array = PackedInt32Array()
var cy: PackedInt32Array = PackedInt32Array()
var ttype: PackedByteArray = PackedByteArray()
var level: PackedByteArray = PackedByteArray()
var cd: PackedFloat32Array = PackedFloat32Array()
var angle: PackedFloat32Array = PackedFloat32Array()
var alive: PackedByteArray = PackedByteArray()
var target_at: PackedInt32Array = PackedInt32Array()

var _high: int = 0
var _free: Array[int] = []
# 锁敌候选上限：射程内可能挤着上千敌人，全扫会很贵；取前 N 个已经足够选出"最靠前"的
var _query_buf: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var cap := Cfg.MAX_TOWERS
	cx.resize(cap)
	cy.resize(cap)
	ttype.resize(cap)
	level.resize(cap)
	cd.resize(cap)
	angle.resize(cap)
	alive.resize(cap)
	target_at.resize(cap)
	alive.fill(0)
	_query_buf.resize(128)


func pos_of(i: int) -> Vector2:
	return Cfg.cell_center(cx[i], cy[i])


func place(grid: MapGrid, x: int, y: int, t: int) -> int:
	var i := -1
	if not _free.is_empty():
		i = _free.pop_back()
	elif _high < Cfg.MAX_TOWERS:
		i = _high
		_high += 1
	else:
		return -1
	cx[i] = x
	cy[i] = y
	ttype[i] = t
	level[i] = 1
	cd[i] = 0.0
	angle[i] = 0.0
	alive[i] = 1
	target_at[i] = -1
	n_alive += 1
	total_built += 1
	grid.set_tower(x, y, i)
	return i


func remove(grid: MapGrid, i: int) -> void:
	if alive[i] == 0:
		return
	grid.clear_tower(cx[i], cy[i])
	alive[i] = 0
	_free.append(i)
	n_alive -= 1


func upgrade(i: int) -> bool:
	if alive[i] == 0 or level[i] >= Cfg.MAX_TOWER_LEVEL:
		return false
	level[i] += 1
	return true


## 性能要点：择优（一次空间哈希扫描）只在"冷却完毕、或旧目标已消失"时做，
## 因此每座塔每发射一发只扫描最多一次；两次射击之间只做一次廉价的"炮管转向"。
## 候选上限 _query_buf.size()，把单次扫描开销钉死。
func update(dt: float, grid: MapGrid, field: FlowField, enemies: Enemies,
		hash: SpatialHash, bullets: Bullets, on_shot: Callable) -> void:
	var gw: int = grid.w
	var gh: int = grid.h
	var dist_lut: PackedInt32Array = field.dist
	var cell: float = float(Cfg.CELL)
	var inv: float = 1.0 / cell
	var epos: PackedVector2Array = enemies.pos
	var ealive: PackedByteArray = enemies.alive
	var eh: int = ealive.size()
	var qb: PackedInt32Array = _query_buf

	for i in _high:
		if alive[i] == 0:
			continue
		if cd[i] > 0.0:
			cd[i] -= dt

		var p := pos_of(i)
		var t: int = ttype[i]
		var lv: int = level[i]
		var rng_r: float = Cfg.tower_range(t, lv)

		# --- 顺手路径：本帧不打算开火且旧目标仍存活 -> 只转向 ---
		var cur: int = target_at[i]
		if cd[i] > 0.0 and cur >= 0 and cur < eh and ealive[cur] == 1:
			var cp: Vector2 = epos[cur]
			angle[i] = lerp_angle(angle[i], (cp - p).angle(), minf(1.0, 14.0 * dt))
			continue

		# --- 择优：射程内、最靠近终点的那个 ---
		var r2 := rng_r * rng_r
		var found := hash.query(p, rng_r, qb)
		var best := -1
		var best_d := 2147483647
		var best_p := Vector2.ZERO
		for k in found:
			var e := qb[k]
			if ealive[e] == 0:
				continue
			var ep: Vector2 = epos[e]
			if p.distance_squared_to(ep) > r2:
				continue
			# dist 更小 = 更靠近终点 = 更危险
			var ex: int = clampi(int(ep.x * inv), 0, gw - 1)
			var ey: int = clampi(int(ep.y * inv), 0, gh - 1)
			var d: int = dist_lut[ey * gw + ex]
			if d < 0:
				d = 2147483000
			if d < best_d:
				best_d = d
				best = e
				best_p = ep

		target_at[i] = best
		if best < 0:
			# 没目标：低频重试（0.12s），避免闲置塔每帧都做一次扫描
			if cd[i] <= 0.0:
				cd[i] = 0.12
			continue

		angle[i] = lerp_angle(angle[i], (best_p - p).angle(), minf(1.0, 14.0 * dt))
		if cd[i] > 0.0:
			continue

		var heading := Vector2.from_angle(angle[i])
		var muzzle := p + heading * 11.0
		if bullets.fire(muzzle, heading, best, t, lv) >= 0:
			cd[i] = 1.0 / maxf(0.05, Cfg.tower_rate(t, lv))
			on_shot.call(i, t)


func clear_all(grid: MapGrid) -> void:
	for i in _high:
		if alive[i] == 1:
			grid.clear_tower(cx[i], cy[i])
			alive[i] = 0
			target_at[i] = -1
	_free.clear()
	for i in _high:
		_free.append(i)
	# 注意：不要把 _high 归零。_high 是"用过的下标上界"，update() 靠它遍历所有槽位；
	# 若归零，而 place() 又从 _free 里取出高位下标，遍历范围就会漏掉这些塔 ——
	# 表现是"重开一局后塔全都不会开火"。_high 只增不减（上限 MAX_TOWERS）。
	n_alive = 0
	total_built = 0
