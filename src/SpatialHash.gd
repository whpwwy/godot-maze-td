class_name SpatialHash
extends RefCounted
## 均匀网格空间哈希：把 O(n²) 的邻居查询降到接近 O(1)。
## 敌人移动、塔锁敌、子弹命中都靠它。

var cell_size: float = 48.0
var cols: int = 0
var rows: int = 0
var heads: PackedInt32Array = PackedInt32Array()
var nexts: PackedInt32Array = PackedInt32Array()
var item_count: int = 0


func _init(world_w: float, world_h: float, cs: float, capacity: int) -> void:
	cell_size = cs
	cols = int(ceil(world_w / cs)) + 1
	rows = int(ceil(world_h / cs)) + 1
	heads.resize(cols * rows)
	heads.fill(-1)
	nexts.resize(capacity)
	nexts.fill(-1)


func _bucket(p: Vector2) -> int:
	var bx := clampi(int(p.x / cell_size), 0, cols - 1)
	var by := clampi(int(p.y / cell_size), 0, rows - 1)
	return by * cols + bx


## 每帧重建（O(n)）
func rebuild(pos: PackedVector2Array, alive: PackedByteArray, n: int) -> void:
	heads.fill(-1)
	item_count = 0
	for i in n:
		if alive[i] == 0:
			continue
		var b := _bucket(pos[i])
		nexts[i] = heads[b]
		heads[b] = i
		item_count += 1


## 查询半径内的所有 item 下标，写入 out（需预先分配足够大），返回数量
func query(p: Vector2, radius: float, out: PackedInt32Array) -> int:
	var found := 0
	var cap := out.size()
	var x0 := clampi(int((p.x - radius) / cell_size), 0, cols - 1)
	var x1 := clampi(int((p.x + radius) / cell_size), 0, cols - 1)
	var y0 := clampi(int((p.y - radius) / cell_size), 0, rows - 1)
	var y1 := clampi(int((p.y + radius) / cell_size), 0, rows - 1)
	for by in range(y0, y1 + 1):
		var base := by * cols
		for bx in range(x0, x1 + 1):
			var it := heads[base + bx]
			while it != -1:
				if found >= cap:
					return found
				out[found] = it
				found += 1
				it = nexts[it]
	return found
