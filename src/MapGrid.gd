class_name MapGrid
extends RefCounted
## 网格地图：迷宫生成、格子类型、占位与可建性判定。
## 这里是"地形真相"，寻路与渲染都从这里读。

enum Kind { FLOOR, WALL, SPAWN, GOAL }

var w: int = Cfg.GW
var h: int = Cfg.GH
var kind: PackedByteArray = PackedByteArray()
var tower_at: PackedInt32Array = PackedInt32Array()
var seed_value: int = Cfg.DEFAULT_SEED

# 迷宫块邻接（用于编织统计），生成期使用
var _conn: PackedByteArray = PackedByteArray()


func _init() -> void:
	kind.resize(w * h)
	tower_at.resize(w * h)


func idx(x: int, y: int) -> int:
	return y * w + x


func inb(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func kind_at(x: int, y: int) -> int:
	return kind[y * w + x]


func is_wall(x: int, y: int) -> bool:
	return not inb(x, y) or kind[y * w + x] == Kind.WALL


## 地格（不含塔）
func is_open(x: int, y: int) -> bool:
	return inb(x, y) and kind[y * w + x] != Kind.WALL


## 敌人可通行 = 地格 且 无塔
func is_walkable(x: int, y: int) -> bool:
	if not inb(x, y):
		return false
	var i := y * w + x
	return kind[i] != Kind.WALL and tower_at[i] < 0


## 玩家可在此建塔 = 普通地板 且 无塔
func can_build(x: int, y: int) -> bool:
	if not inb(x, y):
		return false
	var i := y * w + x
	return kind[i] == Kind.FLOOR and tower_at[i] < 0


func is_spawn(x: int, y: int) -> bool:
	return inb(x, y) and kind[y * w + x] == Kind.SPAWN


func is_goal(x: int, y: int) -> bool:
	return inb(x, y) and kind[y * w + x] == Kind.GOAL


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / Cfg.CELL)), int(floor(p.y / Cfg.CELL)))


func center_of(cx: int, cy: int) -> Vector2:
	return Cfg.cell_center(cx, cy)


# ------------------------------------------------------------------ 生成
func generate(sd: int) -> void:
	seed_value = sd
	kind.fill(Kind.WALL)
	for i in w * h:
		tower_at[i] = -1

	var rng := RandomNumberGenerator.new()
	rng.seed = sd

	_conn.resize(Cfg.BW * Cfg.BH)
	_conn.fill(0)

	# 1) 每个迷宫块铺 2x2 地面
	for bj in Cfg.BH:
		for bi in Cfg.BW:
			for dy in 2:
				for dx in 2:
					kind[idx(Cfg.BLOCK_PITCH * bi + 1 + dx, Cfg.BLOCK_PITCH * bj + 1 + dy)] = Kind.FLOOR

	# 2) 递归回溯（显式栈）打通块与块
	_carve_maze(rng)

	# 3) 编织：死胡同大概率再开一个口，制造回路（保证"堵一条还有别的路"）
	_braid(rng)

	# 4) 强制打开出生口 / 终点口
	for c in Cfg.SPAWN_CELLS:
		kind[idx(c.x, c.y)] = Kind.SPAWN
	for c in Cfg.GOAL_CELLS:
		kind[idx(c.x, c.y)] = Kind.GOAL


func _carve(x: int, y: int) -> void:
	kind[idx(x, y)] = Kind.FLOOR


func _is_floor(x: int, y: int) -> bool:
	return inb(x, y) and kind[idx(x, y)] == Kind.FLOOR


## 打通两个相邻迷宫块（4 邻域）
func _link(a: Vector2i, b: Vector2i) -> void:
	if a.x == b.x:
		var y := Cfg.BLOCK_PITCH * mini(a.y, b.y) + Cfg.BLOCK_PITCH
		_carve(Cfg.BLOCK_PITCH * a.x + 1, y)
		_carve(Cfg.BLOCK_PITCH * a.x + 2, y)
	else:
		var x := Cfg.BLOCK_PITCH * mini(a.x, b.x) + Cfg.BLOCK_PITCH
		_carve(x, Cfg.BLOCK_PITCH * a.y + 1)
		_carve(x, Cfg.BLOCK_PITCH * a.y + 2)
	_conn[a.y * Cfg.BW + a.x] = _conn[a.y * Cfg.BW + a.x] + 1
	_conn[b.y * Cfg.BW + b.x] = _conn[b.y * Cfg.BW + b.x] + 1


func _linked(a: Vector2i, b: Vector2i) -> bool:
	if a.x == b.x:
		var y := Cfg.BLOCK_PITCH * mini(a.y, b.y) + Cfg.BLOCK_PITCH
		return _is_floor(Cfg.BLOCK_PITCH * a.x + 1, y) and _is_floor(Cfg.BLOCK_PITCH * a.x + 2, y)
	var x := Cfg.BLOCK_PITCH * mini(a.x, b.x) + Cfg.BLOCK_PITCH
	return _is_floor(x, Cfg.BLOCK_PITCH * a.y + 1) and _is_floor(x, Cfg.BLOCK_PITCH * a.y + 2)


func _carve_maze(rng: RandomNumberGenerator) -> void:
	var visited := PackedByteArray()
	visited.resize(Cfg.BW * Cfg.BH)
	visited.fill(0)
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	var stack: Array[Vector2i] = []
	var start := Vector2i(0, 0)
	visited[0] = 1
	stack.append(start)

	while not stack.is_empty():
		var cur: Vector2i = stack[stack.size() - 1]
		var opts: Array[Vector2i] = []
		for d in dirs:
			var nb := cur + d
			if nb.x < 0 or nb.y < 0 or nb.x >= Cfg.BW or nb.y >= Cfg.BH:
				continue
			if visited[nb.y * Cfg.BW + nb.x] == 1:
				continue
			opts.append(nb)
		if opts.is_empty():
			stack.pop_back()
			continue
		var nb2: Vector2i = opts[rng.randi_range(0, opts.size() - 1)]
		_link(cur, nb2)
		visited[nb2.y * Cfg.BW + nb2.x] = 1
		stack.append(nb2)


func _braid(rng: RandomNumberGenerator) -> void:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for bj in Cfg.BH:
		for bi in Cfg.BW:
			var b := Vector2i(bi, bj)
			if _conn[bj * Cfg.BW + bi] >= 2:
				continue
			if rng.randf() > 0.70:
				continue
			var s := rng.randi_range(0, 3)
			for k in 4:
				var d: Vector2i = dirs[(s + k) % 4]
				var nb := b + d
				if nb.x < 0 or nb.y < 0 or nb.x >= Cfg.BW or nb.y >= Cfg.BH:
					continue
				if _linked(b, nb):
					continue
				_link(b, nb)
				break


# ------------------------------------------------------------------ 占位
func set_tower(x: int, y: int, tid: int) -> void:
	tower_at[idx(x, y)] = tid


func clear_tower(x: int, y: int) -> void:
	tower_at[idx(x, y)] = -1


func tower_id_at(x: int, y: int) -> int:
	if not inb(x, y):
		return -1
	return tower_at[idx(x, y)]


# ------------------------------------------------------------------ 调试输出
func dump_ascii() -> String:
	var lines := PackedStringArray()
	for y in h:
		var row := ""
		for x in w:
			var i := idx(x, y)
			match kind[i]:
				Kind.WALL:
					row += "#"
				Kind.SPAWN:
					row += "S"
				Kind.GOAL:
					row += "G"
				_:
					row += "." if tower_at[i] < 0 else "T"
		lines.append(row)
	return "\n".join(lines)
