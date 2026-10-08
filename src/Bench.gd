class_name Bench
extends RefCounted
## 自动化测试 / 压测驱动。三种模式，全部脚本化、无需人工干预：
##
##   --bench                 （= waves）脚本化 AI 自动打完一整局，边打边采样性能，
##                            结束时校验经济账本，产出 自测/bench_result.txt + 自测/autoplay_log.txt
##   --bench-mode=ceiling    上限压测：全图铺塔 + 持续灌敌人，找本机的性能天花板
##   --bench-mode=soak       长稳测试：AI 连续对局并自动重开，检查是否崩溃/泄漏/掉帧
##
## 性能采样：dt 是游戏时间（受速度倍率影响），rdt 是真实墙钟时间。
## 绝对峰值 FPS 用 Engine.get_frames_per_second()（引擎真实值）；
## 另用「1 秒真实窗口内的帧数」计算窗口帧率，记录 ≥60 FPS 下的最大同屏规模。

var mode: String = "waves"
var duration: float = 90.0             # 墙钟秒；--soak 会被覆盖为 600
var t: float = 0.0
var done: bool = false

# ---- 绝对峰值 ----
var peak_enemies: int = 0
var peak_bullets: int = 0
var peak_fps: float = 0.0
var peak_load: int = -1
var peak_time: float = 0.0

# ---- ≥60 FPS 下的峰值（1 秒真实窗口）----
var best60_enemies: int = 0
var best60_bullets: int = 0
var best60_fps: float = 0.0

var min_fps_recent: float = 9999.0
var fps_sum: float = 0.0
var fps_samples: int = 0

var lines: PackedStringArray = PackedStringArray()
var checks: PackedStringArray = PackedStringArray()
var _rng := RandomNumberGenerator.new()
var _sample_timer: float = 0.0
var _shot_timer: float = 0.0
var _shot_index: int = 0

# ---- 1 秒窗口 ----
var _win_t: float = 0.0
var _win_frames: int = 0
var _win_peak_e: int = 0
var _win_peak_b: int = 0

# ---- 内存 / 长稳 ----
var _mem_first: int = 0
var _mem_last: int = 0
var _restarts: int = 0
var _max_node_count: int = 0

# ---- AI 状态 ----
var _ai_timer: float = 0.0
var _ai_build_n: int = 0
var _ai_type_i: int = 0
var _ai_ran_edge: bool = false
var _ai_sold_at_wave: int = -1
var _ai_up_i: int = 0
var _up_check_left: int = 3
var _build_check_left: int = 3

# ---- ceiling 模式 ----
var _flood_timer: float = 0.0
var _flood_batch: int = 120
var _cell_pool: PackedInt32Array = PackedInt32Array()
var _pool_cursor: int = 0

const _AI_MAX_TOWERS := 140
const _AI_TYPES: Array[int] = [0, 2, 1, 0, 1, 2, 0, 2, 1, 0]


func _init() -> void:
	_rng.seed = 424242


# ================================================================== 主入口
func update(dt: float, rdt: float, game) -> void:
	if done:
		return
	t += rdt

	if mode == "ceiling":
		_ceiling_tick(dt, game)
	elif mode == "soak":
		_soak_tick(rdt, game)
	else:
		_waves_tick(rdt, game)

	_sample(rdt, game)

	if t >= duration:
		_finish(game)


func _sample(rdt: float, game) -> void:
	var e: int = game.enemies.n_alive
	var b: int = game.bullets.n_alive
	var fps: float = Engine.get_frames_per_second()
	var load: int = e + b
	if load > peak_load:
		peak_load = load
		peak_enemies = e
		peak_bullets = b
		peak_fps = fps
		peak_time = t
	if t > 5.0:
		min_fps_recent = minf(min_fps_recent, fps)
	fps_sum += fps
	fps_samples += 1

	# 1 秒真实窗口：窗口内取各计数最大值，窗口平均帧率 ≥ 60 才算数
	_win_t += rdt
	_win_frames += 1
	_win_peak_e = maxi(_win_peak_e, e)
	_win_peak_b = maxi(_win_peak_b, b)
	if _win_t >= 1.0:
		var wf: float = float(_win_frames) / _win_t
		if wf >= 60.0 and (_win_peak_e + _win_peak_b) > (best60_enemies + best60_bullets):
			best60_enemies = _win_peak_e
			best60_bullets = _win_peak_b
			best60_fps = wf
		_win_t = 0.0
		_win_frames = 0
		_win_peak_e = 0
		_win_peak_b = 0

	_sample_timer -= rdt
	if _sample_timer <= 0.0:
		_sample_timer = 2.0
		_mem_last = OS.get_static_memory_usage()
		if _mem_first == 0:
			_mem_first = _mem_last
		_max_node_count = maxi(_max_node_count, Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		lines.append("t=%6.1f wave=%2d enemies=%5d bullets=%5d towers=%4d gold=%6d lives=%3d fps=%6.1f fired=%6d kills=%5d mem=%.1fMB" % [
			t, game.waves.wave, e, b, game.towers.n_alive, game.gold, game.lives, fps,
			game.bullets.total_fired, game.kills, float(_mem_last) / 1048576.0])

	_shot_timer -= rdt
	if _shot_timer <= 0.0:
		_shot_timer = 25.0
		_screenshot(game, "%s_%02d" % [mode, _shot_index])


# ================================================================== 脚本化 AI 对局
func _waves_tick(rdt: float, game) -> void:
	if game.state != 0:
		_finish(game)
		return
	if not _ai_ran_edge and t > 0.5:
		_ai_ran_edge = true
		_edge_checks(game)
	if game.speed_idx != 2:
		game.cycle_speed()
	_ai(rdt, game)


func _soak_tick(rdt: float, game) -> void:
	if game.state != 0:
		_restarts += 1
		game.restart()
		# 重开即"新的一局"，AI 的局内状态必须整体归零，否则下一局会带着上一局的
		# 进度继续（曾经只重置了 3 个变量，导致后续局面与首局不一致）。
		_ai_timer = 0.0
		_ai_build_n = 0
		_ai_type_i = 0
		_ai_up_i = 0
		_ai_sold_at_wave = -1
		_build_check_left = 3
		_up_check_left = 3
		return
	if game.speed_idx != 2:
		game.cycle_speed()
	_ai(rdt, game)


## 每 0.2 秒决策一次：开波 -> 建塔 -> 升级 -> 中途卖出一次
func _ai(rdt: float, game) -> void:
	_ai_timer -= rdt
	if _ai_timer > 0.0:
		return
	_ai_timer = 0.20

	if game.waves.can_start_next():
		game.start_next_wave()

	# 中途卖一次塔，验证退款路径与账本
	if _ai_sold_at_wave < 0 and game.waves.wave >= 5 and game.towers.n_alive > 6:
		_ai_sold_at_wave = game.waves.wave
		for i in game.towers._high:
			if game.towers.alive[i] == 0:
				continue
			var sx: int = game.towers.cx[i]
			var sy: int = game.towers.cy[i]
			var stype: int = game.towers.ttype[i]
			var slv: int = game.towers.level[i]
			var expect: int = Cfg.sell_value(stype, slv)
			var before: int = game.gold
			if game.sell_tower(i):
				var got: int = game.gold - before
				checks.append("%s 第 %d 波卖出 %s L%d：应退 %d，实退 %d" % [
					"PASS" if got == expect else "FAIL", game.waves.wave,
					Cfg.TOWERS[stype]["name"], slv, expect, got])
				checks.append("%s 卖出后该格恢复可建 (%d,%d)" % [
					"PASS" if game.grid.can_build(sx, sy) else "FAIL", sx, sy])
			break

	# 建塔（按轮转顺序取"当前买得起"的第一种，绝不卡在买不起的类型上）
	if _ai_build_n < _AI_MAX_TOWERS:
		_ai_build_once(game)

	# 升级：金币有富余时，每个决策 tick 升一座
	if game.gold > 150:
		_ai_up_i = _ai_try_upgrade(game)


## 按轮转顺序找到第一种买得起的塔并建一座；成功返回 true
func _ai_build_once(game) -> bool:
	var cands := _ai_candidates(game)
	if cands.is_empty():
		return false
	for tt in _ai_type_order(game):
		if game.gold < int(Cfg.TOWERS[tt]["cost"]):
			continue
		for c in cands:
			if game.place_tower(c, tt):
				_ai_build_n += 1
				_ai_type_i = (tt + 1) % _AI_TYPES.size()
				if _build_check_left > 0:
					_build_check_left -= 1
					checks.append("%s 建造 %s 于 (%d,%d) 后账本平衡" % [
						"PASS" if game.ledger_balanced() else "FAIL",
						Cfg.TOWERS[tt]["name"], c.x, c.y])
				return true
		return false
	return false


## 出手顺序：钱不宽裕时一律按价格从便宜到贵买（弩塔 DPS/金币 最高，先把塔数铺上去
## 才有覆盖率）；只有明显富裕（500 金以上，此时覆盖率早就满了、多出来的钱没有别的
## 用途）才改用轮转顺序，保证三种塔都被覆盖到。
## 早先的判据是"够买最便宜 + 次便宜两座就轮转"，实测 320 金会被花成
## 弩塔50 + 冰塔75 + 炮塔110 + 弩塔50 = 285，只建出 4 座塔，覆盖率反而不如
## 纯按价格买（6 座弩塔），第 1 波必漏。
func _ai_type_order(game) -> Array[int]:
	var by_cost: Array[int] = []
	for t in Cfg.TOWER_COUNT:
		by_cost.append(t)
	by_cost.sort_custom(func(a, b): return int(Cfg.TOWERS[a]["cost"]) < int(Cfg.TOWERS[b]["cost"]))
	if game.gold >= 500:
		var rot: Array[int] = []
		for step in _AI_TYPES.size():
			rot.append(_AI_TYPES[(_ai_type_i + step) % _AI_TYPES.size()])
		return rot
	return by_cost


## 贪心覆盖选址：先沿路径把火力铺开，铺满之后继续加塔堆火力。
##
## 打分 = 「射程内还没被现有塔覆盖的路径点数」×1000 + 「射程内路径点总数」。
##   - 前一项保证开局几座塔不会挤在同一小段路径上（最早只按路径点数排序时，
##     三座塔全落在出生点旁边，敌人走开后全场开不了火，实测整波只开火 24 发）；
##   - 后一项是"铺满之后的兜底"：一旦整条路径都被覆盖，前一项全归零，排序退化成
##     "谁覆盖的路径点最多"，于是塔会继续往路径最密的段落上加，火力越堆越高
##     （只按前一项会在覆盖率满时直接返回空表，AI 建到 12 座就停手，第 5 波必漏）。
## 路径被塔挤到别处时 game.path_hint 会跟着更新，候选与打分也随之重算。
func _ai_candidates(game) -> Array[Vector2i]:
	var ph: PackedVector2Array = game.path_hint
	var empty: Array[Vector2i] = []
	if ph.is_empty():
		return empty
	var gw: int = Cfg.GW
	var gh: int = Cfg.GH
	# 打分用的标称射程：取三种塔的中位（弩塔 116），避免高估覆盖能力
	var nominal: float = float(Cfg.TOWERS[0]["range"])
	var n2: float = nominal * nominal

	# 1) 标记已被现有塔覆盖的路径点
	var covered := PackedByteArray()
	covered.resize(ph.size())
	var tw: Towers = game.towers
	for i in tw._high:
		if tw.alive[i] == 0:
			continue
		var tp: Vector2 = tw.pos_of(i)
		var rr: float = Cfg.tower_range(tw.ttype[i], tw.level[i])
		var rr2: float = rr * rr
		for k in ph.size():
			if covered[k] == 0 and tp.distance_squared_to(ph[k]) <= rr2:
				covered[k] = 1

	# 2) 给每个可建格打分
	var score := {}
	var enc := {}
	var seen_n: int = 0
	for k in ph.size():
		var unc: int = 0 if covered[k] == 1 else 1000
		var cx: int = int(ph[k].x / Cfg.CELL)
		var cy: int = int(ph[k].y / Cfg.CELL)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var x: int = cx + dx
				var y: int = cy + dy
				if x <= 0 or y <= 0 or x >= gw - 1 or y >= gh - 1:
					continue
				if not game.grid.can_build(x, y):
					continue
				if Cfg.cell_center(x, y).distance_squared_to(ph[k]) > n2:
					continue
				var key: int = y * gw + x
				if not score.has(key):
					score[key] = 0
					enc[key] = seen_n
					seen_n += 1
				score[key] = int(score[key]) + unc + 1
	if score.is_empty():
		return empty

	# 排序：分数从高到低；同分时按「沿路径出现的先后」保证结果确定（sort_custom 不稳定）
	var keys: Array = score.keys()
	keys.sort_custom(func(a, b):
		var sa: int = int(score[a])
		var sb: int = int(score[b])
		if sa != sb:
			return sa > sb
		return int(enc[a]) < int(enc[b]))
	var out: Array[Vector2i] = []
	for k in keys:
		out.append(Vector2i(int(k) % gw, int(k) / gw))
	return out


func _ai_try_upgrade(game) -> int:
	var tw: Towers = game.towers
	var n: int = tw._high
	if n == 0:
		return 0
	for step in n:
		var i: int = (_ai_up_i + step) % n
		if tw.alive[i] == 0 or tw.level[i] >= Cfg.MAX_TOWER_LEVEL:
			continue
		var lv: int = tw.level[i]
		var cost: int = Cfg.upgrade_cost(tw.ttype[i], lv)
		if game.gold < cost:
			continue
		var d0: float = Cfg.tower_damage(tw.ttype[i], lv)
		if game.upgrade_tower(i):
			var d1: float = Cfg.tower_damage(tw.ttype[i], tw.level[i])
			if _up_check_left > 0:
				_up_check_left -= 1
				checks.append("%s 升级 %s L%d->L%d：伤害 %.1f->%.1f，花费 %d，账本平衡=%s" % [
					"PASS" if (tw.level[i] == lv + 1 and d1 > d0 and game.ledger_balanced()) else "FAIL",
					Cfg.TOWERS[tw.ttype[i]]["name"], lv, tw.level[i], d0, d1, cost,
					str(game.ledger_balanced())])
			return (i + 1) % n
	return _ai_up_i


## 边界 / 非法操作 / 连续重复操作（脚本化断言）
##
## 这些探测会临时给钱、建塔、把金币抽干。做完之后必须把**金币和四个账本累计量
## 一起还原**，否则 waves 模式会白拿约 200 金、账本合计也被探测的流水污染，
## "AI 完整对局"就不是从标准起始金币打出来的了（曾经只还原金币、把它记进
## ledger_adjust，恒等式虽然成立，但收入/支出两栏是假的）。
func _edge_checks(game) -> void:
	var gold0: int = game.gold
	var inc0: int = game.ledger_income
	var spent0: int = game.ledger_spent
	var refund0: int = game.ledger_refund
	var adj0: int = game.ledger_adjust

	var wall := _find_wall_cell(game)
	if wall.x >= 0:
		checks.append("%s 在墙上建塔被拒 (%d,%d)" % [
			"PASS" if not game.place_tower(wall, 0) else "FAIL", wall.x, wall.y])
	checks.append("%s 越界格建塔被拒 (-1,5)" % [
		"PASS" if not game.place_tower(Vector2i(-1, 5), 0) else "FAIL"])
	checks.append("%s 卖出不存在的塔被拒 (id=999999)" % [
		"PASS" if not game.sell_tower(999999) else "FAIL"])
	checks.append("%s 升级不存在的塔被拒 (id=999999)" % [
		"PASS" if not game.upgrade_tower(999999) else "FAIL"])
	checks.append("%s 卖出负数 id 被拒 (id=-1)" % [
		"PASS" if not game.sell_tower(-1) else "FAIL"])

	# 同一格连续快速重复建塔：只应成功一次，只扣一次钱
	# （先给足金币，否则会被"余额不足"掩盖掉真正要测的重复放置逻辑）
	var cell := _first_buildable(game)
	if cell.x >= 0:
		var probe_cost: int = int(Cfg.TOWERS[0]["cost"])
		game.add_gold(probe_cost * 4, "edge_probe")
		var g0: int = game.gold
		var ok: int = 0
		for r in 5:
			if game.place_tower(cell, 0):
				ok += 1
		var spent: int = g0 - game.gold
		checks.append("%s 同格连点 5 次：成功 %d 次（应 1），扣 %d 金（应 %d）" % [
			"PASS" if (ok == 1 and spent == probe_cost) else "FAIL",
			ok, spent, probe_cost])
		var tid: int = game.grid.tower_id_at(cell.x, cell.y)
		if tid >= 0:
			game.sell_tower(tid)

	# 金币耗尽时必须拒绝建造
	var drained: int = 0
	var g1: int = game.gold
	if g1 > 0 and game.try_spend(g1, "test_drain"):
		drained = g1
	var poor_refused: bool = true
	var probe := _first_buildable(game)
	if probe.x >= 0:
		poor_refused = not game.place_tower(probe, 1)
	checks.append("%s 金币为 0 时建塔被拒（余额 %d）" % [
		"PASS" if poor_refused else "FAIL", game.gold])
	if drained > 0:
		game.add_gold(drained, "test_restore")
	checks.append("%s 边界测试后账本仍平衡（余额 %d）" % [
		"PASS" if game.ledger_balanced() else "FAIL", game.gold])

	# 还原：金币 + 四个账本累计量。探测不能给 AI 白送钱，也不能留下假流水。
	game.gold = gold0
	game.ledger_income = inc0
	game.ledger_spent = spent0
	game.ledger_refund = refund0
	game.ledger_adjust = adj0


func _find_wall_cell(game) -> Vector2i:
	for y in Cfg.GH:
		for x in Cfg.GW:
			if game.grid.is_wall(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _first_buildable(game) -> Vector2i:
	for y in Cfg.GH:
		for x in Cfg.GW:
			if game.grid.can_build(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# ================================================================== 上限压测
func _ceiling_tick(dt: float, game) -> void:
	if _cell_pool.is_empty():
		_build_cell_pool(game)
	if game.speed_idx != 2:
		game.cycle_speed()
	# 纯吞吐压测：不漏怪掉命，否则 state 变成 LOST 后 place_tower 会全部被拒
	game.lives = Cfg.START_LIVES

	_ai_timer -= dt
	if _ai_timer <= 0.0:
		_ai_timer = 0.05
		game.add_gold(4000, "ceiling")
		# 全图均匀铺塔（不只贴路径），让子弹尽可能多
		for k in 4:
			if _pool_cursor >= _cell_pool.size():
				_pool_cursor = 0
			var c := Vector2i(_cell_pool[_pool_cursor] % Cfg.GW, _cell_pool[_pool_cursor] / Cfg.GW)
			_pool_cursor += 1
			game.place_tower(c, _AI_TYPES[_ai_type_i % _AI_TYPES.size()])
			_ai_type_i += 1

	# 持续灌敌人
	_flood_timer -= dt
	if _flood_timer <= 0.0:
		_flood_timer = 0.25
		_flood(game)


func _build_cell_pool(game) -> void:
	var tmp: Array[int] = []
	for y in Cfg.GH:
		for x in Cfg.GW:
			if game.grid.can_build(x, y):
				tmp.append(y * Cfg.GW + x)
	# 打散，保证铺塔位置均匀
	for i in range(tmp.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var s := tmp[i]
		tmp[i] = tmp[j]
		tmp[j] = s
	_cell_pool = PackedInt32Array(tmp)


func _flood(game) -> void:
	var n: int = _flood_batch
	for i in n:
		var cell := _random_open_cell(game)
		if cell.x < 0:
			return
		game.enemies.spawn(_rng.randi_range(0, 2), 6, Cfg.cell_center(cell.x, cell.y))
	if _flood_batch < 900:
		_flood_batch = int(_flood_batch * 1.35)


func _random_open_cell(game) -> Vector2i:
	for attempt in 40:
		var x := _rng.randi_range(1, Cfg.GW - 2)
		var y := _rng.randi_range(1, Cfg.GH - 2)
		if game.grid.is_open(x, y) and game.grid.tower_at[game.grid.idx(x, y)] < 0:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


# ================================================================== 收尾
func _screenshot(game, tag: String) -> void:
	# 无头模式没有真实渲染后端，取不到视口纹理，直接跳过（不算失败）
	if DisplayServer.get_name() == "headless":
		return
	var vp: Viewport = game.get_viewport()
	if vp == null:
		return
	var tex: ViewportTexture = vp.get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return
	img.save_png("res://自测/screenshots/%s.png" % tag)
	_shot_index += 1


func _finish(game) -> void:
	if done:
		return
	done = true
	_screenshot(game, "%s_final" % mode)
	var avg: float = fps_sum / maxf(1.0, float(fps_samples))
	var f := FileAccess.open("res://自测/bench_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_line("mode=%s wall_time=%.1fs duration=%.1fs" % [mode, t, duration])
		f.store_line("peak_load_time=%.1fs" % peak_time)
		f.store_line("peak: 同屏 %d 个敌人 + %d 发子弹, 当时 %.1f FPS" % [peak_enemies, peak_bullets, peak_fps])
		f.store_line("best_at_60fps: 同屏 %d 个敌人 + %d 发子弹, 窗口帧率 %.1f FPS" % [
			best60_enemies, best60_bullets, best60_fps])
		f.store_line("avg_fps=%.1f  min_fps_after_5s=%.1f" % [avg, min_fps_recent])
		f.store_line("towers=%d enemies_alive_at_end=%d max_nodes=%d" % [
			game.towers.n_alive, game.enemies.n_alive, _max_node_count])
		f.store_line("restarts=%d mem_first=%.1fMB mem_last=%.1fMB" % [
			_restarts, float(_mem_first) / 1048576.0, float(_mem_last) / 1048576.0])
		f.store_line("cpu_count=%d renderer=%s window=%s" % [OS.get_processor_count(),
			ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"),
			str(game.get_viewport().get_visible_rect().size)])
		f.store_line("--- samples ---")
		for line in lines:
			f.store_line(line)
		f.close()

	var a := FileAccess.open("res://自测/autoplay_log.txt", FileAccess.WRITE)
	if a != null:
		a.store_line("=== 脚本化 AI 对局（模式 %s）===" % mode)
		a.store_line("结果: %s" % ["胜利" if game.state == 1 else ("失败" if game.state == 2 else "未结束")])
		a.store_line("波次: %d/%d  游戏内用时: %.1fs  剩余命: %d  总击杀: %d  建塔总数: %d" % [
			game.waves.wave, Cfg.WAVE_COUNT, game.elapsed, game.lives, game.kills, game.towers.total_built])
		# 重开过的局（长稳模式）账本里会多一项「账外调整」：restart() 把金币强行拉回起始值，
		# 差额记进 ledger_adjust。ledger_balanced() 的恒等式是含这一项的，所以这里也必须打出来，
		# 否则长稳日志会印出「… = -116 ；当前金币 14 ；平衡=true」这种自相矛盾的一行。
		# 调整项为 0 时不打后缀，普通对局/压测的日志格式保持原样。
		var l_base: int = Cfg.START_GOLD + game.ledger_income - game.ledger_spent + game.ledger_refund
		var l_adj: int = game.ledger_adjust
		if l_adj == 0:
			a.store_line("经济账本: 初始 %d + 收入 %d - 支出 %d + 退款 %d = %d ；当前金币 %d ；平衡=%s" % [
				Cfg.START_GOLD, game.ledger_income, game.ledger_spent, game.ledger_refund,
				l_base, game.gold, str(game.ledger_balanced())])
		else:
			a.store_line("经济账本: 初始 %d + 收入 %d - 支出 %d + 退款 %d + 重开调整 %+d = %d ；当前金币 %d ；平衡=%s" % [
				Cfg.START_GOLD, game.ledger_income, game.ledger_spent, game.ledger_refund,
				l_adj, l_base + l_adj, game.gold, str(game.ledger_balanced())])
		a.store_line("--- 边界/异常/重复操作断言 ---")
		for c in checks:
			a.store_line(c)
		a.store_line("--- 每 2 秒采样 ---")
		for line in lines:
			a.store_line(line)
		a.close()

	if game.ledger_enabled:
		game._flush_ledger()

	print("[BENCH] mode=%s peak=%d enemies + %d bullets @ %.1f FPS ; best@60fps=%d+%d ; avg=%.1f ; balanced=%s" % [
		mode, peak_enemies, peak_bullets, peak_fps, best60_enemies, best60_bullets, avg,
		str(game.ledger_balanced())])
	game.get_tree().quit(0)
