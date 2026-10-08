class_name FlowField
extends RefCounted
## 寻路核心：从终点反向做多源 Dijkstra，得到"到终点的最短代价场"。
## 所有敌人共享同一张场，每帧每人只查一次表 —— 这是本项目能上规模的根本原因。
##
## 不使用任何寻路库，二叉堆与 Dijkstra 均为自写。

const OX: Array[int] = [1, -1, 0, 0, 1, 1, -1, -1]
const OY: Array[int] = [0, 0, 1, -1, 1, -1, 1, -1]
const OC: Array[int] = [100, 100, 100, 100, 141, 141, 141, 141]  # 正交 100 / 对角 141

var w: int = 0
var h: int = 0

## 到终点的最短代价；-1 = 不可达
var dist: PackedInt32Array = PackedInt32Array()
## 最短路上的下一格索引；-1 = 无（终点或不可达）
var best: PackedInt32Array = PackedInt32Array()
## 出生点是否可达终点
var spawn_reachable: bool = false
## 终点中心（兜底"尽力场"用）
var goal_center: Vector2 = Vector2.ZERO

var _hc: Array[int] = []
var _hi: Array[int] = []
var _pop_cost: int = 0


func _init(grid_w: int, grid_h: int) -> void:
	w = grid_w
	h = grid_h
	dist.resize(w * h)
	best.resize(w * h)
	dist.fill(-1)
	best.fill(-1)


# ------------------------------------------------------------------ 构建
func rebuild(grid: MapGrid, goals: Array[Vector2i]) -> void:
	dist.fill(-1)
	best.fill(-1)
	_hc.clear()
	_hi.clear()

	var goal_sum := Vector2.ZERO
	var goal_n := 0
	for g in goals:
		if not grid.inb(g.x, g.y):
			continue
		goal_sum += grid.center_of(g.x, g.y)
		goal_n += 1
		var gi := grid.idx(g.x, g.y)
		dist[gi] = 0
		_heap_push(gi, 0)
	if goal_n > 0:
		goal_center = goal_sum / float(goal_n)

	# 多源 Dijkstra（惰性删除）
	while not _hc.is_empty():
		var i := _heap_pop()
		if _pop_cost != dist[i]:
			continue
		var c := dist[i]
		var x := i % w
		var y := i / w
		for k in 8:
			var nx: int = x + OX[k]
			var ny: int = y + OY[k]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			if not grid.is_walkable(nx, ny):
				continue
			if k >= 4:
				# 禁止斜穿墙角
				if not grid.is_walkable(x + OX[k], y) or not grid.is_walkable(x, y + OY[k]):
					continue
			var ni: int = ny * w + nx
			var nc: int = c + OC[k]
			if dist[ni] == -1 or nc < dist[ni]:
				dist[ni] = nc
				_heap_push(ni, nc)

	# 方向表：每格指向 dist 最小的邻居
	for y in h:
		for x in w:
			var i := y * w + x
			var d := dist[i]
			if d <= 0:
				continue
			var besti := -1
			var bestd := 2147483647
			for k in 8:
				var nx: int = x + OX[k]
				var ny: int = y + OY[k]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				if k >= 4:
					if not grid.is_walkable(x + OX[k], y) or not grid.is_walkable(x, y + OY[k]):
						continue
				var ni: int = ny * w + nx
				var nd := dist[ni]
				if nd < 0:
					continue
				if nd < bestd:
					bestd = nd
					besti = ni
			best[i] = besti

	spawn_reachable = true
	for s in Cfg.SPAWN_CELLS:
		if not grid.inb(s.x, s.y) or dist[grid.idx(s.x, s.y)] < 0:
			spawn_reachable = false


## 敌人当前格 -> 下一个目标格索引（-1 表示无）
func next_cell(cell_idx: int) -> int:
	if cell_idx < 0 or cell_idx >= best.size():
		return -1
	return best[cell_idx]


func dist_of(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return dist[y * w + x]


# ------------------------------------------------------------------ 二叉最小堆
func _heap_push(cell: int, cost: int) -> void:
	_hc.append(cost)
	_hi.append(cell)
	var i := _hc.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hc[p] <= _hc[i]:
			break
		var tc := _hc[p]; _hc[p] = _hc[i]; _hc[i] = tc
		var ti := _hi[p]; _hi[p] = _hi[i]; _hi[i] = ti
		i = p


func _heap_pop() -> int:
	var top := _hi[0]
	_pop_cost = _hc[0]
	var last := _hc.size() - 1
	_hc[0] = _hc[last]
	_hi[0] = _hi[last]
	_hc.resize(last)
	_hi.resize(last)
	var n := _hc.size()
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var smallest := i
		if l < n and _hc[l] < _hc[smallest]:
			smallest = l
		if r < n and _hc[r] < _hc[smallest]:
			smallest = r
		if smallest == i:
			break
		var tc := _hc[smallest]; _hc[smallest] = _hc[i]; _hc[i] = tc
		var ti := _hi[smallest]; _hi[smallest] = _hi[i]; _hi[i] = ti
		i = smallest
	return top


# ------------------------------------------------------------------ 连通性 / 追踪
## 出生点集合能否走到终点集合（extra_blocked_idx 视为额外障碍，用于"建塔会不会堵死"预判）
static func has_path(grid: MapGrid, from_cells: Array[Vector2i], goal_cells: Array[Vector2i],
		extra_blocked_idx: int = -1) -> bool:
	var n := grid.w * grid.h
	var seen := PackedByteArray()
	seen.resize(n)
	seen.fill(0)

	var goal_set := {}
	for g in goal_cells:
		if grid.inb(g.x, g.y):
			goal_set[grid.idx(g.x, g.y)] = true

	var q: Array[int] = []
	for s in from_cells:
		if not grid.inb(s.x, s.y):
			continue
		var si: int = grid.idx(s.x, s.y)
		if grid.tower_at[si] >= 0 or grid.kind[si] == MapGrid.Kind.WALL or si == extra_blocked_idx:
			continue
		if seen[si] == 1:
			continue
		seen[si] = 1
		q.append(si)

	var head := 0
	while head < q.size():
		var cur: int = q[head]
		head += 1
		if goal_set.has(cur):
			return true
		var x := cur % grid.w
		var y := cur / grid.w
		for k in 8:
			var nx: int = x + OX[k]
			var ny: int = y + OY[k]
			if nx < 0 or ny < 0 or nx >= grid.w or ny >= grid.h:
				continue
			var ni: int = ny * grid.w + nx
			if seen[ni] == 1 or ni == extra_blocked_idx:
				continue
			if grid.kind[ni] == MapGrid.Kind.WALL or grid.tower_at[ni] >= 0:
				continue
			if k >= 4:
				# 斜向需要两侧正交可走
				var a: int = y * grid.w + nx
				var b: int = ny * grid.w + x
				if grid.kind[a] == MapGrid.Kind.WALL or grid.tower_at[a] >= 0:
					continue
				if grid.kind[b] == MapGrid.Kind.WALL or grid.tower_at[b] >= 0:
					continue
			seen[ni] = 1
			q.append(ni)
	return false


## 从某格沿着最短路走回终点，返回格心序列（用于画面上的"当前路线"提示）
func trace(grid: MapGrid, start: Vector2i, max_steps: int = 400) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not grid.inb(start.x, start.y):
		return pts
	var i := grid.idx(start.x, start.y)
	if dist[i] < 0:
		return pts
	var guard := 0
	while i >= 0 and guard < max_steps:
		guard += 1
		var x := i % w
		var y := i / w
		pts.append(grid.center_of(x, y))
		if dist[i] == 0:
			break
		i = best[i]
	return pts
