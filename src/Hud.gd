class_name Hud
extends CanvasLayer
## 全部界面：顶栏 / 底栏按钮 / 建造菜单 / 塔信息面板 / 结算面板 / 提示条。
## 界面打开时游戏不暂停（Game._process 照跑）。

const TOP_H := 40.0
const BOT_H := 40.0

var game = null

var hover_menu_type: int = -1
var pending_cell: Vector2i = Vector2i(-1, -1)

var _top_bg: Panel
var _bottom_bg: Panel
var _lives: Label
var _gold: Label
var _wave: Label
var _sel: Label
var _enemy_lb: Label
var _fps: Label
var _btn_wave: Button
var _btn_speed: Button
var _toast: Label
var _toast_t: float = 0.0
var _hint: Label

var _build_menu: Panel
var _build_rows: Array[Button] = []
var _tower_panel: Panel
var _tp_title: Label
var _tp_stats: Label
var _tp_upgrade: Button
var _tp_sell: Button

var _result: Control
var _result_title: Label
var _result_stats: Label

var _icon_cache: Dictionary = {}


func _init() -> void:
	layer = 10


# ------------------------------------------------------------------ 构建
func setup(g) -> void:
	game = g
	_build_top()
	_build_bottom()
	_build_menu_panel()
	_build_tower_panel()
	_build_result()
	_build_toast()


func _panel_style(fill: Color, border: Color, radius: int = 8, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _button(b: Button, accent: Color) -> void:
	# 界面按钮一律不接收键盘焦点：否则点过按钮后焦点留在它身上，
	# 空格会被 GUI 当成 ui_accept 去"按"那个按钮、Tab 被当成 ui_focus_next 切焦点，
	# 游戏自己的「空格=下一波」「Tab=切速度」就收不到键了。
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _panel_style(Color(0.11, 0.14, 0.20, 0.95), Color(accent.r, accent.g, accent.b, 0.35), 6))
	b.add_theme_stylebox_override("hover", _panel_style(Color(0.17, 0.22, 0.31, 0.98), accent, 6))
	b.add_theme_stylebox_override("pressed", _panel_style(Color(0.09, 0.12, 0.17, 1.0), accent, 6))
	b.add_theme_stylebox_override("disabled", _panel_style(Color(0.09, 0.10, 0.13, 0.85), Color(0.22, 0.24, 0.30, 0.6), 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(0.42, 0.45, 0.52))
	b.add_theme_font_size_override("font_size", 14)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_top() -> void:
	_top_bg = Panel.new()
	_top_bg.position = Vector2(0, 0)
	_top_bg.size = Vector2(Cfg.VIEW_W, TOP_H)
	_top_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_top_bg.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.070, 0.102, 0.94), Color(0.16, 0.22, 0.32, 1.0), 0))
	add_child(_top_bg)

	_lives = _label("❤ 20", 18, Color(1.0, 0.42, 0.48))
	_lives.position = Vector2(14, 8)
	_top_bg.add_child(_lives)

	_gold = _label("◆ 165", 18, Color(1.0, 0.84, 0.36))
	_gold.position = Vector2(120, 8)
	_top_bg.add_child(_gold)

	_wave = _label("波次 0/12", 18, Color(0.70, 0.86, 1.0))
	_wave.position = Vector2(250, 8)
	_top_bg.add_child(_wave)

	_sel = _label("选中：无", 14, Color(0.66, 0.72, 0.84))
	_sel.position = Vector2(430, 11)
	_top_bg.add_child(_sel)

	_enemy_lb = _label("同屏 0", 18, Color(1.0, 0.66, 0.44))
	_enemy_lb.position = Vector2(Cfg.VIEW_W - 240, 8)
	_top_bg.add_child(_enemy_lb)

	_fps = _label("FPS 60", 18, Color(0.55, 1.0, 0.72))
	_fps.position = Vector2(Cfg.VIEW_W - 118, 8)
	_top_bg.add_child(_fps)


func _build_bottom() -> void:
	_bottom_bg = Panel.new()
	_bottom_bg.position = Vector2(0, Cfg.VIEW_H - BOT_H)
	_bottom_bg.size = Vector2(Cfg.VIEW_W, BOT_H)
	_bottom_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bottom_bg.add_theme_stylebox_override("panel", _panel_style(Color(0.055, 0.070, 0.102, 0.94), Color(0.16, 0.22, 0.32, 1.0), 0))
	add_child(_bottom_bg)

	_btn_wave = Button.new()
	_btn_wave.text = "开始下一波"
	_btn_wave.position = Vector2(14, 6)
	_btn_wave.size = Vector2(140, 28)
	_button(_btn_wave, Color(0.30, 0.90, 0.60))
	_btn_wave.pressed.connect(func(): game.start_next_wave())
	_bottom_bg.add_child(_btn_wave)

	_btn_speed = Button.new()
	_btn_speed.text = "速度 1×"
	_btn_speed.position = Vector2(162, 6)
	_btn_speed.size = Vector2(96, 28)
	_button(_btn_speed, Color(0.42, 0.72, 1.0))
	_btn_speed.pressed.connect(func(): game.cycle_speed())
	_bottom_bg.add_child(_btn_speed)

	_hint = _label("", 13, Color(0.55, 0.62, 0.74))
	_hint.position = Vector2(272, 12)
	_bottom_bg.add_child(_hint)
	_hint.text = "左键空地建塔 · 左键塔查看/升级 · 右键取消 · 1/2/3 选塔 · U 升级 · X 卖出 · 空格 下一波 · Tab 速度 · R 重开"


func _build_menu_panel() -> void:
	_build_menu = Panel.new()
	_build_menu.size = Vector2(268, 168)
	_build_menu.visible = false
	_build_menu.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.09, 0.13, 0.97), Color(0.30, 0.42, 0.60), 10, 2))
	add_child(_build_menu)

	var title := _label("建造菜单", 15, Color(0.85, 0.92, 1.0))
	title.position = Vector2(12, 8)
	_build_menu.add_child(title)

	for i in Cfg.TOWER_COUNT:
		var b := Button.new()
		b.position = Vector2(10, 34 + i * 42)
		b.size = Vector2(248, 38)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = _tower_icon(i)
		b.add_theme_constant_override("icon_max_width", 32)
		b.expand_icon = false
		_button(b, Cfg.TOWERS[i]["color"])
		b.pressed.connect(_on_menu_pick.bind(i))
		b.mouse_entered.connect(func(): hover_menu_type = i)
		b.mouse_exited.connect(func(): hover_menu_type = -1)
		_build_menu.add_child(b)
		_build_rows.append(b)


func _build_tower_panel() -> void:
	_tower_panel = Panel.new()
	_tower_panel.size = Vector2(272, 130)
	_tower_panel.visible = false
	_tower_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.09, 0.13, 0.97), Color(0.30, 0.42, 0.60), 10, 2))
	add_child(_tower_panel)

	_tp_title = _label("", 16, Color(1, 1, 1))
	_tp_title.position = Vector2(12, 8)
	_tower_panel.add_child(_tp_title)

	_tp_stats = _label("", 14, Color(0.72, 0.80, 0.92))
	_tp_stats.position = Vector2(12, 34)
	_tower_panel.add_child(_tp_stats)

	_tp_upgrade = Button.new()
	_tp_upgrade.position = Vector2(12, 90)
	_tp_upgrade.size = Vector2(122, 30)
	_button(_tp_upgrade, Color(0.36, 0.92, 0.62))
	_tp_upgrade.pressed.connect(func():
		if game.selected_tower >= 0:
			game.upgrade_tower(game.selected_tower))
	_tower_panel.add_child(_tp_upgrade)

	_tp_sell = Button.new()
	_tp_sell.position = Vector2(140, 90)
	_tp_sell.size = Vector2(120, 30)
	_button(_tp_sell, Color(1.0, 0.55, 0.45))
	_tp_sell.pressed.connect(func():
		if game.selected_tower >= 0:
			game.sell_tower(game.selected_tower))
	_tower_panel.add_child(_tp_sell)


func _build_result() -> void:
	_result = Control.new()
	_result.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result.mouse_filter = Control.MOUSE_FILTER_STOP
	_result.visible = false
	add_child(_result)

	var mask := ColorRect.new()
	mask.color = Color(0.02, 0.03, 0.05, 0.62)
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result.add_child(mask)

	_result_title = _label("", 64, Color.WHITE)
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.position = Vector2(0, 190)
	_result_title.size = Vector2(Cfg.VIEW_W, 80)
	_result.add_child(_result_title)

	_result_stats = _label("", 20, Color(0.86, 0.91, 1.0))
	_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_stats.position = Vector2(0, 300)
	_result_stats.size = Vector2(Cfg.VIEW_W, 120)
	_result.add_child(_result_stats)

	var hint := _label("按 R 键再来一局", 22, Color(0.60, 1.0, 0.78))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, 470)
	hint.size = Vector2(Cfg.VIEW_W, 40)
	_result.add_child(hint)


func _build_toast() -> void:
	_toast = _label("", 17, Color(1, 1, 1))
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(0, 52)
	_toast.size = Vector2(Cfg.VIEW_W, 28)
	_toast.visible = false
	add_child(_toast)


# ------------------------------------------------------------------ 图标（程序化）
func _tower_icon(ttype: int) -> ImageTexture:
	if _icon_cache.has(ttype):
		return _icon_cache[ttype] as ImageTexture
	var n := 34
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var def: Dictionary = Cfg.TOWERS[ttype]
	var col: Color = def["color"]
	var dark: Color = def["dark"]
	var accent: Color = def["accent"]
	var c := Vector2((n - 1) * 0.5, (n - 1) * 0.5)
	for y in n:
		for x in n:
			var p := Vector2(x, y)
			var d := p.distance_to(c)
			var out := Color(0, 0, 0, 0)
			if d <= 11.0:
				out = col
			elif d <= 13.0:
				out = dark
			# 炮管
			if x > int(c.x) and absf(y - c.y) < (float(n - 2 - x)) * 0.42:
				out = accent
			if d <= 4.0:
				out = dark
			if out.a > 0.0:
				img.set_pixel(x, y, out)
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[ttype] = tex
	return tex


# ------------------------------------------------------------------ 刷新
func refresh() -> void:
	if game == null:
		return
	_lives.text = "❤ %d" % game.lives
	_gold.text = "◆ %d" % game.gold
	if game.waves.wave == 0:
		_wave.text = "波次 0/%d" % Cfg.WAVE_COUNT
	else:
		_wave.text = "波次 %d/%d" % [game.waves.wave, Cfg.WAVE_COUNT]
	_enemy_lb.text = "同屏 %d" % game.enemies.n_alive
	_fps.text = "FPS %d" % Engine.get_frames_per_second()
	_sel.text = _selection_text()

	if game.waves.spawning:
		_btn_wave.text = "进行中…"
		_btn_wave.disabled = true
	elif game.waves.wave >= Cfg.WAVE_COUNT:
		_btn_wave.text = "已全部完成"
		_btn_wave.disabled = true
	else:
		_btn_wave.text = "开始下一波 (%.0fs)" % maxf(0.0, game.waves.prep)
		_btn_wave.disabled = false

	var s: float = Cfg.SPEEDS[game.speed_idx]
	_btn_speed.text = "速度 %s" % _speed_text(s)

	if _tower_panel.visible:
		_refresh_tower_panel()
	if _build_menu.visible:
		_refresh_build_rows()

	if _toast_t > 0.0:
		_toast_t -= 0.1
		_toast.modulate.a = clampf(_toast_t / 0.8, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false


func _speed_text(s: float) -> String:
	if is_equal_approx(s, 1.0):
		return "1×"
	elif is_equal_approx(s, 2.0):
		return "2×"
	return "3×"


func _selection_text() -> String:
	var parts := PackedStringArray()
	if game.build_type >= 0:
		parts.append("手持：%s (%d金)" % [Cfg.TOWERS[game.build_type]["name"], int(Cfg.TOWERS[game.build_type]["cost"])])
	if game.selected_tower >= 0 and game.selected_tower < game.towers.alive.size() and game.towers.alive[game.selected_tower] == 1:
		var t = game.towers
		var def: Dictionary = Cfg.TOWERS[t.ttype[game.selected_tower]]
		parts.append("选中：%s Lv.%d" % [def["name"], t.level[game.selected_tower]])
	if parts.is_empty():
		return "选中：无"
	return "   ·   ".join(parts)


func _refresh_build_rows() -> void:
	for i in _build_rows.size():
		var b := _build_rows[i]
		var cost := int(Cfg.TOWERS[i]["cost"])
		var afford: bool = int(game.gold) >= cost
		b.text = "  %s   ◆%d   %s" % [Cfg.TOWERS[i]["name"], cost, Cfg.TOWERS[i]["desc"]]
		b.disabled = not afford


func _refresh_tower_panel() -> void:
	var tid = game.selected_tower
	if tid < 0 or tid >= game.towers.alive.size() or game.towers.alive[tid] == 0:
		_tower_panel.visible = false
		return
	var t = game.towers
	var tt: int = t.ttype[tid]
	var lv: int = t.level[tid]
	var def: Dictionary = Cfg.TOWERS[tt]
	_tp_title.text = "%s   Lv.%d%s" % [def["name"], lv, "  (满级)" if lv >= Cfg.MAX_TOWER_LEVEL else ""]
	_tp_stats.text = "伤害 %.1f     射程 %.0f\n攻速 %.2f 次/秒" % [
		Cfg.tower_damage(tt, lv), Cfg.tower_range(tt, lv), Cfg.tower_rate(tt, lv)]
	var uc := Cfg.upgrade_cost(tt, lv)
	if lv >= Cfg.MAX_TOWER_LEVEL:
		_tp_upgrade.text = "已满级"
		_tp_upgrade.disabled = true
	else:
		_tp_upgrade.text = "升级 ◆%d" % uc
		_tp_upgrade.disabled = game.gold < uc
	_tp_sell.text = "卖出 +◆%d" % Cfg.sell_value(tt, lv)
	_tp_sell.disabled = false


# ------------------------------------------------------------------ 交互入口
func open_build_menu(cell: Vector2i) -> void:
	pending_cell = cell
	hover_menu_type = -1
	_build_menu.visible = true
	var p := Cfg.cell_center(cell.x, cell.y)
	var pos := p + Vector2(Cfg.CELL * 0.5 + 6.0, -_build_menu.size.y * 0.5)
	pos.x = clampf(pos.x, 8.0, Cfg.VIEW_W - _build_menu.size.x - 8.0)
	pos.y = clampf(pos.y, TOP_H + 8.0, Cfg.VIEW_H - BOT_H - _build_menu.size.y - 8.0)
	_build_menu.position = pos
	_refresh_build_rows()
	game.preview_pos = p
	game.preview_range = 0.0


func open_tower_panel(tid: int) -> void:
	_build_menu.visible = false
	hover_menu_type = -1
	_tower_panel.visible = true
	var t: Towers = game.towers
	var p: Vector2 = t.pos_of(tid)
	var pos: Vector2 = p + Vector2(Cfg.CELL * 0.5 + 6.0, -_tower_panel.size.y * 0.5)
	pos.x = clampf(pos.x, 8.0, Cfg.VIEW_W - _tower_panel.size.x - 8.0)
	pos.y = clampf(pos.y, TOP_H + 8.0, Cfg.VIEW_H - BOT_H - _tower_panel.size.y - 8.0)
	_tower_panel.position = pos
	_refresh_tower_panel()


func close_panels() -> void:
	_build_menu.visible = false
	_tower_panel.visible = false
	hover_menu_type = -1
	pending_cell = Vector2i(-1, -1)
	game.preview_range = 0.0


func _on_menu_pick(ttype: int) -> void:
	if pending_cell.x < 0:
		return
	game.place_tower(pending_cell, ttype)
	if game.gold >= int(Cfg.TOWERS[ttype]["cost"]):
		_refresh_build_rows()
	else:
		close_panels()


func flash_message(msg: String) -> void:
	_toast.text = msg
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_t = 1.6


func show_result(win: bool) -> void:
	close_panels()
	_result.visible = true
	_result_title.text = "胜  利" if win else "失  败"
	_result_title.add_theme_color_override("font_color",
		Color(0.45, 1.0, 0.66) if win else Color(1.0, 0.42, 0.46))
	var mins := int(game.elapsed) / 60
	var secs := int(game.elapsed) % 60
	_result_stats.text = "用时 %02d:%02d        剩余命数 %d\n总击杀 %d        建塔数 %d" % [
		mins, secs, maxi(0, game.lives), game.kills, game.towers.total_built]


func reset_ui() -> void:
	_result.visible = false
	close_panels()
	_toast.visible = false
	_toast_t = 0.0
	_refresh_build_rows()
