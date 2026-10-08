class_name Waves
extends RefCounted
## 波次调度：备战倒计时 -> 按组密集生成 -> 全场清空后进入下一波。

var wave: int = 0                 # 当前波号（0 = 尚未开始）
var prep: float = Cfg.WAVE_PREP_TIME
var spawning: bool = false
var all_cleared: bool = false

var groups: Array[Dictionary] = []
var g_timer: PackedFloat32Array = PackedFloat32Array()
var g_spawned: PackedInt32Array = PackedInt32Array()
var spawned_this_wave: int = 0
var total_this_wave: int = 0
var wave_elapsed: float = 0.0

var _rng := RandomNumberGenerator.new()
var _spawn_points: PackedVector2Array = PackedVector2Array()


func _init() -> void:
	_rng.seed = 0xC0FFEE
	for c in Cfg.SPAWN_CELLS:
		_spawn_points.append(Cfg.cell_center(c.x, c.y))


## 当前这一波是否已经打完
func wave_finished(enemies: Enemies) -> bool:
	return spawning and spawned_this_wave >= total_this_wave and enemies.n_alive == 0


func can_start_next() -> bool:
	return (not spawning) and wave < Cfg.WAVE_COUNT


func start_next(enemies: Enemies) -> bool:
	if not can_start_next():
		return false
	_begin(enemies)
	return true


func _begin(enemies: Enemies) -> void:
	wave += 1
	groups = Cfg.build_wave(wave)
	var n := groups.size()
	g_timer.resize(n)
	g_spawned.resize(n)
	g_timer.fill(0.0)
	g_spawned.fill(0)
	var tot := 0
	for g in groups:
		tot += int(g["count"])
	total_this_wave = tot
	spawned_this_wave = 0
	spawning = true
	prep = 0.0
	wave_elapsed = 0.0


func update(dt: float, enemies: Enemies, fx: Effects) -> void:
	if all_cleared:
		return

	if not spawning:
		if wave >= Cfg.WAVE_COUNT:
			all_cleared = true
			return
		prep -= dt
		if prep <= 0.0:
			_begin(enemies)
		return

	wave_elapsed += dt
	var n := groups.size()
	for gi in n:
		var g := groups[gi]
		var interval := maxf(0.01, float(g["interval"]))
		var count := int(g["count"])
		g_timer[gi] += dt
		var delay := float(g["delay"])
		while g_timer[gi] >= interval and g_spawned[gi] < count:
			if wave_elapsed < delay:
				break
			g_timer[gi] -= interval
			g_spawned[gi] += 1
			spawned_this_wave += 1
			_spawn_one(enemies, int(g["type"]))
			if spawned_this_wave >= total_this_wave:
				break

	if wave_finished(enemies):
		spawning = false
		if wave >= Cfg.WAVE_COUNT:
			all_cleared = true
		else:
			prep = Cfg.WAVE_PREP_TIME


func _spawn_one(enemies: Enemies, type_id: int) -> void:
	var base := _spawn_points[_rng.randi_range(0, _spawn_points.size() - 1)]
	var jitter := Vector2(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-11.0, 11.0))
	var at := base + jitter
	at.x = maxf(4.0, at.x)
	enemies.spawn(type_id, maxi(1, wave), at)


func reset() -> void:
	wave = 0
	prep = Cfg.WAVE_PREP_TIME
	spawning = false
	all_cleared = false
	groups = []
	spawned_this_wave = 0
	total_this_wave = 0
	wave_elapsed = 0.0


## 本波剩余待生成数量
func remaining_to_spawn() -> int:
	return maxi(0, total_this_wave - spawned_this_wave)
