extends Node2D
## 总控：拥有全部模块，推进模拟，管经济 / 生命 / 胜负 / 速度 / 输入 / 重开。

enum State { PLAYING, WON, LOST }

# ---- 模块 ----
var grid: MapGrid
var field: FlowField
var enemies: Enemies
var bullets: Bullets
var towers: Towers
var effects: Effects
var waves: Waves
var hash: SpatialHash
var audio: Audio
var renderer: Renderer
var hud
var bench: Bench = null

# ---- 经济 / 进度 ----
var gold: int = Cfg.START_GOLD
var lives: int = Cfg.START_LIVES
var kills: int = 0
var elapsed: float = 0.0
var speed_idx: int = 0
var state: int = State.PLAYING

# ---- 账本（用于"分毫不差"校验）----
var ledger_income: int = 0
var ledger_spent: int = 0
var ledger_refund: int = 0
var ledger_adjust: int = 0
var ledger_lines: PackedStringArray = PackedStringArray()
var ledger_enabled: bool = false

# ---- 交互 ----
var hover_cell: Vector2i = Vector2i(-1, -1)
var hover_valid: bool = false
var hover_color: Color = Cfg.C_HOVER_OK
var build_type: int = -1
var selected_tower: int = -1
var preview_range: float = 0.0
var preview_pos: Vector2 = Vector2.ZERO
var show_path_hint: bool = true
var path_hint: PackedVector2Array = PackedVector2Array()

var seed_value: int = Cfg.DEFAULT_SEED

# ---- 运行参数 ----
var ui_timer: float = 0.0
var auto_restart_test: bool = false
var _selftest: bool = false
var _uitest: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 20261008
	_parse_cmdline()
	_build_world()
	if _selftest:
		set_process(false)
		SelfTest.run(self)
		get_tree().quit(0)
		return
	if _uitest:
		var ut := UiTest.new()
		add_child(ut)
		ut.start(self)
		return
	set_process(true)


func _parse_cmdline() -> void:
	var args := OS.get_cmdline_args()
	for a in args:
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))
		elif a == "--selftest":
			_selftest = true
		elif a == "--uitest":
			_uitest = true
		elif a == "--ledger":
			ledger_enabled = true
		elif a == "--bench" or a == "--autoplay":
			bench = Bench.new()
			bench.mode = "waves"
		elif a.begins_with("--bench-mode="):
			if bench == null:
				bench = Bench.new()
			bench.mode = a.substr(13)
		elif a.begins_with("--bench-time="):
			if bench == null:
				bench = Bench.new()
			bench.duration = float(a.substr(13))
		elif a == "--soak":
			bench = Bench.new()
			bench.mode = "soak"
			bench.duration = 600.0
		elif a == "--ledger-full":
			ledger_enabled = true


func _build_world() -> void:
	grid = MapGrid.new()
	grid.generate(seed_value)
	field = FlowField.new(grid.w, grid.h)
	field.rebuild(grid, Cfg.GOAL_CELLS)

	enemies = Enemies.new()
	bullets = Bullets.new()
	towers = Towers.new()
	effects = Effects.new()
	waves = Waves.new()
	hash = SpatialHash.new(Cfg.VIEW_W, Cfg.VIEW_H, 48.0, Cfg.MAX_ENEMIES)

	if audio == null:
		audio = Audio.new(self)
	if renderer == null:
		renderer = Renderer.new()
		renderer.game = self
		add_child(renderer)
	if hud == null:
		hud = Hud.new()
		hud.name = "Hud"
		add_child(hud)
		hud.setup(self)

	renderer.bake_map(grid)
	_rebuild_path_hint()


func _rebuild_path_hint() -> void:
	path_hint = field.trace(grid, Cfg.SPAWN_CELLS[0])


func restart() -> void:
	towers.clear_all(grid)
	enemies = Enemies.new()
	bullets = Bullets.new()
	effects.clear()
	waves.reset()
	grid.generate(seed_value)
	field.rebuild(grid, Cfg.GOAL_CELLS)
	hash = SpatialHash.new(Cfg.VIEW_W, Cfg.VIEW_H, 48.0, Cfg.MAX_ENEMIES)
	renderer.bake_map(grid)
	_rebuild_path_hint()

	# 重开就是把金币强行拉回初始值。这属于"账外调整"，记一笔 ledger_adjust，
	# 否则账本恒等式会在重开后失效（长稳测试里表现为 balanced=false）。
	ledger_adjust += Cfg.START_GOLD - gold
	if ledger_enabled:
		ledger_lines.append("RESTART adjust %+d -> %d" % [Cfg.START_GOLD - gold, Cfg.START_GOLD])
	gold = Cfg.START_GOLD
	lives = Cfg.START_LIVES
	kills = 0
	elapsed = 0.0
	speed_idx = 0
	state = State.PLAYING
	build_type = -1
	selected_tower = -1
	preview_range = 0.0
	preview_pos = Vector2.ZERO
	hud.reset_ui()


# ------------------------------------------------------------------ 主循环
func _process(delta: float) -> void:
	var spd: float = Cfg.SPEEDS[speed_idx]
	var dt: float = minf(delta * spd, 0.05)
	step(dt)
	elapsed += dt

	# 塔一建/卖，全图路径都可能变
	if _path_dirty:
		_path_dirty = false
		_rebuild_path_hint()

	if bench != null:
		bench.update(dt, delta, self)

	if state == State.PLAYING:
		if waves.all_cleared and enemies.n_alive == 0:
			_finish(true)
		elif lives <= 0:
			_finish(false)

	_update_preview()
	renderer.render()

	ui_timer += delta
	if ui_timer >= 0.1:
		ui_timer = 0.0
		hud.refresh()


var _path_dirty: bool = false


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	enemies.begin_frame()

	hash.rebuild(enemies.pos, enemies.alive, enemies._high)
	towers.update(dt, grid, field, enemies, hash, bullets, _on_shot)
	bullets.update(dt, enemies, hash, effects)
	_process_kills()
	enemies.update(dt, grid, field, hash)
	_process_leaks()
	waves.update(dt, enemies, effects)
	effects.update(dt)


func _on_shot(tid: int, ttype: int) -> void:
	match ttype:
		1:
			audio.play("shoot2", _rng.randf_range(0.94, 1.08), -3.0)
		2:
			audio.play("shoot3", _rng.randf_range(0.96, 1.06), -6.0)
		_:
			audio.play("shoot", _rng.randf_range(0.95, 1.10), -4.0)


func _process_kills() -> void:
	var n := enemies.killed_count
	if n == 0:
		return
	for k in n:
		var i := enemies.killed_indices[k]
		var g := enemies.gold[i]
		kills += 1
		add_gold(g, "kill")
		var etype := enemies.etype[i]
		var col: Color = Cfg.ENEMIES[etype]["color"]
		effects.text(enemies.pos[i], "+%d" % g, Color(1.0, 0.92, 0.45))
		if etype == 3:
			effects.ring(enemies.pos[i], 10.0, 70.0, 0.45, Color(1.0, 0.35, 0.45))
			audio.play("boom", 0.7, 2.0)
		else:
			audio.play("hit", _rng.randf_range(0.9, 1.25), -10.0)


func _process_leaks() -> void:
	var n := enemies.leaked_count
	if n == 0:
		return
	for k in n:
		var i := enemies.leaked_indices[k]
		var d := enemies.life_dmg[i]
		lives -= d
		effects.text(Vector2(Cfg.VIEW_W - 70.0, 60.0), "-%d 命" % d, Color(1.0, 0.4, 0.4))
	audio.play("leak", 1.0, 0.0)
	ledger_lines.append("LEAK %d lives -> %d" % [n, lives])
	if lives <= 0:
		lives = 0


func _finish(win: bool) -> void:
	state = State.WON if win else State.LOST
	audio.play("win" if win else "lose", 1.0, 0.0)
	hud.show_result(win)
	if ledger_enabled:
		_flush_ledger()


# ------------------------------------------------------------------ 经济
func add_gold(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	gold += amount
	ledger_income += amount
	if ledger_enabled:
		ledger_lines.append("+%d %s -> %d" % [amount, reason, gold])


func try_spend(cost: int, reason: String) -> bool:
	if cost > gold:
		audio.play("deny", 1.0, -4.0)
		return false
	gold -= cost
	ledger_spent += cost
	if ledger_enabled:
		ledger_lines.append("-%d %s -> %d" % [cost, reason, gold])
	return true


func add_refund(amount: int, reason: String) -> void:
	if amount <= 0:
		return
	gold += amount
	ledger_refund += amount
	if ledger_enabled:
		ledger_lines.append("+%d %s(退款) -> %d" % [amount, reason, gold])


func ledger_balanced() -> bool:
	return Cfg.START_GOLD + ledger_income - ledger_spent + ledger_refund + ledger_adjust == gold


func _flush_ledger() -> void:
	var f := FileAccess.open("res://自测/economy_ledger.log", FileAccess.WRITE)
	if f == null:
		return
	f.store_line("start=%d income=%d spent=%d refund=%d adjust=%d final=%d balanced=%s" % [
		Cfg.START_GOLD, ledger_income, ledger_spent, ledger_refund, ledger_adjust, gold,
		str(ledger_balanced())])
	for line in ledger_lines:
		f.store_line(line)
	f.close()


# ------------------------------------------------------------------ 玩家动作
func can_afford(ttype: int) -> bool:
	return gold >= int(Cfg.TOWERS[ttype]["cost"])


func place_tower(cell: Vector2i, ttype: int) -> bool:
	if state != State.PLAYING:
		return false
	if not grid.can_build(cell.x, cell.y):
		return false
	# 预判：建了之后会不会把出生点彻底堵死
	if not FlowField.has_path(grid, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS, grid.idx(cell.x, cell.y)):
		audio.play("deny", 0.8, 0.0)
		hud.flash_message("这里会完全堵死通路，不能建")
		return false
	var cost := int(Cfg.TOWERS[ttype]["cost"])
	if not try_spend(cost, "build"):
		return false
	var tid := towers.place(grid, cell.x, cell.y, ttype)
	if tid < 0:
		add_refund(cost, "place_failed")
		return false
	field.rebuild(grid, Cfg.GOAL_CELLS)
	_path_dirty = true
	audio.play("build", _rng.randf_range(0.98, 1.05), 0.0)
	effects.ring(Cfg.cell_center(cell.x, cell.y), 6.0, 30.0, 0.3, Cfg.TOWERS[ttype]["color"])
	return true


func upgrade_tower(tid: int) -> bool:
	if state != State.PLAYING:
		return false
	if tid < 0 or tid >= towers.alive.size() or towers.alive[tid] == 0:
		return false
	var lv := towers.level[tid]
	if lv >= Cfg.MAX_TOWER_LEVEL:
		audio.play("deny", 1.2, -2.0)
		hud.flash_message("已经是最高等级")
		return false
	var cost: int = Cfg.upgrade_cost(towers.ttype[tid], lv)
	if not try_spend(cost, "upgrade"):
		return false
	towers.upgrade(tid)
	audio.play("upgrade", 1.0, 0.0)
	effects.ring(towers.pos_of(tid), 8.0, 34.0, 0.3, Cfg.TOWERS[towers.ttype[tid]]["accent"])
	hud.refresh()
	return true


func sell_tower(tid: int) -> bool:
	if state != State.PLAYING:
		return false
	if tid < 0 or tid >= towers.alive.size() or towers.alive[tid] == 0:
		return false
	var refund: int = Cfg.sell_value(towers.ttype[tid], towers.level[tid])
	towers.remove(grid, tid)
	add_refund(refund, "sell")
	field.rebuild(grid, Cfg.GOAL_CELLS)
	_path_dirty = true
	audio.play("sell", 1.0, 0.0)
	if selected_tower == tid:
		selected_tower = -1
		hud.close_panels()
	return true


func start_next_wave() -> bool:
	if state != State.PLAYING:
		return false
	if waves.start_next(enemies):
		audio.play("wave", 1.0, 0.0)
		hud.flash_message("第 %d 波来袭！" % waves.wave)
		return true
	return false


func cycle_speed() -> void:
	speed_idx = (speed_idx + 1) % Cfg.SPEEDS.size()
	hud.refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover(event.position)
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_arm_build(0)
			KEY_2:
				_arm_build(1)
			KEY_3:
				_arm_build(2)
			KEY_U:
				if selected_tower >= 0:
					upgrade_tower(selected_tower)
			KEY_X:
				if selected_tower >= 0:
					sell_tower(selected_tower)
			KEY_SPACE:
				start_next_wave()
			KEY_TAB:
				cycle_speed()
			KEY_R:
				if state != State.PLAYING:
					restart()
			KEY_ESCAPE:
				_cancel()


func _update_hover(mouse: Vector2) -> void:
	var c := Vector2i(int(mouse.x / Cfg.CELL), int(mouse.y / Cfg.CELL))
	if c != hover_cell:
		hover_cell = c
	if not grid.inb(c.x, c.y):
		hover_valid = false
		preview_range = 0.0
		return
	hover_valid = true
	var has_tower := grid.tower_id_at(c.x, c.y) >= 0
	if grid.can_build(c.x, c.y):
		hover_color = Cfg.C_HOVER_OK
	elif has_tower:
		hover_color = Color(1.0, 1.0, 1.0, 0.65)
	else:
		hover_color = Cfg.C_HOVER_BAD

	# 射程预览不在这里算：建造菜单 / 塔面板是 mouse_filter=STOP 的控件，
	# 鼠标停在它们上面时 InputEventMouseMotion 会被 GUI 吃掉，_unhandled_input 收不到，
	# 于是"悬停菜单项显示射程"就会失灵。改由 _process 每帧统一刷新（见 _update_preview）。


## 每帧刷新射程预览圈：手持塔时跟着光标格子；鼠标停在建造菜单某条目上时跟着待建格。
func _update_preview() -> void:
	if build_type >= 0 and hover_valid:
		preview_pos = Cfg.cell_center(hover_cell.x, hover_cell.y)
		preview_range = Cfg.tower_range(build_type, 1)
	elif hud != null and hud.hover_menu_type >= 0 and hud.pending_cell.x >= 0:
		preview_pos = Cfg.cell_center(hud.pending_cell.x, hud.pending_cell.y)
		preview_range = Cfg.tower_range(hud.hover_menu_type, 1)
	else:
		preview_range = 0.0


func _arm_build(ttype: int) -> void:
	if state != State.PLAYING:
		return
	if build_type == ttype:
		build_type = -1
		preview_range = 0.0
		return
	build_type = ttype
	hud.close_panels()
	hud.flash_message("已选择 %s（%d 金）— 左键点空地建造" % [Cfg.TOWERS[ttype]["name"], int(Cfg.TOWERS[ttype]["cost"])])


func _on_left_click(mouse: Vector2) -> void:
	_update_hover(mouse)
	if not hover_valid:
		_cancel()
		return
	var c := hover_cell
	var tid := grid.tower_id_at(c.x, c.y)
	if tid >= 0:
		selected_tower = tid
		build_type = -1
		hud.open_tower_panel(tid)
		return
	if grid.can_build(c.x, c.y):
		if build_type >= 0:
			if place_tower(c, build_type):
				pass
			return
		hud.open_build_menu(c)
		return
	_cancel()


func _cancel() -> void:
	build_type = -1
	selected_tower = -1
	preview_range = 0.0
	preview_pos = Vector2.ZERO
	hud.close_panels()


func enemy_count() -> int:
	return enemies.n_alive


func bullet_count() -> int:
	return bullets.n_alive
