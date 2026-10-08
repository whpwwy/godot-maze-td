class_name Bullets
extends RefCounted
## 子弹：面向数据定长数组 + 空闲链表。追踪飞行 + 线段扫掠命中（防高速穿模）。

var n_alive: int = 0
var total_fired: int = 0
var total_hits: int = 0

var pos: PackedVector2Array = PackedVector2Array()
var vel: PackedVector2Array = PackedVector2Array()
var target: PackedInt32Array = PackedInt32Array()
var dmg: PackedFloat32Array = PackedFloat32Array()
var spd: PackedFloat32Array = PackedFloat32Array()
var splash: PackedFloat32Array = PackedFloat32Array()
var slow_pct: PackedFloat32Array = PackedFloat32Array()
var slow_time: PackedFloat32Array = PackedFloat32Array()
var life: PackedFloat32Array = PackedFloat32Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var kind: PackedByteArray = PackedByteArray()
var alive: PackedByteArray = PackedByteArray()

var _high: int = 0
var _free: Array[int] = []
var _query_buf: PackedInt32Array = PackedInt32Array()
var _hit_buf: PackedInt32Array = PackedInt32Array()


func _init() -> void:
	var cap := Cfg.MAX_BULLETS
	pos.resize(cap)
	vel.resize(cap)
	target.resize(cap)
	dmg.resize(cap)
	spd.resize(cap)
	splash.resize(cap)
	slow_pct.resize(cap)
	slow_time.resize(cap)
	life.resize(cap)
	radius.resize(cap)
	kind.resize(cap)
	alive.resize(cap)
	alive.fill(0)
	_query_buf.resize(512)
	_hit_buf.resize(512)


func fire(from: Vector2, heading: Vector2, target_idx: int, ttype: int, level: int) -> int:
	var i := -1
	if not _free.is_empty():
		i = _free.pop_back()
	elif _high < Cfg.MAX_BULLETS:
		i = _high
		_high += 1
	else:
		return -1

	var def: Dictionary = Cfg.TOWERS[ttype]
	pos[i] = from
	spd[i] = float(def["bullet_speed"])
	vel[i] = heading.normalized() * spd[i]
	target[i] = target_idx
	dmg[i] = Cfg.tower_damage(ttype, level)
	splash[i] = Cfg.tower_splash(ttype, level)
	slow_pct[i] = float(def["slow"])
	slow_time[i] = Cfg.tower_slow_time(ttype, level)
	radius[i] = float(def["bullet_radius"])
	kind[i] = int(def["bullet_kind"])
	life[i] = 3.0
	alive[i] = 1
	n_alive += 1
	total_fired += 1
	return i


func _release(i: int) -> void:
	alive[i] = 0
	_free.append(i)
	n_alive -= 1


## 逐帧推进 + 命中判定。
## 性能要点：绝大多数命中都发生在"追踪目标"身上，所以先做 O(1) 的目标线段判定；
## 只有目标已消失/落空时才退回空间哈希做一次小范围补判。这样子弹开销与同屏密度脱钩。
func update(dt: float, enemies: Enemies, hash: SpatialHash, fx: Effects) -> void:
	var eh: int = enemies.alive.size()
	var epos: PackedVector2Array = enemies.pos
	var erads: PackedFloat32Array = enemies.radius
	var ealive: PackedByteArray = enemies.alive

	for i in _high:
		if alive[i] == 0:
			continue

		life[i] -= dt
		if life[i] <= 0.0:
			_release(i)
			continue

		var p0: Vector2 = pos[i]

		# 追踪转向
		var t: int = target[i]
		var t_alive: bool = t >= 0 and t < eh and ealive[t] == 1
		if t_alive:
			var desired := (epos[t] - p0).normalized() * spd[i]
			vel[i] = vel[i].lerp(desired, minf(1.0, 16.0 * dt))
			var l := vel[i].length()
			if l > 0.0001:
				vel[i] = vel[i] / l * spd[i]
		else:
			target[i] = -1
			t = -1

		var p1: Vector2 = p0 + vel[i] * dt
		var seg: Vector2 = p1 - p0
		var l2: float = seg.length_squared()

		var best_e := -1
		var best_t := 2.0

		# --- 1) 直接判定追踪目标（常见路径，无哈希开销）---
		if t_alive:
			var er: float = erads[t] + radius[i]
			if l2 < 0.0001:
				if epos[t].distance_squared_to(p0) <= er * er:
					best_t = 0.0
					best_e = t
			else:
				var tt := clampf((epos[t] - p0).dot(seg) / l2, 0.0, 1.0)
				if epos[t].distance_squared_to(p0 + seg * tt) <= er * er:
					best_t = tt
					best_e = t

		# --- 2) 目标已不存在时，小范围补判（限 8 个候选）---
		if best_e < 0:
			var mid: Vector2 = (p0 + p1) * 0.5
			var qr: float = sqrt(l2) * 0.5 + 14.0
			var found := hash.query(mid, qr, _query_buf)
			var seen := 0
			for k in found:
				if seen >= 8:
					break
				seen += 1
				var e := _query_buf[k]
				if ealive[e] == 0:
					continue
				var er2: float = erads[e] + radius[i]
				var tt2 := 0.0
				var d2 := 0.0
				if l2 < 0.0001:
					d2 = epos[e].distance_squared_to(p0)
				else:
					tt2 = clampf((epos[e] - p0).dot(seg) / l2, 0.0, 1.0)
					d2 = epos[e].distance_squared_to(p0 + seg * tt2)
				if d2 <= er2 * er2 and tt2 < best_t:
					best_t = tt2
					best_e = e

		if best_e < 0:
			pos[i] = p1
			continue

		# --- 命中 ---
		total_hits += 1
		var impact := p0 + (p1 - p0) * best_t
		var damage := dmg[i]
		enemies.damage(best_e, damage)

		if splash[i] > 0.0:
			var cnt := enemies.query_radius(impact, splash[i], hash, _hit_buf)
			for k in cnt:
				var e2 := _hit_buf[k]
				if e2 == best_e:
					continue
				var d := enemies.pos[e2].distance_to(impact)
				var f := 1.0 - 0.55 * clampf(d / splash[i], 0.0, 1.0)
				enemies.damage(e2, damage * f)
			fx.ring(impact, 6.0, splash[i], 0.30, Color(1.0, 0.78, 0.42))
			fx.spark(impact, Color(1.0, 0.86, 0.55), 0.26, 9.0)
		elif kind[i] == 2:
			fx.ring(impact, 4.0, 20.0, 0.22, Color(0.62, 0.92, 1.0))
			fx.spark(impact, Color(0.80, 0.96, 1.0), 0.18, 5.0)
		else:
			fx.spark(impact, Color(0.85, 0.95, 1.0), 0.16, 5.0)

		if slow_pct[i] > 0.0 and slow_time[i] > 0.0:
			enemies.apply_slow(best_e, slow_pct[i], slow_time[i])
			if splash[i] > 0.0:
				var cnt2 := enemies.query_radius(impact, splash[i], hash, _hit_buf)
				for k in cnt2:
					enemies.apply_slow(_hit_buf[k], slow_pct[i], slow_time[i])

		_release(i)


## 清空（重开一局用）。与 Towers.clear_all 同理：_high 是"用过的下标上界"，
## fire() 会从空闲链取高位下标，若这里把 _high 归零，update() 的 `for i in _high` 就遍历不到。
func reset() -> void:
	for i in _high:
		alive[i] = 0
	_free.clear()
	for i in _high:
		_free.append(i)
	n_alive = 0
	total_fired = 0
	total_hits = 0
