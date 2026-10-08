extends SceneTree
## 语义探针：确认 Packed*Array 作为函数参数时是否为引用传递。


func _fill(a: PackedInt32Array) -> void:
	a[0] = 999
	a[1] = 888


func _fill_dyn(a: Array) -> void:
	a[0] = 777


func _initialize() -> void:
	var packed := PackedInt32Array([1, 2, 3])
	_fill(packed)
	print("packed after call: ", packed)

	var packed2 := PackedInt32Array([1, 2, 3])
	var alias = packed2
	_fill(alias)
	print("packed alias after call: ", packed2)

	var arr := [1, 2, 3]
	_fill_dyn(arr)
	print("Array after call: ", arr)

	var f := PackedFloat32Array([1.0, 2.0])
	var g = f
	g[0] = 5.0
	print("float copy-on-assign: f=", f, " g=", g)

	quit(0)
