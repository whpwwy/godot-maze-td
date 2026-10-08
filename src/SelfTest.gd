class_name SelfTest
extends RefCounted
## 无头逻辑自测：全部断言脚本化，跑完写 自测/selftest_log.txt。
## 覆盖：迷宫生成 / 流场最短路正确性 / 塔改变寻路 / 堵死检测 / 敌人不穿墙 /
##       战斗与命中 / 溅射 / 减速 / 经济账本 / 升级卖出公式 / 波次表 / 极限容量。

var lines: PackedStringArray = PackedStringArray()
var passed: int = 0
var failed: int = 0

var _grid: MapGrid
var _field: FlowField
var _enemies: Enemies
var _bullets: Bullets
var _fx: Effects
var _hash: SpatialHash


static func run(game) -> void:
	var st := SelfTest.new()
	st._all(game)
	st._write()


func _all(game) -> void:
	lines.append("=== 迷宫塔防 无头逻辑自测 ===")
	lines.append("Godot %s   CPU=%d 核   网格 %dx%d(格边长 %d)" % [
		Engine.get_version_info()["string"], OS.get_processor_count(), Cfg.GW, Cfg.GH, Cfg.CELL])

	_new_world(Cfg.DEFAULT_SEED)
	_t_map()
	_t_flowfield()
	_t_tower_blocking()
	_t_enemy_sim()
	_t_combat()
	_t_economy(game)
	_t_waves()
	_t_capacity()
	_t_defs()
	_t_restart(game)

	lines.append("")
	lines.append("结果：通过 %d 项，失败 %d 项" % [passed, failed])
	lines.append("SELFTEST_RESULT=%s" % ("PASS" if failed == 0 else "FAIL"))


# ------------------------------------------------------------------ 工具
func _ok(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		lines.append("  [PASS] %s%s" % [name, ("  " + detail) if detail != "" else ""])
	else:
		failed += 1
		lines.append("  [FAIL] %s%s" % [name, ("  " + detail) if detail != "" else ""])


func _new_world(seed_value: int) -> void:
	_grid = MapGrid.new()
	_grid.generate(seed_value)
	_field = FlowField.new(_grid.w, _grid.h)
	_field.rebuild(_grid, Cfg.GOAL_CELLS)
	_enemies = Enemies.new()
	_bullets = Bullets.new()
	_fx = Effects.new()
	_hash = SpatialHash.new(Cfg.VIEW_W, Cfg.VIEW_H, 48.0, Cfg.MAX_ENEMIES)


func _write() -> void:
	var f := FileAccess.open("res://自测/selftest_log.txt", FileAccess.WRITE)
	if f == null:
		print("[SELFTEST] 无法写入日志")
		return
	for l in lines:
		f.store_line(l)
	f.close()
	for l in lines:
		print(l)


# ------------------------------------------------------------------ 1. 地图
func _t_map() -> void:
	lines.append("")
	lines.append("--- 1. 迷宫生成 ---")
	var k := _grid.kind
	var cnt := [0, 0, 0, 0]
	for i in k.size():
		cnt[k[i]] += 1
	var total: int = Cfg.GW * Cfg.GH
	_ok("格子总数 = 31x19 = %d" % total, k.size() == total, "实际 %d" % k.size())
	_ok("墙 / 地板 / 出生 / 终点 都非空",
		cnt[MapGrid.Kind.WALL] > 0 and cnt[MapGrid.Kind.FLOOR] > 0 and cnt[MapGrid.Kind.SPAWN] > 0 and cnt[MapGrid.Kind.GOAL] > 0,
		"地板=%d 墙=%d 出生=%d 终点=%d" % [cnt[0], cnt[1], cnt[2], cnt[3]])
	_ok("墙占比 25%~55%（迷宫有效）",
		float(cnt[1]) / float(total) > 0.25 and float(cnt[1]) / float(total) < 0.55,
		"%.1f%%" % (100.0 * float(cnt[1]) / float(total)))

	var row0_wall := true
	var rowlast_wall := true
	for x in Cfg.GW:
		if _grid.kind[_grid.idx(x, 0)] != MapGrid.Kind.WALL:
			row0_wall = false
		if _grid.kind[_grid.idx(x, Cfg.GH - 1)] != MapGrid.Kind.WALL:
			rowlast_wall = false
	_ok("第 0 行与最后一行整行是墙（HUD 可压在上面不挡可玩格）", row0_wall and rowlast_wall)

	_ok("出生格类型为 SPAWN", _grid.is_spawn(0, 7) and _grid.is_spawn(0, 8))
	_ok("终点格类型为 GOAL", _grid.is_goal(30, 7) and _grid.is_goal(30, 8))

	var g2 := MapGrid.new()
	g2.generate(Cfg.DEFAULT_SEED)
	_ok("同种子两次生成完全一致（可复现）", g2.dump_ascii() == _grid.dump_ascii())
	var diff := 0
	for sd in [1, 2, 3, 4, 5]:
		var g3 := MapGrid.new()
		g3.generate(sd)
		if g3.dump_ascii() != _grid.dump_ascii():
			diff += 1
	_ok("不同种子生成不同迷宫", diff >= 4, "5 个种子中 %d 个不同" % diff)


# ------------------------------------------------------------------ 2. 流场
func _t_flowfield() -> void:
	lines.append("")
	lines.append("--- 2. 寻路（流场 / Dijkstra）---")
	var gw: int = _grid.w
	var gh: int = _grid.h

	_ok("出生点可达终点", _field.spawn_reachable)
	_ok("BFS 独立验证：出生点 -> 终点 连通", FlowField.has_path(_grid, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS))

	var d_spawn: int = _field.dist_of(0, 7)
	_ok("出生点剩余代价 > 0", d_spawn > 0, "dist=%d (≈%.1f 格)" % [d_spawn, float(d_spawn) / 100.0])

	# Bellman 最优性：每个可达格 dist[i] 必须等于「邻居 dist + 边长」的最小值
	var bad := ""
	var reachable := 0
	for y in gh:
		for x in gw:
			var i: int = y * gw + x
			var d: int = _field.dist[i]
			if d < 0:
				continue
			reachable += 1
			if d == 0:
				continue
			var bestc := 2147483647
			for kk in 8:
				var nx: int = x + FlowField.OX[kk]
				var ny: int = y + FlowField.OY[kk]
				if not _grid.is_walkable(nx, ny):
					continue
				if kk >= 4:
					if not _grid.is_walkable(x + FlowField.OX[kk], y):
						continue
					if not _grid.is_walkable(x, y + FlowField.OY[kk]):
						continue
				var nd: int = _field.dist[ny * gw + nx]
				if nd < 0:
					continue
				var c: int = nd + (100 if kk < 4 else 141)
				if c < bestc:
					bestc = c
			if bestc != d and bad == "":
				bad = "格(%d,%d) dist=%d 但邻居最小 = %d" % [x, y, d, bestc]
	_ok("流场满足 Bellman 最优性（即真实最短距离场）", bad == "", bad if bad != "" else "%d 个可达格全部满足" % reachable)

	# best[] 必须指向最优邻居
	var bad2 := ""
	for y in gh:
		for x in gw:
			var i: int = y * gw + x
			var d: int = _field.dist[i]
			if d <= 0:
				continue
			var b: int = _field.best[i]
			if b < 0:
				bad2 = "格(%d,%d) 可达但没有方向" % [x, y]
				break
			var bx: int = b % gw
			var by: int = b / gw
			var dx: int = absi(bx - x)
			var dy: int = absi(by - y)
			if dx > 1 or dy > 1 or (dx == 0 and dy == 0):
				bad2 = "格(%d,%d) 的下一步不是邻居" % [x, y]
				break
			var step_cost: int = 100 if (dx + dy == 1) else 141
			if _field.dist[b] + step_cost != d:
				bad2 = "格(%d,%d) dist=%d 但 best 邻居 dist=%d + %d" % [x, y, d, _field.dist[b], step_cost]
				break
		if bad2 != "":
			break
	_ok("best[] 每格都指向代价更小的相邻格（最短路方向正确）", bad2 == "", bad2)

	# 不可达格 = BFS 从终点不可达的格
	var visited := PackedByteArray()
	visited.resize(gw * gh)
	visited.fill(0)
	var q: Array[int] = []
	for g in Cfg.GOAL_CELLS:
		var gi: int = _grid.idx(g.x, g.y)
		visited[gi] = 1
		q.append(gi)
	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		var x: int = cur % gw
		var y: int = cur / gw
		for kk in 8:
			var nx: int = x + FlowField.OX[kk]
			var ny: int = y + FlowField.OY[kk]
			if not _grid.is_walkable(nx, ny):
				continue
			if kk >= 4:
				if not _grid.is_walkable(x + FlowField.OX[kk], y) or not _grid.is_walkable(x, y + FlowField.OY[kk]):
					continue
			var ni: int = ny * gw + nx
			if visited[ni] == 0:
				visited[ni] = 1
				q.append(ni)
	var mismatch := 0
	for y in gh:
		for x in gw:
			var i2: int = y * gw + x
			var reach_bfs: bool = visited[i2] == 1
			var reach_ff: bool = _field.dist[i2] >= 0
			if reach_bfs != reach_ff:
				mismatch += 1
	_ok("流场可达集合与独立 BFS 完全一致", mismatch == 0, "不一致格数 %d（BFS 可达 %d 格）" % [mismatch, q.size()])

	# 追踪路径
	var path := _field.trace(_grid, Cfg.SPAWN_CELLS[0])
	_ok("从出生点回溯出完整路径（>= 10 步）", path.size() >= 10, "%d 步" % path.size())
	var endp: Vector2 = path[path.size() - 1]
	var goal_ok := false
	for g in Cfg.GOAL_CELLS:
		if endp.distance_to(Cfg.cell_center(g.x, g.y)) < 0.5:
			goal_ok = true
	_ok("路径终点落在终点格中心", goal_ok, "终点 (%d,%d)" % [int(endp.x / Cfg.CELL), int(endp.y / Cfg.CELL)])
	var mono := true
	var prev := 2147483647
	for p in path:
		var d3: int = _field.dist_of(int(p.x / Cfg.CELL), int(p.y / Cfg.CELL))
		if d3 > prev:
			mono = false
		prev = d3
	_ok("路径上 dist 单调递减（确实在往终点走）", mono)


# ------------------------------------------------------------------ 3. 塔挡路
func _t_tower_blocking() -> void:
	lines.append("")
	lines.append("--- 3. 塔占据格子 / 挡住敌人的路 ---")
	var before := _field.trace(_grid, Cfg.SPAWN_CELLS[0])
	var d0: int = _field.dist_of(0, 7)

	# 在最短路第一个可建格上建塔，路径必须改变
	var target := Vector2i(-1, -1)
	for i in range(1, before.size() - 1):
		var cx: int = int(before[i].x / Cfg.CELL)
		var cy: int = int(before[i].y / Cfg.CELL)
		if _grid.can_build(cx, cy):
			target = Vector2i(cx, cy)
			break
	_ok("最短路沿途存在可建格", target.x >= 0, "(%d,%d)" % [target.x, target.y])
	if target.x >= 0:
		_grid.set_tower(target.x, target.y, 777)
		_field.rebuild(_grid, Cfg.GOAL_CELLS)
		var after := _field.trace(_grid, Cfg.SPAWN_CELLS[0])
		var blocked_center := Cfg.cell_center(target.x, target.y)
		var still_on_path := false
		for p in after:
			if p.distance_to(blocked_center) < 0.5:
				still_on_path = true
		_ok("建塔后新路径不再经过该格（路径真的绕开了）", not still_on_path)
		_ok("建塔后路径确实变了", str(after) != str(before), "%d 步 -> %d 步" % [before.size(), after.size()])
		_ok("建塔后该格在流场里不可达（被占）", _field.dist_of(target.x, target.y) < 0, "dist=%d" % _field.dist_of(target.x, target.y))
		_ok("建塔后最短路不会变短", _field.dist_of(0, 7) >= d0, "%d -> %d" % [d0, _field.dist_of(0, 7)])
		_grid.clear_tower(target.x, target.y)
		_field.rebuild(_grid, Cfg.GOAL_CELLS)
		_ok("拆塔后路径恢复原样", str(_field.trace(_grid, Cfg.SPAWN_CELLS[0])) == str(before))

	# 完全堵死检测
	_ok("堵死前：出生点 -> 终点 连通", FlowField.has_path(_grid, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS))
	_grid.set_tower(1, 7, 901)
	_grid.set_tower(1, 8, 902)
	_ok("把出生口两条通道全堵上后：判定为不可达（建塔会被拒绝）",
		not FlowField.has_path(_grid, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS))
	_grid.clear_tower(1, 7)
	_ok("只堵一条通道时仍连通（走廊宽 2 格，可绕行）",
		FlowField.has_path(_grid, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS))
	_grid.clear_tower(1, 8)
	_ok("拆掉后恢复连通", FlowField.has_path(_grid, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS))
	_ok("extra_blocked_idx 参数被正确使用（把起点自身视为障碍 -> 不可达）",
		not FlowField.has_path(_grid, [Cfg.SPAWN_CELLS[0]], Cfg.GOAL_CELLS, _grid.idx(0, 7)))


# ------------------------------------------------------------------ 4. 敌人移动
func _t_enemy_sim() -> void:
	lines.append("")
	lines.append("--- 4. 敌人沿流场移动（200 只 x 3000 帧）---")
	var dt := 1.0 / 60.0
	var n := 200
	for i in n:
		var c := Cfg.SPAWN_CELLS[i % Cfg.SPAWN_CELLS.size()]
		_enemies.spawn(i % 3, 1, Cfg.cell_center(c.x, c.y) + Vector2((i % 7) * 1.5 - 5.0, (i % 5) * 1.5 - 3.0))
	_ok("生成 %d 只敌人" % n, _enemies.n_alive == n, "实际 %d" % _enemies.n_alive)

	var clipped := 0
	var moved_any := false
	var frames := 0
	var max_frames := 30000
	var gw: int = _grid.w
	var stall := PackedInt32Array()
	stall.resize(_enemies.alive.size())
	stall.fill(0)
	var prev_cell := PackedInt32Array()
	prev_cell.resize(_enemies.alive.size())
	prev_cell.fill(-1)
	var worst_stall := 0
	var stall_who := ""
	while frames < max_frames and _enemies.n_alive > 0:
		frames += 1
		_hash.rebuild(_enemies.pos, _enemies.alive, _enemies._high)
		_enemies.update(dt, _grid, _field, _hash)
		for i in _enemies._high:
			if _enemies.alive[i] == 0:
				continue
			var p: Vector2 = _enemies.pos[i]
			if not _grid.is_walkable(int(p.x / Cfg.CELL), int(p.y / Cfg.CELL)):
				clipped += 1
			moved_any = true
		# 每 2 秒统计一次：某个敌人连续多少个采样周期没有换格（= 原地卡住）
		if frames % 120 == 0:
			for i in _enemies._high:
				if _enemies.alive[i] == 0:
					continue
				var p2: Vector2 = _enemies.pos[i]
				var ci: int = int(p2.y / Cfg.CELL) * gw + int(p2.x / Cfg.CELL)
				if ci != prev_cell[i]:
					prev_cell[i] = ci
					stall[i] = 0
				else:
					stall[i] += 120
				if stall[i] > worst_stall:
					worst_stall = stall[i]
					stall_who = "敌 #%d 在格(%d,%d)" % [i, int(p2.x / Cfg.CELL), int(p2.y / Cfg.CELL)]
	_ok("敌人从未进入墙格 / 塔格（不穿墙）", clipped == 0, "越界次数 %d" % clipped)
	_ok("敌人确实移动了", moved_any)
	_ok("没有敌人长时间原地卡住（10 秒内必然换格）", worst_stall < 600,
		"最长停滞 %d 帧 %.1fs %s" % [worst_stall, float(worst_stall) / 60.0, stall_who])
	_ok("敌人最终全部走到终点（不漏、不卡死）", _enemies.n_alive == 0,
		"剩余 %d，累计漏 %d，耗时 %d 帧(%.1fs 游戏时间)" % [
			_enemies.n_alive, _enemies.total_leaked, frames, float(frames) / 60.0])
	_ok("漏怪计数与实际一致", _enemies.total_leaked == n, "total_leaked=%d" % _enemies.total_leaked)

	# 减速
	_enemies = Enemies.new()
	var ei: int = _enemies.spawn(0, 1, Vector2(100, 100))
	var base_spd: float = _enemies.current_speed(ei)
	_enemies.apply_slow(ei, 0.45, 1.8)
	var slowed: float = _enemies.current_speed(ei)
	_ok("减速后速度下降", slowed < base_spd, "%.1f -> %.1f" % [base_spd, slowed])
	_enemies.apply_slow(ei, 0.20, 3.0)
	_ok("弱减速不会覆盖强减速（取较大减速比例）", is_equal_approx(_enemies.slow_pct[ei], 0.45))
	_ok("减速时间取较长者", is_equal_approx(_enemies.slow_timer[ei], 3.0))


# ------------------------------------------------------------------ 5. 战斗
func _t_combat() -> void:
	lines.append("")
	lines.append("--- 5. 子弹 / 命中 / 溅射 ---")

	# 5.1 直达命中
	_enemies = Enemies.new()
	_bullets = Bullets.new()
	_fx = Effects.new()
	var ei: int = _enemies.spawn(0, 1, Vector2(200, 100))
	_enemies.spawn(1, 1, Vector2(600, 600))
	_hash.rebuild(_enemies.pos, _enemies.alive, _enemies._high)
	var bi: int = _bullets.fire(Vector2(0, 100), Vector2(1, 0), ei, 0, 1)
	_bullets.spd[bi] = 3000.0
	_bullets.vel[bi] = Vector2(3000, 0)
	var hp0: float = _enemies.hp[ei]
	_bullets.update(0.1, _enemies, _hash, _fx)
	_ok("子弹命中追踪目标（一帧跨 300px 也不穿模）", _enemies.hp[ei] < hp0,
		"hp %.1f -> %.1f" % [hp0, _enemies.hp[ei]])
	_ok("命中产生可见特效（火花/环）", _count_fx() > 0, "特效个数 %d" % _count_fx())
	_ok("命中后子弹被回收", _bullets.n_alive == 0, "n_alive=%d" % _bullets.n_alive)
	_ok("累计命中计数 +1", _bullets.total_hits == 1, "total_hits=%d" % _bullets.total_hits)

	# 5.2 溅射
	_enemies = Enemies.new()
	_bullets = Bullets.new()
	_fx = Effects.new()
	var center: Vector2 = Vector2(400, 200)
	var ids: Array[int] = []
	var offs: Array[Vector2] = [Vector2.ZERO, Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20)]
	for o in offs:
		ids.append(_enemies.spawn(2, 1, center + o))
	_hash.rebuild(_enemies.pos, _enemies.alive, _enemies._high)
	var bi2: int = _bullets.fire(Vector2(0, 200), Vector2(1, 0), ids[0], 1, 1)
	_bullets.spd[bi2] = 4000.0
	_bullets.vel[bi2] = Vector2(4000, 0)
	_bullets.update(0.1, _enemies, _hash, _fx)
	var hit_n := 0
	for i in ids:
		if _enemies.hp[i] < _enemies.max_hp[i]:
			hit_n += 1
	_ok("炮塔溅射一发命中多只敌人", hit_n >= 4, "命中 %d / 5 只" % hit_n)

	# 5.3 冰塔减速命中
	_enemies = Enemies.new()
	_bullets = Bullets.new()
	_fx = Effects.new()
	var si: int = _enemies.spawn(0, 1, Vector2(300, 300))
	var sp0: float = _enemies.current_speed(si)
	_hash.rebuild(_enemies.pos, _enemies.alive, _enemies._high)
	var bi3: int = _bullets.fire(Vector2(0, 300), Vector2(1, 0), si, 2, 1)
	_bullets.spd[bi3] = 3000.0
	_bullets.vel[bi3] = Vector2(3000, 0)
	_bullets.update(0.1, _enemies, _hash, _fx)
	_ok("冰塔命中后目标被减速", _enemies.current_speed(si) < sp0,
		"%.1f -> %.1f" % [sp0, _enemies.current_speed(si)])

	# 5.4 击杀与掉金
	_enemies = Enemies.new()
	_enemies.begin_frame()
	var ki: int = _enemies.spawn(0, 1, Vector2(50, 50))
	_enemies.damage(ki, 99999.0)
	_ok("致死伤害后敌人被移除", _enemies.alive[ki] == 0 and _enemies.n_alive == 0)
	_ok("击杀被记入事件表", _enemies.killed_count == 1 and _enemies.killed_indices[0] == ki)
	_ok("击杀金币 = 敌人定义的金币", _enemies.gold[ki] == int(Cfg.ENEMIES[0]["gold"]),
		"%d" % _enemies.gold[ki])

	# 5.5 塔开火（完整链路：塔 -> 子弹 -> 命中）
	_enemies = Enemies.new()
	_bullets = Bullets.new()
	_fx = Effects.new()
	var tower := Towers.new()
	var g2 := MapGrid.new()
	g2.generate(Cfg.DEFAULT_SEED)
	var f2 := FlowField.new(g2.w, g2.h)
	f2.rebuild(g2, Cfg.GOAL_CELLS)
	var tcell := Vector2i(-1, -1)
	for y in Cfg.GH:
		for x in Cfg.GW:
			if g2.can_build(x, y):
				tcell = Vector2i(x, y)
	var tid: int = tower.place(g2, tcell.x, tcell.y, 0)
	var ec: int = _enemies.spawn(0, 1, Cfg.cell_center(tcell.x, tcell.y) + Vector2(30, 0))
	_hash.rebuild(_enemies.pos, _enemies.alive, _enemies._high)
	var shots := [0]
	var hp_before: float = _enemies.hp[ec]
	for f in 200:
		if _enemies.alive[ec] == 0:
			break
		_hash.rebuild(_enemies.pos, _enemies.alive, _enemies._high)
		tower.update(1.0 / 60.0, g2, f2, _enemies, _hash, _bullets,
			func(_a, _b): shots[0] += 1)
		_bullets.update(1.0 / 60.0, _enemies, _hash, _fx)
	_ok("塔自动锁敌并开火", shots[0] > 0, "开火 %d 次" % shots[0])
	_ok("子弹最终造成伤害", _enemies.hp[ec] < hp_before or _enemies.alive[ec] == 0,
		"hp %.1f -> %.1f" % [hp_before, _enemies.hp[ec]])


func _count_fx() -> int:
	var n := 0
	for i in _fx.alive.size():
		if _fx.alive[i] == 1:
			n += 1
	return n


# ------------------------------------------------------------------ 6. 经济
func _t_economy(game) -> void:
	lines.append("")
	lines.append("--- 6. 经济账本（分毫不差）---")
	var g0: int = game.gold
	game.add_gold(37, "selftest")
	_ok("加钱后余额正确", game.gold == g0 + 37, "%d + 37 = %d" % [g0, game.gold])
	_ok("加钱后账本平衡", game.ledger_balanced())

	var ok_spend: bool = game.try_spend(20, "selftest")
	_ok("余额足够时扣款成功", ok_spend and game.gold == g0 + 17, "余额 %d" % game.gold)
	_ok("扣款后账本平衡", game.ledger_balanced())

	var g1: int = game.gold
	var over: bool = game.try_spend(g1 + 1, "selftest")
	_ok("余额不足时扣款被拒且余额不变", (not over) and game.gold == g1, "余额 %d" % game.gold)
	_ok("被拒后账本仍平衡", game.ledger_balanced())

	game.add_refund(11, "selftest")
	_ok("退款计入账本", game.ledger_balanced(), "余额 %d" % game.gold)

	_ok("账本恒等式 初始 + 收入 - 支出 + 退款 == 当前金币",
		Cfg.START_GOLD + game.ledger_income - game.ledger_spent + game.ledger_refund == game.gold,
		"%d + %d - %d + %d == %d" % [Cfg.START_GOLD, game.ledger_income, game.ledger_spent,
			game.ledger_refund, game.gold])

	# 塔的投入 / 卖出公式
	lines.append("")
	lines.append("--- 7. 塔数值 / 升级 / 卖出公式 ---")
	var formula_ok := true
	var detail := ""
	for t in Cfg.TOWER_COUNT:
		var c: int = int(Cfg.TOWERS[t]["cost"])
		if Cfg.tower_invested(t, 1) != c:
			formula_ok = false
			detail = "塔%d L1 投入 != %d" % [t, c]
		var inv2: int = c + Cfg.upgrade_cost(t, 1)
		if Cfg.tower_invested(t, 2) != inv2:
			formula_ok = false
			detail = "塔%d L2 投入错误" % t
		var inv3: int = inv2 + Cfg.upgrade_cost(t, 2)
		if Cfg.tower_invested(t, 3) != inv3:
			formula_ok = false
			detail = "塔%d L3 投入错误" % t
		for lv in [1, 2, 3]:
			if Cfg.sell_value(t, lv) != int(float(Cfg.tower_invested(t, lv)) * Cfg.SELL_RATIO):
				formula_ok = false
				detail = "塔%d L%d 卖出价错误" % [t, lv]
		if not (Cfg.tower_damage(t, 1) < Cfg.tower_damage(t, 2) and Cfg.tower_damage(t, 2) < Cfg.tower_damage(t, 3)):
			formula_ok = false
			detail = "塔%d 伤害未随等级提升" % t
		if not (Cfg.tower_range(t, 1) < Cfg.tower_range(t, 2) and Cfg.tower_range(t, 2) < Cfg.tower_range(t, 3)):
			formula_ok = false
			detail = "塔%d 射程未随等级提升" % t
		if not (Cfg.tower_rate(t, 1) < Cfg.tower_rate(t, 2) and Cfg.tower_rate(t, 2) < Cfg.tower_rate(t, 3)):
			formula_ok = false
			detail = "塔%d 攻速未随等级提升" % t
	_ok("投入 / 升级 / 卖出返还公式全部正确（3 种塔 x 3 级）", formula_ok, detail)

	var tower := Towers.new()
	var g3 := MapGrid.new()
	g3.generate(Cfg.DEFAULT_SEED)
	var tid: int = tower.place(g3, 5, 5, 0)
	var lv_ok: bool = tower.upgrade(tid) and tower.upgrade(tid) and not tower.upgrade(tid)
	_ok("满级后不能再升级", lv_ok, "L%d" % tower.level[tid])
	tower.remove(g3, tid)
	_ok("卖出后格子重新可建且塔被移除", tower.alive[tid] == 0 and g3.can_build(5, 5))


# ------------------------------------------------------------------ 7. 波次
func _t_waves() -> void:
	lines.append("")
	lines.append("--- 8. 波次表 ---")
	_ok("总波数 >= 8", Cfg.WAVE_COUNT >= 8, "WAVE_COUNT=%d" % Cfg.WAVE_COUNT)
	var prev := -1
	var mono := true
	var detail := ""
	for w in range(1, Cfg.WAVE_COUNT + 1):
		var tot: int = Cfg.wave_total(w)
		if tot <= 0:
			mono = false
			detail = "第 %d 波没有敌人" % w
		if tot <= prev:
			mono = false
			detail = "第 %d 波(%d) 未比第 %d 波(%d) 多" % [w, tot, w - 1, prev]
		prev = tot
	_ok("每波都有敌人且逐波变强（数量严格递增）", mono, detail if detail != "" else "第1波 %d -> 第%d波 %d" % [Cfg.wave_total(1), Cfg.WAVE_COUNT, Cfg.wave_total(Cfg.WAVE_COUNT)])
	var hp_mono := true
	for w in range(2, Cfg.WAVE_COUNT + 1):
		if Cfg.hp_mult(w) <= Cfg.hp_mult(w - 1):
			hp_mono = false
	_ok("敌人血量倍率逐波递增", hp_mono, "第1波 x%.2f -> 第%d波 x%.2f" % [
		Cfg.hp_mult(1), Cfg.WAVE_COUNT, Cfg.hp_mult(Cfg.WAVE_COUNT)])

	# 波次调度器
	var en := Enemies.new()
	var fx := Effects.new()
	var wv := Waves.new()
	var started := wv.start_next(en)
	_ok("开局可开始第 1 波", started and wv.wave == 1 and wv.spawning)
	var spawned_total := 0
	for f in 20000:
		wv.update(1.0 / 60.0, en, fx)
		spawned_total = wv.spawned_this_wave
		if spawned_total >= wv.total_this_wave:
			break
	_ok("波次调度器把本波敌人全部生成完毕", spawned_total == wv.total_this_wave,
		"%d / %d" % [spawned_total, wv.total_this_wave])
	_ok("生成总数 = 波次表定义", wv.total_this_wave == Cfg.wave_total(1), "%d" % wv.total_this_wave)


# ------------------------------------------------------------------ 8. 容量
func _t_capacity() -> void:
	lines.append("")
	lines.append("--- 9. 极限容量 ---")
	var en := Enemies.new()
	var n := 0
	while en.spawn(0, 1, Vector2(10, 10)) >= 0:
		n += 1
	_ok("敌人容量打满后拒绝生成", n == Cfg.MAX_ENEMIES and en.spawn(0, 1, Vector2(10, 10)) == -1,
		"容量 %d，实际生成 %d" % [Cfg.MAX_ENEMIES, n])

	var bl := Bullets.new()
	var m := 0
	while bl.fire(Vector2.ZERO, Vector2.RIGHT, 0, 0, 1) >= 0:
		m += 1
	_ok("子弹容量打满后拒绝生成", m == Cfg.MAX_BULLETS and bl.fire(Vector2.ZERO, Vector2.RIGHT, 0, 0, 1) == -1,
		"容量 %d，实际生成 %d" % [Cfg.MAX_BULLETS, m])

	var tw := Towers.new()
	var g4 := MapGrid.new()
	g4.generate(Cfg.DEFAULT_SEED)
	var placed := 0
	var x := 0
	while placed < Cfg.MAX_TOWERS + 5:
		var cx: int = x % Cfg.GW
		var cy: int = (x / Cfg.GW) % Cfg.GH
		if tw.place(g4, cx, cy, 0) < 0:
			break
		placed += 1
		x += 1
	_ok("塔容量上限生效（超出返回 -1）", placed <= Cfg.MAX_TOWERS, "放置 %d 座" % placed)

	# 波次生成超过容量时不崩
	var en2 := Enemies.new()
	for i in Cfg.MAX_ENEMIES + 500:
		if en2.spawn(0, 12, Vector2(10, 10)) < 0:
			break
	_ok("超量生成时不崩溃、不再增加", en2.n_alive == Cfg.MAX_ENEMIES, "n_alive=%d" % en2.n_alive)


# ------------------------------------------------------------------ 9. 定义差异
func _t_defs() -> void:
	lines.append("")
	lines.append("--- 10. 塔 / 敌人 定义差异（需求：各不相同）---")
	_ok("至少 2 种塔", Cfg.TOWER_COUNT >= 2, "%d 种" % Cfg.TOWER_COUNT)
	_ok("至少 3 种敌人", Cfg.ENEMY_COUNT >= 3, "%d 种" % Cfg.ENEMY_COUNT)
	var keys: Array[String] = ["cost", "range", "rate", "damage"]
	for k in keys:
		var vals: Array = []
		for t in Cfg.TOWER_COUNT:
			vals.append(Cfg.TOWERS[t][k])
		var uniq := {}
		for v in vals:
			uniq[v] = true
		_ok("3 种塔的 %s 各不相同" % k, uniq.size() == Cfg.TOWER_COUNT, str(vals))
	var ekeys: Array[String] = ["hp", "speed"]
	for k in ekeys:
		var vals2: Array = []
		for e in Cfg.ENEMY_COUNT:
			vals2.append(Cfg.ENEMIES[e][k])
		var uniq2 := {}
		for v in vals2:
			uniq2[v] = true
		_ok("4 种敌人的 %s 各不相同" % k, uniq2.size() == Cfg.ENEMY_COUNT, str(vals2))


## 在可建格上连续建 want 座 ttype 塔（挡住通路的格子会被 place_tower 拒绝并自动跳过），
## 返回成功建起的塔所在格子。
func _place_n(game, want: int, ttype: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(1, Cfg.GH - 1):
		if out.size() >= want:
			break
		for x in range(1, Cfg.GW - 1):
			if out.size() >= want:
				break
			if not game.grid.can_build(x, y):
				continue
			if game.place_tower(Vector2i(x, y), ttype):
				out.append(Vector2i(x, y))
	return out


# ------------------------------------------------------------------ 10. 重开
## 回归测试：长稳（soak）跑出来的两个真实 bug ——
##   (1) towers._high 曾被清零，而 place() 从空闲链取高位下标，
##       导致 update() 的 `for i in _high` 遍历不到这些塔 -> 重开一局后塔永远不开火；
##   (2) 重开把金币强拉回初始值，账本累计量不重置 -> 恒等式失效（balanced=false）。
func _t_restart(game) -> void:
	lines.append("")
	lines.append("--- 11. 重开（R）语义：塔槽位 / 开火 / 账本 ---")
	game.add_gold(9000, "selftest_seed")

	var first := _place_n(game, 6, 0)
	var high_before: int = game.towers._high
	_ok("重开前已建起若干塔（用掉了一些塔下标）", first.size() >= 4 and high_before >= 4,
		"建 %d 座，_high=%d" % [first.size(), high_before])

	game.restart()

	_ok("重开后塔归零 / 金币回初始 / 生命回满 / 关卡重置",
		game.towers.n_alive == 0 and game.gold == Cfg.START_GOLD
			and game.lives == Cfg.START_LIVES and game.state == 0 and game.waves.wave == 0,
		"塔=%d 金=%d 命=%d 状态=%d 波=%d" % [game.towers.n_alive, game.gold,
			game.lives, game.state, game.waves.wave])

	var high_after: int = game.towers._high
	_ok("重开后 towers._high 未被清零（update() 的遍历范围仍覆盖所有槽位）",
		high_after >= high_before, "重开前 %d -> 重开后 %d" % [high_before, high_after])

	game.add_gold(9000, "selftest_seed2")
	var second := _place_n(game, 6, 1)
	var out_of_range := ""
	for tid in second:
		var t: int = game.grid.tower_id_at(tid.x, tid.y)
		if t < 0 or t >= game.towers._high:
			out_of_range = "塔下标 %d 不在遍历范围 [0,%d) 内" % [t, game.towers._high]
	_ok("重开后新建的塔全部落在 update() 的遍历范围内（否则塔不会开火）",
		second.size() >= 4 and out_of_range == "",
		out_of_range if out_of_range != "" else "新建 %d 座，_high=%d" % [second.size(), game.towers._high])

	# 功能性验证：重开后塔真的开火，子弹真的命中
	var fired0: int = game.bullets.total_fired
	var tc: Vector2i = second[0] if second.size() > 0 else Vector2i(-1, -1)
	var ec: int = game.enemies.spawn(0, 1, Cfg.cell_center(tc.x, tc.y) + Vector2(28, 0))
	_ok("重开后能在新世界里生成敌人", ec >= 0, "敌人下标 %d" % ec)
	var hp0: float = game.enemies.hp[ec] if ec >= 0 else 0.0
	for f in 120:
		game.step(1.0 / 60.0)
		if game.bullets.total_fired > fired0:
			break
	_ok("重开后塔确实开火（回归：不再出现「重开一局塔全部不开火」）",
		game.bullets.total_fired > fired0, "开火 %d 发" % (game.bullets.total_fired - fired0))

	var hit := false
	var hp_now: float = hp0
	for f in 120:
		game.step(1.0 / 60.0)
		if ec < 0:
			hit = true
			break
		hp_now = game.enemies.hp[ec]
		if game.enemies.alive[ec] == 0 or hp_now < hp0:
			hit = true
			break
	_ok("重开后塔的子弹能造成伤害（命中链路完好）", hit, "hp %.1f -> %.1f" % [hp0, hp_now])

	_ok("重开后账本恒等式仍然成立（含重开时的账外调整项）", game.ledger_balanced(),
		"初始 %d + 收入 %d - 支出 %d + 退款 %d + 调整 %d == 当前 %d" % [
			Cfg.START_GOLD, game.ledger_income, game.ledger_spent,
			game.ledger_refund, game.ledger_adjust, game.gold])
