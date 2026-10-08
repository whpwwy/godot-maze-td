extends SceneTree
## 地图 + 流场转储：把迷宫打成 ASCII、验证连通性与最短路长度。


func _initialize() -> void:
	var seed_value := Cfg.DEFAULT_SEED
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--seed="):
			seed_value = int(a.substr(7))

	var g := MapGrid.new()
	g.generate(seed_value)
	print("=== MAP (seed=%d) ===" % seed_value)
	print(g.dump_ascii())

	var walls := 0
	var floor_cells := 0
	for i in g.kind.size():
		if g.kind[i] == MapGrid.Kind.WALL:
			walls += 1
		else:
			floor_cells += 1
	print("cells=%d walls=%d floor=%d wall_ratio=%.3f" % [g.kind.size(), walls, floor_cells, float(walls) / float(g.kind.size())])

	var naive := FlowField.has_path(g, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS)
	print("BFS spawn->goal : %s" % str(naive))

	var ff := FlowField.new(g.w, g.h)
	ff.rebuild(g, Cfg.GOAL_CELLS)
	print("field.spawn_reachable : %s" % str(ff.spawn_reachable))
	print("dist(spawn 0,7) : %d  (格数约 %.1f)" % [ff.dist_of(0, 7), float(ff.dist_of(0, 7)) / 100.0])
	print("dist(spawn 0,8) : %d" % ff.dist_of(0, 8))

	var path := ff.trace(g, Vector2i(0, 7))
	print("trace cells : %d" % path.size())

	# 可达格统计
	var reach := 0
	for i in ff.dist.size():
		if ff.dist[i] >= 0:
			reach += 1
	print("reachable cells : %d / %d" % [reach, ff.dist.size()])

	# 建塔堵路测试：把出生口旁边两格都堵上，看是否拒绝
	var test := MapGrid.new()
	test.generate(seed_value)
	var blocked_ok := true
	# 找到一处可从 (1,7) 出发的瓶颈：直接把 (1,7)(1,8) 都占塔
	test.set_tower(1, 7, 0)
	print("after blocking (1,7) -> has_path : %s" % str(FlowField.has_path(test, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS)))
	test.set_tower(1, 8, 1)
	print("after blocking (1,7)+(1,8) -> has_path : %s" % str(FlowField.has_path(test, Cfg.SPAWN_CELLS, Cfg.GOAL_CELLS)))

	quit(0)
