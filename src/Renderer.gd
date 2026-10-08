class_name Renderer
extends Node2D
## 绘制层：只读游戏状态，负责把一切画出来。
##   · 静态迷宫 -> 开局烘焙成一张贴图，每帧只画 1 个 Sprite2D
##   · 敌人 / 血条 / 子弹 / 特效 -> MultiMeshInstance2D 实例化，一次 draw call 画完
##   · 塔 / 悬停高亮 / 射程圈 / 路线提示 / 飘字 -> 矢量 _draw

const QUAD := 1.0

var game = null

var _map_sprite: Sprite2D
var _mm_enemy: MultiMeshInstance2D
var _mm_hp: MultiMeshInstance2D
var _mm_bullet: MultiMeshInstance2D
var _mm_ring: MultiMeshInstance2D
var _mm_spark: MultiMeshInstance2D

var _tex_circle: ImageTexture
var _tex_ring: ImageTexture
var _tex_soft: ImageTexture
var _tex_white: ImageTexture

var font: Font

# 颜色查表：热循环里不做 Dictionary 取值
var _ecol: PackedColorArray = PackedColorArray()
var _bcol: PackedColorArray = PackedColorArray()


func _ready() -> void:
	z_index = 0
	font = ThemeDB.fallback_font
	for d in Cfg.ENEMIES:
		_ecol.append(d["color"])
	for d in Cfg.TOWERS:
		_bcol.append(d["accent"])
	_build_textures()
	_build_nodes()


# ------------------------------------------------------------------ 贴图（程序化）
func _circle_texture(px: int) -> ImageTexture:
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) * 0.5
	var r := px * 0.5 - 1.0
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length()
			var a := clampf((r - d) / 1.8, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _soft_texture(px: int) -> ImageTexture:
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) * 0.5
	var r := px * 0.5 - 1.0
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length()
			var a := clampf((r - d) / (r * 0.9), 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)


func _ring_texture(px: int, thickness_ratio: float) -> ImageTexture:
	var img := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) * 0.5
	var r := px * 0.5 - 1.0
	var th := r * thickness_ratio
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length()
			var outer := clampf((r - d) / 1.6, 0.0, 1.0)
			var inner := clampf((d - (r - th)) / 1.6, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, outer * inner))
	return ImageTexture.create_from_image(img)


func _white_texture() -> ImageTexture:
	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	return ImageTexture.create_from_image(img)


func _build_textures() -> void:
	_tex_circle = _circle_texture(64)
	_tex_soft = _soft_texture(64)
	_tex_ring = _ring_texture(64, 0.16)
	_tex_white = _white_texture()


func _make_mm(tex: Texture2D, cap: int, z: int) -> MultiMeshInstance2D:
	var qm := QuadMesh.new()
	qm.size = Vector2(QUAD, QUAD)
	qm.orientation = PlaneMesh.FACE_Z
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = qm
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = tex
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	if tex == _tex_white:
		node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.z_index = z
	node.z_as_relative = true
	add_child(node)
	return node


func _build_nodes() -> void:
	_map_sprite = Sprite2D.new()
	_map_sprite.centered = false
	_map_sprite.z_index = -20
	_map_sprite.z_as_relative = true
	_map_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_map_sprite)

	_mm_enemy = _make_mm(_tex_circle, Cfg.MAX_ENEMIES, -6)
	_mm_hp = _make_mm(_tex_white, 4096, -5)
	_mm_bullet = _make_mm(_tex_soft, Cfg.MAX_BULLETS, -4)
	_mm_ring = _make_mm(_tex_ring, Cfg.MAX_EFFECTS, -3)
	_mm_spark = _make_mm(_tex_soft, Cfg.MAX_EFFECTS, -2)


# ------------------------------------------------------------------ 地图烘焙
func bake_map(grid: MapGrid) -> void:
	var iw := Cfg.VIEW_W
	var ih := Cfg.VIEW_H
	var img := Image.create_empty(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Cfg.C_BG)
	var cell := Cfg.CELL
	for y in grid.h:
		for x in grid.w:
			var k := grid.kind[grid.idx(x, y)]
			var rx := x * cell
			var ry := y * cell
			match k:
				MapGrid.Kind.WALL:
					img.fill_rect(Rect2i(rx, ry, cell, cell), Cfg.C_WALL)
					img.fill_rect(Rect2i(rx + 3, ry + 3, cell - 6, cell - 6), Cfg.C_WALL_FACE)
					# 顶面高光：只有上方不是墙时才画，形成"砖块"层次
					if y == 0 or grid.kind[grid.idx(x, y - 1)] == MapGrid.Kind.WALL:
						img.fill_rect(Rect2i(rx + 2, ry + 1, cell - 4, 5), Cfg.C_WALL_TOP)
				MapGrid.Kind.FLOOR:
					img.fill_rect(Rect2i(rx, ry, cell, cell), Cfg.C_FLOOR)
					img.fill_rect(Rect2i(rx, ry, cell, 1), Cfg.C_FLOOR_LINE)
					img.fill_rect(Rect2i(rx, ry, 1, cell), Cfg.C_FLOOR_LINE)
				MapGrid.Kind.SPAWN:
					img.fill_rect(Rect2i(rx, ry, cell, cell), Cfg.C_FLOOR)
					img.fill_rect(Rect2i(rx, ry, cell, cell), Color(Cfg.C_SPAWN.r, Cfg.C_SPAWN.g, Cfg.C_SPAWN.b, 0.28))
					img.fill_rect(Rect2i(rx, ry, 5, cell), Cfg.C_SPAWN)
				MapGrid.Kind.GOAL:
					img.fill_rect(Rect2i(rx, ry, cell, cell), Cfg.C_FLOOR)
					img.fill_rect(Rect2i(rx, ry, cell, cell), Color(Cfg.C_GOAL.r, Cfg.C_GOAL.g, Cfg.C_GOAL.b, 0.28))
					img.fill_rect(Rect2i(rx + cell - 5, ry, 5, cell), Cfg.C_GOAL)
	var tex := ImageTexture.create_from_image(img)
	_map_sprite.texture = tex


# ------------------------------------------------------------------ 每帧
func render() -> void:
	_sync_enemies()
	_sync_bullets()
	_sync_effects()
	queue_redraw()


func _sync_enemies() -> void:
	var e: Enemies = game.enemies
	var mm := _mm_enemy.multimesh
	var mmh := _mm_hp.multimesh
	var k := 0
	var kh := 0
	var hp_cap := mmh.instance_count

	for i in e._high:
		if e.alive[i] == 0:
			continue
		var col: Color = _ecol[e.etype[i]]
		var f := e.flash[i]
		if f > 0.0:
			col = col.lerp(Color(1, 1, 1), f * 0.85)
		elif e.slow_timer[i] > 0.0:
			col = col.lerp(Color(0.45, 0.85, 1.0), 0.5)

		var r: float = e.radius[i]
		var d := r * 2.0
		mm.set_instance_transform_2d(k, Transform2D(0.0, Vector2(d, d), 0.0, e.pos[i]))
		mm.set_instance_color(k, col)
		k += 1

		# 只在受伤时画血条；数量有上限，保证极端情况下不爆
		var hp: float = e.hp[i]
		var mhp: float = e.max_hp[i]
		if hp < mhp and kh + 2 <= hp_cap:
			var w := maxf(16.0, r * 2.2)
			var ratio := clampf(hp / mhp, 0.0, 1.0)
			var top := e.pos[i] + Vector2(0.0, -r - 6.0)
			mmh.set_instance_transform_2d(kh, Transform2D(0.0, Vector2(w, 2.8), 0.0, top - Vector2(w * 0.5, 1.4)))
			mmh.set_instance_color(kh, Color(0.05, 0.06, 0.09, 0.85))
			kh += 1
			var bar_col := Color(0.25, 0.92, 0.48)
			if ratio < 0.35:
				bar_col = Color(1.0, 0.32, 0.32)
			elif ratio < 0.7:
				bar_col = Color(1.0, 0.80, 0.30)
			mmh.set_instance_transform_2d(kh, Transform2D(0.0, Vector2(maxf(0.5, w * ratio), 2.8), 0.0, top - Vector2(w * 0.5, 1.4)))
			mmh.set_instance_color(kh, bar_col)
			kh += 1

	mm.visible_instance_count = k
	mmh.visible_instance_count = kh


func _sync_bullets() -> void:
	var b: Bullets = game.bullets
	var mm := _mm_bullet.multimesh
	var k := 0
	for i in b._high:
		if b.alive[i] == 0:
			continue
		var d: float = b.radius[i] * 3.4
		mm.set_instance_transform_2d(k, Transform2D(0.0, Vector2(d, d), 0.0, b.pos[i]))
		mm.set_instance_color(k, _bcol[b.kind[i]])
		k += 1
		if k >= mm.instance_count:
			break
	mm.visible_instance_count = k


func _sync_effects() -> void:
	var fx: Effects = game.effects
	var mr := _mm_ring.multimesh
	var ms := _mm_spark.multimesh
	var kr := 0
	var ks := 0
	for i in fx._cap:
		if fx.alive[i] == 0:
			continue
		var u := clampf(fx.t[i] / maxf(0.0001, fx.life[i]), 0.0, 1.0)
		match fx.kind[i]:
			Effects.RING:
				if kr >= mr.instance_count:
					continue
				var rad := lerpf(fx.r0[i], fx.r1[i], u)
				var d := rad * 2.0
				var c: Color = fx.col[i]
				c.a = 1.0 - u
				mr.set_instance_transform_2d(kr, Transform2D(0.0, Vector2(d, d), 0.0, fx.pos[i]))
				mr.set_instance_color(kr, c)
				kr += 1
			Effects.SPARK:
				if ks >= ms.instance_count:
					continue
				var d2: float = fx.size[i] * (1.0 - u * 0.55)
				var c2: Color = fx.col[i]
				c2.a = 1.0 - u
				ms.set_instance_transform_2d(ks, Transform2D(0.0, Vector2(d2, d2), 0.0, fx.pos[i]))
				ms.set_instance_color(ks, c2)
				ks += 1
	mr.visible_instance_count = kr
	ms.visible_instance_count = ks


# ------------------------------------------------------------------ 矢量层
func _draw() -> void:
	if game == null or game.grid == null:
		return
	var grid: MapGrid = game.grid

	# 当前最短路提示（塔一建就会变，直观展示"寻路"）
	if game.show_path_hint and game.path_hint.size() > 1:
		draw_polyline(game.path_hint, Cfg.C_PATH_HINT * Color(1, 1, 1, 0.30), 3.0, true)

	# 出生 / 终点方向标
	for c in Cfg.SPAWN_CELLS:
		_draw_arrow(Cfg.cell_center(c.x, c.y), 1.0, Cfg.C_SPAWN)
	for c in Cfg.GOAL_CELLS:
		_draw_arrow(Cfg.cell_center(c.x, c.y), -1.0, Cfg.C_GOAL)

	# 射程预览圈
	if game.preview_range > 0.0 and game.preview_pos != Vector2.ZERO:
		var col := Cfg.C_HOVER_OK
		draw_circle(game.preview_pos, game.preview_range, Color(col.r, col.g, col.b, 0.09))
		draw_arc(game.preview_pos, game.preview_range, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.75), 1.6, true)

	# 塔
	_draw_towers()

	# 悬停格高亮
	if game.hover_valid:
		var rect := Rect2(game.hover_cell.x * Cfg.CELL, game.hover_cell.y * Cfg.CELL, Cfg.CELL, Cfg.CELL)
		var c: Color = game.hover_color
		draw_rect(rect, Color(c.r, c.g, c.b, 0.20), true)
		draw_rect(rect, c, false, 2.0)

	# 选中塔高亮
	if game.selected_tower >= 0 and game.selected_tower < game.towers.alive.size():
		var t: Towers = game.towers
		var si: int = game.selected_tower
		if t.alive[si] == 1:
			var p := t.pos_of(si)
			draw_rect(Rect2(p.x - Cfg.CELL * 0.5, p.y - Cfg.CELL * 0.5, Cfg.CELL, Cfg.CELL), Color(1, 1, 1, 0.85), false, 2.0)

	# 飘字
	_draw_texts()


func _draw_arrow(c: Vector2, dir: float, col: Color) -> void:
	var a := Color(col.r, col.g, col.b, 0.9)
	var w := 7.0
	var pts := PackedVector2Array([
		c + Vector2(-8.0 * dir, -w),
		c + Vector2(8.0 * dir, 0.0),
		c + Vector2(-8.0 * dir, w),
	])
	draw_colored_polygon(pts, a)


func _draw_towers() -> void:
	var t: Towers = game.towers
	for i in t._high:
		if t.alive[i] == 0:
			continue
		var def: Dictionary = Cfg.TOWERS[t.ttype[i]]
		var p := t.pos_of(i)
		var col: Color = def["color"]
		var dark: Color = def["dark"]
		var accent: Color = def["accent"]
		var lv := t.level[i]

		draw_circle(p, 13.0, dark)
		draw_arc(p, 13.0, 0.0, TAU, 28, Color(col.r, col.g, col.b, 0.9), 2.0, true)
		draw_circle(p, 8.5, col)

		var a := t.angle[i]
		var d := Vector2.from_angle(a)
		var perp := Vector2(-d.y, d.x)
		match t.ttype[i]:
			1:  # 炮塔：粗短炮管（顶点必须沿周界顺序，否则三角化失败）
				var tip := p + d * 15.0
				var pts := PackedVector2Array([p + perp * 5.0, tip + perp * 2.0, tip - perp * 2.0, p - perp * 5.0])
				draw_colored_polygon(pts, accent)
				draw_circle(p, 4.0, dark)
			2:  # 冰塔：三角棱镜
				var tip2 := p + d * 14.0
				var pts2 := PackedVector2Array([p + perp * 4.5, tip2, p - perp * 4.5])
				draw_colored_polygon(pts2, accent)
				draw_circle(p, 4.0, dark)
			_:  # 弩塔：细长弩臂
				var tip3 := p + d * 17.0
				var pts3 := PackedVector2Array([p + perp * 2.6, tip3, p - perp * 2.6])
				draw_colored_polygon(pts3, accent)
				draw_circle(p, 3.5, dark)

		# 等级点
		for lv_i in lv:
			draw_circle(p + Vector2(-5.0 + float(lv_i) * 5.0, 12.0), 2.0, accent)


func _draw_texts() -> void:
	var fx: Effects = game.effects
	for i in fx._cap:
		if fx.alive[i] == 0 or fx.kind[i] != Effects.TEXT:
			continue
		var u := clampf(fx.t[i] / maxf(0.0001, fx.life[i]), 0.0, 1.0)
		var p := fx.pos[i] + Vector2(-14.0, -18.0 - u * 22.0)
		var c: Color = fx.col[i]
		c.a = 1.0 - u
		draw_string(font, p, fx.txt[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)
