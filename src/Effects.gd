class_name Effects
extends RefCounted
## 特效池：环形缓冲，永不分配、永不耗尽。命中火花 / 爆炸环 / 飘字。

enum { RING, SPARK, TEXT }

var kind: PackedByteArray = PackedByteArray()
var pos: PackedVector2Array = PackedVector2Array()
var t: PackedFloat32Array = PackedFloat32Array()
var life: PackedFloat32Array = PackedFloat32Array()
var r0: PackedFloat32Array = PackedFloat32Array()
var r1: PackedFloat32Array = PackedFloat32Array()
var col: PackedColorArray = PackedColorArray()
var size: PackedFloat32Array = PackedFloat32Array()
var txt: PackedStringArray = PackedStringArray()
var alive: PackedByteArray = PackedByteArray()

var _head: int = 0
var _cap: int = 0


func _init() -> void:
	_cap = Cfg.MAX_EFFECTS
	kind.resize(_cap)
	pos.resize(_cap)
	t.resize(_cap)
	life.resize(_cap)
	r0.resize(_cap)
	r1.resize(_cap)
	col.resize(_cap)
	size.resize(_cap)
	txt.resize(_cap)
	alive.resize(_cap)
	alive.fill(0)


func _next(k: int) -> int:
	var i := _head
	_head = (_head + 1) % _cap
	kind[i] = k
	t[i] = 0.0
	alive[i] = 1
	return i


func ring(p: Vector2, radius0: float, radius1: float, duration: float, color: Color) -> void:
	var i := _next(RING)
	pos[i] = p
	r0[i] = radius0
	r1[i] = radius1
	life[i] = duration
	col[i] = color


func spark(p: Vector2, color: Color, duration: float, sz: float) -> void:
	var i := _next(SPARK)
	pos[i] = p
	life[i] = duration
	col[i] = color
	size[i] = sz


func text(p: Vector2, s: String, color: Color) -> void:
	var i := _next(TEXT)
	pos[i] = p
	life[i] = 0.85
	col[i] = color
	txt[i] = s


func update(dt: float) -> void:
	for i in _cap:
		if alive[i] == 0:
			continue
		t[i] += dt
		if t[i] >= life[i]:
			alive[i] = 0


func clear() -> void:
	alive.fill(0)
	_head = 0
