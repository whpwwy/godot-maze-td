class_name UiTest
extends Node
## 界面 / 交互自动化自测。
##
## 关键点：所有操作都通过 Viewport.push_input 注入真实的 InputEvent，
## 走的是和玩家点击、按键完全相同的输入链路（GUI 命中测试 -> _unhandled_input），
## 而不是直接调用内部函数。这样才测得到"按钮真的能点、键真的绑对了"。

var game = null

var _i: int = 0
var _frame: int = 0
var _lines: PackedStringArray = PackedStringArray()
var _pass: int = 0
var _fail: int = 0

# 跨步骤传递的状态
var _cell: Vector2i = Vector2i(-1, -1)
var _wall: Vector2i = Vector2i(-1, -1)
var _tid: int = -1
var _lv0: int = 0
var _gold0: int = 0
var _elapsed0: float = 0.0
var _sum0: float = 0.0
var _eidx: int = -1

const STEP_EVERY := 3   # 每 3 帧执行一步，给引擎留出刷新时间


func start(g) -> void:
	game = g
	name = "UiTest"
	_lines.append("=== 迷宫塔防 界面 / 交互自测（真实鼠标键盘事件）===")
	_lines.append("Godot %s   视口 %s" % [
		Engine.get_version_info()["string"], str(g.get_viewport().get_visible_rect().size)])


func _process(_d: float) -> void:
	_frame += 1
	if _frame % STEP_EVERY != 0:
		return
	if _i >= 22:
		_finish()
		return
	var n: int = _i
	_i += 1
	_step(n)


# ------------------------------------------------------------------ 断言
func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
	_lines.append("  [%s] %s%s" % ["PASS" if ok else "FAIL", what, ("  " + detail) if detail != "" else ""])


func _section(t: String) -> void:
	_lines.append("")
	_lines.append("--- %s ---" % t)


# ------------------------------------------------------------------ 输入注入
func _push(ev: InputEvent) -> void:
	get_viewport().push_input(ev, true)


func _move(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	_push(ev)


func _click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	_move(pos)
	var d := InputEventMouseButton.new()
	d.position = pos
	d.global_position = pos
	d.button_index = button
	d.pressed = true
	_push(d)
	var u := InputEventMouseButton.new()
	u.position = pos
	u.global_position = pos
	u.button_index = button
	u.pressed = false
	_push(u)


func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	_push(ev)


func _center(c: Vector2i) -> Vector2:
	return Cfg.cell_center(c.x, c.y)


func _hud():
	return game.hud


func _btn_pos(panel: Control, b: Button) -> Vector2:
	return panel.position + b.position + b.size * 0.5


func _pos_sum() -> float:
	var s := 0.0
	for i in game.enemies._high:
		if game.enemies.alive[i] == 1:
			s += game.enemies.pos[i].x * 0.37 + game.enemies.pos[i].y
	return s


# ------------------------------------------------------------------ 步骤
func _step(n: int) -> void:
	match n:
		0:
			_section("1. 悬停高亮")
			_cell = _find_buildable()
			_move(_center(_cell))
			_check(_cell.x >= 0, "找到可建造格", "(%d,%d)" % [_cell.x, _cell.y])
			_check(game.hover_valid, "悬停可建造格 -> hover_valid")
			_check(game.hover_color == Cfg.C_HOVER_OK, "可建造格高亮为「可建」色")
		1:
			_wall = _find_wall()
			_move(_center(_wall))
			_check(game.hover_valid, "悬停墙格 -> hover_valid")
			_check(game.hover_color == Cfg.C_HOVER_BAD, "墙格高亮为「不可建」色",
				"(%d,%d)" % [_wall.x, _wall.y])
		2:
			_section("2. 金币不足时选项不可选")
			_gold0 = game.gold
			# 清空金币（走正规经济入口，账本仍平衡）
			if _gold0 > 0:
				game.try_spend(_gold0, "uitest_drain")
			_move(_center(_cell))
			_click(_center(_cell))
			var m = _hud()._build_menu
			_check(m.visible, "左键点空地 -> 弹出建造菜单")
			_check(_hud()._build_rows.size() == Cfg.TOWER_COUNT,
				"菜单列出全部 %d 种塔" % Cfg.TOWER_COUNT, "实际 %d 行" % _hud()._build_rows.size())
			var all_disabled := true
			var txt_ok := true
			for b in _hud()._build_rows:
				if not b.disabled:
					all_disabled = false
				if b.text.find("◆") < 0:
					txt_ok = false
			_check(all_disabled, "金币为 0 时所有选项不可选（disabled）")
			_check(txt_ok, "每个选项都显示名称与价格")
			game.add_gold(3000, "uitest_restore")
			_hud()._refresh_build_rows()
			var any_enabled := false
			for b in _hud()._build_rows:
				if not b.disabled:
					any_enabled = true
			_check(any_enabled, "金币恢复后选项变为可选")
		3:
			_section("3. 悬停菜单项 -> 场上显示射程")
			var b0: Button = _hud()._build_rows[0]
			_move(_btn_pos(_hud()._build_menu, b0))
			_check(_hud().hover_menu_type == 0, "悬停第 1 个选项 -> hover_menu_type=0",
				"实际 %d" % _hud().hover_menu_type)
		4:
			# 射程预览由 Game._process 每帧刷新，这里等了三帧再看（模拟玩家真实停留）
			_check(game.preview_range > 0.0, "场上显示该塔射程圈", "半径 %.0f" % game.preview_range)
			_check(game.preview_pos != Vector2.ZERO, "射程圈画在待建格上",
				str(game.preview_pos))
			_section("4. 点击菜单项建造")
			_gold0 = game.gold
			var mb: Button = _hud()._build_rows[0]
			_click(_btn_pos(_hud()._build_menu, mb))
			_tid = game.grid.tower_id_at(_cell.x, _cell.y)
			_check(_tid >= 0, "点击选项 -> 在选中格建出塔", "id=%d" % _tid)
			_check(game.gold == _gold0 - int(Cfg.TOWERS[0]["cost"]),
				"建塔扣款 = 该塔价格（%d）" % int(Cfg.TOWERS[0]["cost"]),
				"%d -> %d" % [_gold0, game.gold])
		5:
			_section("5. 点击已有塔 -> 信息面板")
			_click(_center(_cell))
			var tp = _hud()._tower_panel
			_check(tp.visible, "左键点塔 -> 弹出信息面板")
			_check(game.selected_tower == _tid, "面板绑定到被点中的塔", "selected=%d" % game.selected_tower)
			var s: String = _hud()._tp_stats.text
			_check(s.find("伤害") >= 0 and s.find("射程") >= 0 and s.find("攻速") >= 0,
				"面板显示伤害 / 射程 / 攻速", s.replace("\n", "  "))
			_check(_hud()._tp_title.text.find("Lv.") >= 0, "面板显示等级", _hud()._tp_title.text)
			_check(_hud()._tp_upgrade.text.find("◆") >= 0, "升级按钮标价", _hud()._tp_upgrade.text)
			_check(_hud()._tp_sell.text.find("◆") >= 0, "卖出按钮标价", _hud()._tp_sell.text)
		6:
			_section("6. 升级按钮")
			_lv0 = game.towers.level[_tid]
			_gold0 = game.gold
			var exp := Cfg.upgrade_cost(game.towers.ttype[_tid], _lv0)
			_click(_btn_pos(_hud()._tower_panel, _hud()._tp_upgrade))
			_check(game.towers.level[_tid] == _lv0 + 1, "点升级 -> 等级 +1",
				"Lv%d -> Lv%d" % [_lv0, game.towers.level[_tid]])
			_check(game.gold == _gold0 - exp, "升级扣款 = 标价（%d）" % exp,
				"%d -> %d" % [_gold0, game.gold])
		7:
			_section("7. 卖出按钮")
			_gold0 = game.gold
			var lv: int = game.towers.level[_tid]
			var ttype: int = game.towers.ttype[_tid]
			var exp := Cfg.sell_value(ttype, lv)
			_check(_hud()._tp_sell.text.find("◆%d" % exp) >= 0, "卖出返还 = 标价（%d）" % exp,
				_hud()._tp_sell.text)
			_click(_btn_pos(_hud()._tower_panel, _hud()._tp_sell))
			_check(game.gold == _gold0 + exp, "卖出到账", "%d -> %d" % [_gold0, game.gold])
			_check(game.grid.tower_id_at(_cell.x, _cell.y) < 0, "卖出后该格恢复为空")
			_check(game.grid.can_build(_cell.x, _cell.y), "卖出后该格重新可建")
		8:
			_section("8. 右键关闭面板 / 取消选择")
			_click(_center(_cell))
			_check(_hud()._build_menu.visible, "再次点空地 -> 建造菜单打开（准备测试右键）")
			_click(_center(_cell), MOUSE_BUTTON_RIGHT)
			_check(not _hud()._build_menu.visible, "右键 -> 关闭建造菜单")
			_check(not _hud()._tower_panel.visible, "右键 -> 关闭塔信息面板")
			_check(game.build_type < 0 and game.selected_tower < 0, "右键 -> 清空选择状态")
		9:
			_section("9. 数字键 1/2/3 选塔")
			_key(KEY_1)
			_check(game.build_type == 0, "按 1 -> 选中弩塔", "build_type=%d" % game.build_type)
			_key(KEY_3)
			_check(game.build_type == 2, "按 3 -> 选中冰塔", "build_type=%d" % game.build_type)
			_key(KEY_2)
			_check(game.build_type == 1, "按 2 -> 选中炮塔", "build_type=%d" % game.build_type)
		10:
			_section("10. 手持塔 + 左键空地直接建造")
			_gold0 = game.gold
			var c2 := _find_buildable()
			_click(_center(c2))
			_check(game.grid.tower_id_at(c2.x, c2.y) >= 0, "手持塔时左键空地 -> 直接建塔",
				"(%d,%d)" % [c2.x, c2.y])
			_check(game.gold == _gold0 - int(Cfg.TOWERS[1]["cost"]), "扣款 = 炮塔价格",
				"%d -> %d" % [_gold0, game.gold])
			_key(KEY_2)   # 放下手里的塔
		11:
			_section("11. 键盘 U 升级 / X 卖出")
			var tid2: int = game.grid.tower_id_at(_cell.x, _cell.y)
			if tid2 < 0:
				_key(KEY_1)
				_click(_center(_cell))
				tid2 = game.grid.tower_id_at(_cell.x, _cell.y)
			_check(tid2 >= 0, "为 U/X 测试准备好一座塔", "id=%d" % tid2)
			game.selected_tower = tid2
			_lv0 = game.towers.level[tid2]
			_key(KEY_U)
			_check(game.towers.level[tid2] == _lv0 + 1, "按 U -> 升级选中的塔",
				"Lv%d -> Lv%d" % [_lv0, game.towers.level[tid2]])
			_gold0 = game.gold
			_key(KEY_X)
			_check(game.grid.tower_id_at(_cell.x, _cell.y) < 0, "按 X -> 卖出选中的塔")
			_check(game.gold > _gold0, "卖出后金币增加", "%d -> %d" % [_gold0, game.gold])
		12:
			_section("12. Tab 切换速度 1× / 2× / 3×")
			var s0: int = game.speed_idx
			_key(KEY_TAB)
			var s1: int = game.speed_idx
			_key(KEY_TAB)
			var s2: int = game.speed_idx
			_key(KEY_TAB)
			_check(s1 == (s0 + 1) % 3 and s2 == (s0 + 2) % 3 and game.speed_idx == s0,
				"Tab 在 1×/2×/3× 之间循环", "%d -> %d -> %d -> %d" % [s0, s1, s2, game.speed_idx])
			_check(_hud()._btn_speed.text.find("×") >= 0, "底栏速度按钮文字跟随", _hud()._btn_speed.text)
		13:
			_section("13. 空格开始下一波")
			var w0: int = game.waves.wave
			_key(KEY_SPACE)
			_check(game.waves.wave == w0 + 1, "空格 -> 开始下一波", "波次 %d -> %d" % [w0, game.waves.wave])
		14:
			_section("14. 点击底栏「速度」按钮")
			var before: int = game.speed_idx
			var btn: Button = _hud()._btn_speed
			_click(_hud()._bottom_bg.position + btn.position + btn.size * 0.5)
			_check(game.speed_idx == (before + 1) % 3, "点击速度按钮生效",
				"%d -> %d" % [before, game.speed_idx])
		15:
			_section("15. 界面打开时游戏不暂停")
			_click(_center(_cell), MOUSE_BUTTON_RIGHT)   # 先清掉手持状态
			var c3 := _find_buildable()
			_click(_center(c3))
			_check(_hud()._build_menu.visible, "建造菜单已打开")
			_check(not get_tree().paused, "打开界面时 scene tree 未暂停")
			# 手动放一只敌人，用来验证"敌人照走"
			_eidx = game.enemies.spawn(0, 1, Cfg.cell_center(Cfg.SPAWN_CELLS[0].x, Cfg.SPAWN_CELLS[0].y))
			_elapsed0 = game.elapsed
			_sum0 = _pos_sum()
			_check(_eidx >= 0 and game.enemies.n_alive > 0, "菜单打开期间敌人进入战场",
				"同屏 %d" % game.enemies.n_alive)
		16:
			_check(game.elapsed > _elapsed0, "菜单打开期间游戏时间仍在推进",
				"%.2f -> %.2f" % [_elapsed0, game.elapsed])
			_check(absf(_pos_sum() - _sum0) > 0.01, "菜单打开期间敌人确实在移动（位置变了）",
				"坐标和 %.2f -> %.2f" % [_sum0, _pos_sum()])
			_click(_center(_cell), MOUSE_BUTTON_RIGHT)
		17:
			_section("16. 右上角 FPS / 同屏敌人数为真实值")
			_hud().refresh()
			var f: int = Engine.get_frames_per_second()
			_check(_hud()._fps.text == "FPS %d" % f, "FPS 文本 == Engine.get_frames_per_second()",
				"%s vs %d" % [_hud()._fps.text, f])
			_check(_hud()._enemy_lb.text == "同屏 %d" % game.enemies.n_alive,
				"同屏敌人数文本 == enemies.n_alive", _hud()._enemy_lb.text)
		18:
			_section("17. 结算面板")
			game._finish(false)
			_check(game.state == 2, "失败后进入 LOST 状态")
			_check(_hud()._result.visible, "结算面板弹出")
			_check(_hud()._result_title.text.find("失") >= 0, "居中大字显示胜负",
				_hud()._result_title.text.replace(" ", ""))
			var st: String = _hud()._result_stats.text
			_check(st.find("用时") >= 0 and st.find("剩余命数") >= 0 and st.find("总击杀") >= 0
				and st.find("建塔数") >= 0, "显示用时 / 剩余命数 / 总击杀 / 建塔数", st.replace("\n", "  "))
		19:
			_section("18. R 键重开")
			_gold0 = game.gold
			_key(KEY_R)
			_check(game.state == 0, "结算面板上按 R -> 重开")
			_check(not _hud()._result.visible, "重开后结算面板隐藏")
			_check(game.gold == Cfg.START_GOLD, "重开后金币回到初始值",
				"%d -> %d" % [_gold0, game.gold])
			_check(not _hud()._build_menu.visible and not _hud()._tower_panel.visible,
				"重开后无残留面板")
		20:
			_section("19. 游戏中按 R 不误触发重开")
			_gold0 = game.gold
			_key(KEY_R)
			_check(game.state == 0 and game.gold == _gold0, "游戏中按 R 无副作用",
				"金币 %d" % game.gold)
		21:
			_check(true, "全部界面交互步骤执行完毕")


func _find_buildable() -> Vector2i:
	for y in range(2, Cfg.GH - 2):
		for x in range(2, Cfg.GW - 2):
			if game.grid.can_build(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _find_wall() -> Vector2i:
	for y in range(1, Cfg.GH - 1):
		for x in range(1, Cfg.GW - 1):
			if game.grid.is_wall(x, y):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# ------------------------------------------------------------------ 收尾
func _finish() -> void:
	_lines.append("")
	_lines.append("结果：通过 %d 项，失败 %d 项" % [_pass, _fail])
	_lines.append("UITEST_RESULT=%s" % ("PASS" if _fail == 0 else "FAIL"))
	var f := FileAccess.open("res://自测/uitest_log.txt", FileAccess.WRITE)
	if f != null:
		for l in _lines:
			f.store_line(l)
		f.close()
	print("[UITEST] pass=%d fail=%d" % [_pass, _fail])
	get_tree().quit(0)
