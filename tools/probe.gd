extends SceneTree
# API 探针：确认本机 Godot 版本可用到的具体 API，避免凭记忆写代码。


func _initialize() -> void:
	var out: Array[String] = []
	out.append("Godot: %s" % str(Engine.get_version_info().get("string", "?")))

	out.append("Image.create_empty: %s" % _has("Image", "create_empty"))
	out.append("Image.create: %s" % _has("Image", "create"))
	out.append("ImageTexture.create_from_image: %s" % _has("ImageTexture", "create_from_image", false))

	out.append("MultiMesh.TRANSFORM_2D: %d" % MultiMesh.TRANSFORM_2D)
	out.append("MultiMesh.set_instance_transform_2d: %s" % _has("MultiMesh", "set_instance_transform_2d"))
	out.append("MultiMesh.set_instance_color: %s" % _has("MultiMesh", "set_instance_color"))

	var mmi := MultiMeshInstance2D.new()
	out.append("MultiMeshInstance2D.texture (set/get): %s" % str(mmi.get("texture")))

	var qm := QuadMesh.new()
	out.append("QuadMesh.size default: %s" % str(qm.size))
	out.append("PlaneMesh.FACE_Z: %d" % PlaneMesh.FACE_Z)
	qm.orientation = PlaneMesh.FACE_Z
	out.append("QuadMesh orientation set OK -> %d" % qm.orientation)

	var img := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	out.append("ImageTexture OK: %s" % str(tex.get_size()))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.data = PackedByteArray([0, 0, 0, 0])
	out.append("AudioStreamWAV OK, data size=%d" % wav.data.size())
	out.append("AudioStreamPlayer exists: %s" % str(ClassDB.class_exists("AudioStreamPlayer")))

	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	mmi.multimesh.use_colors = true
	mmi.multimesh.mesh = qm
	mmi.multimesh.instance_count = 3
	mmi.multimesh.visible_instance_count = 2
	out.append("MultiMesh configured OK")

	out.append("Engine.get_frames_per_second: %s" % _has("Engine", "get_frames_per_second", false))
	out.append("OS.get_processor_count: %d" % OS.get_processor_count())
	out.append("display driver: %s" % str(DisplayServer.get_name()))
	out.append("use_colors prop: %s" % str(mmi.multimesh.use_colors))

	print("=== PROBE START ===")
	for line in out:
		print(line)
	print("=== PROBE END ===")
	quit(0)


func _has(cls: String, method: String, inherited := true) -> String:
	return "YES" if ClassDB.class_has_method(cls, method, not inherited) else "NO"
