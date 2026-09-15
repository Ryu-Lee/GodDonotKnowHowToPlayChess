## 无头测试工具:godot --headless --script tools/headless_test.gd
## 覆盖:初始局面、各棋子走法、蹩马腿、塞象眼、炮架、过河兵、对将、将死、悔棋、自对弈。
extends SceneTree

var pass_count := 0
var fail_count := 0

func _init() -> void:
	_run_tests()
	quit(1 if fail_count > 0 else 0)

func _check(cond: bool, name: String) -> void:
	if cond:
		pass_count += 1
		print("  PASS  %s" % name)
	else:
		fail_count += 1
		print("  FAIL  %s" % name)

func _load() -> Dictionary:
	return PackLoader.load_pack("res://data/packs/classic_xiangqi")

func _piece(state: MatchState, faction: String, x: int, y: int) -> Piece:
	var p := state.piece_at(x, y)
	return p if p != null and p.faction == faction else null

func _new_match() -> Match:
	var pack := _load()
	return Match.new(pack["state"], pack["rules"], pack["piece_types"])

func _run_tests() -> void:
	print("=== Headless engine tests (M0+M1) ===")
	_test_initial_setup()
	_test_movegen_counts()
	_test_ma_leg()
	_test_xiang_eye()
	_test_pao_screen()
	_test_bing_cross()
	_test_flying_general()
	_test_checkmate()
	_test_undo()
	_test_selfplay()
	_test_palace_bounds()
	_test_terrain_impassable()
	_test_terrain_oneway()
	_test_terrain_limited()
	_test_terrain_limited_undo()
	_test_ruleops()
	_test_ruleops_undo()
	_test_temp_rule_effect()
	_test_win_cond_variants()
	_test_scenario()
	_test_ai_search()
	_test_ai_search_perf()
	print("=== Results: %d passed, %d failed ===" % [pass_count, fail_count])

# ---------------------------------------------------------------- 测试用例

func _test_initial_setup() -> void:
	print("[initial setup]")
	var m := _new_match()
	_check(m.state.pieces.size() == 32, "32 pieces on board")
	_check(m.state.turn == "red", "red moves first")
	var red_j: Piece = m.state.piece_at(4, 9)
	var black_j: Piece = m.state.piece_at(4, 0)
	_check(red_j != null and red_j.type.royal, "red general at (4,9)")
	_check(black_j != null and black_j.type.royal, "black general at (4,0)")

func _test_movegen_counts() -> void:
	print("[movegen counts]")
	var m := _new_match()
	var red_moves := MoveGen.all_legal_moves(m.state, "red")
	# 象棋共识:初始局面双方各有 44 步合法走法
	_check(red_moves.size() == 44, "initial red legal moves == 44 (got %d)" % red_moves.size())
	var black_moves := MoveGen.all_legal_moves(m.state, "black")
	_check(black_moves.size() == 44,
		"initial black legal moves == 44 (got %d)" % black_moves.size())

func _test_ma_leg() -> void:
	print("[ma leg block]")
	var m := _new_match()
	# 红马 (1,9):向上跳 (0,7) 和 (2,7) 被己方炮 (1,7) 蹩腿?
	# 马在 (1,9), 走 (0,7): 方向 v=(-1,-2), 大轴 y => 腿在 (1,8), 空,可走
	# 走 (2,7): v=(1,-2), 腿在 (1,8), 空,可走
	# 走 (3,8): v=(2,-1), 大轴 x => 腿在 (2,9), 有相 => 蹩
	var ma := _piece(m.state, "red", 1, 9)
	_check(ma != null, "red horse found at (1,9)")
	var moves := MoveGen.piece_moves(m.state, ma)
	var targets := {}
	for mv in moves:
		targets[Vector2i(mv.to_x, mv.to_y)] = true
	_check(targets.has(Vector2i(0, 7)), "horse can jump to (0,7)")
	_check(targets.has(Vector2i(2, 7)), "horse can jump to (2,7)")
	_check(not targets.has(Vector2i(3, 8)), "horse leg blocked by elephant at (2,9) -> no (3,8)")
	_check(not targets.has(Vector2i(1, 7)), "horse cannot land on own cannon (1,7)")

func _test_xiang_eye() -> void:
	print("[xiang eye block]")
	var m := _new_match()
	# 红相 (2,9) 走 (0,7): 眼在 (1,8),空,可走
	# 红相 (2,9) 走 (4,7): 眼在 (3,8),空,可走——(4,7)? 有红兵吗?红兵在 (4,6)。(4,7) 空,可走
	# 走 (2,5)? 那是过河,zone own_half 禁止(河在 4,5)
	var xiang := _piece(m.state, "red", 2, 9)
	_check(xiang != null, "red elephant found at (2,9)")
	var moves := MoveGen.piece_moves(m.state, xiang)
	var targets := {}
	for mv in moves:
		targets[Vector2i(mv.to_x, mv.to_y)] = true
	_check(targets.has(Vector2i(0, 7)), "elephant to (0,7) ok")
	_check(targets.has(Vector2i(4, 7)), "elephant to (4,7) ok")
	_check(not targets.has(Vector2i(2, 5)), "elephant cannot cross river to (2,5)")
	# 塞象眼:黑士在 (3,0)? 黑象 (2,0) 走 (4,2),眼 (3,1) 空;构造:黑炮 (7,2) 与黑象 (6,0):
	# 象 (6,0) 走 (8,2): 眼 (7,1) 空 => 可;走 (4,2): 眼 (5,1) 空 => 可。
	# 直接构造局面:眼 (1,8) 放黑子 => 红相 (2,9) 不能到 (0,7)
	var blocker := Piece.new(m.piece_types["ju"], "black", 1, 8)
	m.state.pieces.append(blocker)
	var moves2 := MoveGen.piece_moves(m.state, xiang)
	var targets2 := {}
	for mv in moves2:
		targets2[Vector2i(mv.to_x, mv.to_y)] = true
	_check(not targets2.has(Vector2i(0, 7)), "elephant eye blocked at (1,8) -> no (0,7)")

func _test_pao_screen() -> void:
	print("[pao screen capture]")
	var m := _new_match()
	# 红炮 (1,7) 平移可到 (0,7)..(7,7)? (7,7) 是己方炮 => 滑到 (6,7) 停。
	# 吃:向上方向 (1,6)...(1,3) 有黑卒? (1,3) 无卒,卒在 (0,3)(2,3)...;黑炮在 (1,2)。
	# 屏吃:红炮 (1,7) 向上,炮架 = 黑卒? 无 —— 第一个遇到的是 (1,2) 黑炮(架),越过,下一个 (1,0) 黑马(可吃)。
	var pao := _piece(m.state, "red", 1, 7)
	_check(pao != null, "red cannon found at (1,7)")
	var moves := MoveGen.piece_moves(m.state, pao)
	var targets := {}
	for mv in moves:
		targets[Vector2i(mv.to_x, mv.to_y)] = true
	_check(targets.has(Vector2i(1, 0)), "cannon screens over (1,2) to capture horse at (1,0)")
	_check(not targets.has(Vector2i(1, 2)), "cannon cannot capture screen itself at (1,2)")
	_check(targets.has(Vector2i(6, 7)), "cannon slides along row to (6,7)")
	_check(not targets.has(Vector2i(8, 7)), "cannon blocked by own cannon at (7,7)")
	# 吃完验证:apply 后黑马死
	var mv := Action.new(pao, 1, 0)
	MoveGen.apply(m.state, mv)
	_check(_piece(m.state, "black", 1, 0) == null, "black horse captured")

func _test_bing_cross() -> void:
	print("[bing river crossing]")
	var m := _new_match()
	# 红兵 (4,6): 未过河只可 (4,5);手动放到 (4,4)(已过河,河是 4,5)
	var bing := _piece(m.state, "red", 4, 6)
	bing.x = 4
	bing.y = 4
	var moves := MoveGen.piece_moves(m.state, bing)
	var targets := {}
	for mv in moves:
		targets[Vector2i(mv.to_x, mv.to_y)] = true
	_check(targets.has(Vector2i(4, 3)), "crossed pawn moves forward to (4,3)")
	_check(targets.has(Vector2i(3, 4)), "crossed pawn moves left to (3,4)")
	_check(targets.has(Vector2i(5, 4)), "crossed pawn moves right to (5,4)")
	_check(not targets.has(Vector2i(4, 5)), "crossed pawn cannot retreat to (4,5)")
	# 未过河兵只能前进
	var bing2 := _piece(m.state, "red", 0, 6)
	var moves2 := MoveGen.piece_moves(m.state, bing2)
	var only_forward := true
	for mv in moves2:
		if Vector2i(mv.to_x, mv.to_y) != Vector2i(0, 5):
			only_forward = false
	_check(moves2.size() == 1 and only_forward, "uncrossed pawn only moves forward")

func _test_flying_general() -> void:
	print("[flying general]")
	var m := _new_match()
	# 构造双将对脸:仅保留双将,同列 (4,9) vs (4,0),中间无子
	for p in m.state.pieces:
		if not p.type.royal:
			p.alive = false
	var jiang := _piece(m.state, "red", 4, 9)
	var black_jiang := _piece(m.state, "black", 4, 0)
	_check(jiang != null and black_jiang != null, "both generals alive on file 4")
	# 红帅尝试走到 (4,8):模拟后双将对脸 => 非法(结构规则,非败着过滤)
	var mv := Action.new(jiang, 4, 8)
	_check(not MoveGen.is_legal(m.state, mv), "general cannot step into flying-general line")
	# 送将步(走完被吃)不再过滤:先把红帅移出对将线(3,9)避免结构规则干扰,
	# 再构造黑车 (3,5) 瞄着 (3,8):红车走进去 = 下回合必被吃,但仍合法
	jiang.x = 3
	m.state.pieces.append(Piece.new(m.piece_types["ju"], "black", 3, 5))
	var suicide := Action.new(Piece.new(m.piece_types["ju"], "red", 5, 8), 3, 8)
	m.state.pieces.append(suicide.piece)
	_check(MoveGen.is_legal(m.state, suicide), "losing moves are legal (player freedom)")

func _test_checkmate() -> void:
	print("[checkmate / stalemate]")
	var m := _new_match()
	# 构造极简将死:仅保留双将;红帅 (3,9) 避开同列,红车围死黑将
	for p in m.state.pieces:
		if not p.type.royal:
			p.alive = false
	var black_jiang := _piece(m.state, "black", 4, 0)
	var red_jiang := _piece(m.state, "red", 4, 9)
	red_jiang.x = 3
	red_jiang.y = 9
	m.state.pieces.append(Piece.new(m.piece_types["ju"], "red", 4, 1))   # 正面叫将
	m.state.pieces.append(Piece.new(m.piece_types["ju"], "red", 3, 0))   # 封左
	m.state.pieces.append(Piece.new(m.piece_types["ju"], "red", 5, 0))   # 封右
	m.state.pieces.append(Piece.new(m.piece_types["ju"], "red", 4, 2))   # 防黑将吃(4,1)后逃逸
	m.state.turn = "black"
	var black_moves := MoveGen.all_legal_moves(m.state, "black")
	# 黑将可吃 (4,1) 与 (5,0) 的车(吃后必被将 = 合法败着,不再过滤);
	# (3,0) 吃车后与红帅 (3,9) 同列空巷 => 对禁。=> 合法走法 = 2 吃车步
	var capture_targets := {}
	for bmv in black_moves:
		capture_targets[Vector2i(bmv.to_x, bmv.to_y)] = true
	_check(black_moves.size() == 2 and capture_targets.has(Vector2i(4, 1)) and capture_targets.has(Vector2i(5, 0)),
		"black general: both chariot captures legal (losing moves allowed, got %d moves)" % black_moves.size())
	# 黑将真吃 (4,1) 车:submit 接受败着;对局未完(将还在)——
	# 红车 (4,2) 下一步吃将(将身挡 4 列,只能吃 (4,1)),royal_captured 结算 => 红胜
	var applied := m.try_move(black_moves[0].piece, 4, 1)
	_check(applied != null, "suicide capture is accepted by submit")
	_check(m.result == WinCond.Result.ONGOING, "game ongoing after suicide move (royal still alive)")
	var red_ju := _piece(m.state, "red", 4, 2)
	_check(red_ju != null, "red chariot at (4,2) ready to capture general")
	var finisher := m.try_move(red_ju, 4, 1)
	_check(finisher != null, "red captures black general")
	m.result = WinCond.evaluate(m.state, m.rules)
	_check(m.result == WinCond.Result.RED_WIN, "royal captured => red wins")

func _test_undo() -> void:
	print("[undo]")
	var m := _new_match()
	var pao := _piece(m.state, "red", 1, 7)
	var mv := m.try_move(pao, 1, 0)   # 吃黑马
	_check(mv != null, "cannon captures horse")
	_check(_piece(m.state, "black", 1, 0) == null, "horse gone")
	_check(m.state.turn == "black", "turn flipped to black")
	m.undo_last()
	_check(_piece(m.state, "black", 1, 0) != null, "horse restored after undo")
	_check(m.state.turn == "red", "turn restored to red")
	_check(m.state.piece_at(1, 7) == pao, "cannon back at (1,7)")

func _test_selfplay() -> void:
	print("[selfplay x5]")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260911
	var finished := 0
	for i in 5:
		var m := _new_match()
		var steps := 0
		while m.result == WinCond.Result.ONGOING and steps < 500:
			var mv := AIRandom.pick_move(m.state, m.state.turn, rng)
			if mv == null:
				break
			var applied := m.try_move(mv.piece, mv.to_x, mv.to_y)
			if applied == null:
				break
			steps += 1
		if m.result != WinCond.Result.ONGOING or steps < 500:
			finished += 1
		print("    game %d: %d moves, result=%s" % [i + 1, steps, WinCond.result_name(m.result)])
	_check(finished > 0, "at least one selfplay game finished within cap")

# ---------------------------------------------------------------- M1 九宫修复

func _test_palace_bounds() -> void:
	print("[palace bounds]")
	var m := _new_match()
	# 帅 (4,9) 只能走到九宫内:(4,8)(3,9)(5,9);不可越出九宫(x=6 / y>9 之外 / y=6)
	var jiang := _piece(m.state, "red", 4, 9)
	_check(jiang != null, "red general found")
	# 直接验证 in_palace 闭区间语义:红宫 x∈[3,5] y∈[7,9]
	_check(m.state.board.in_palace("red", 3, 7), "red palace contains (3,7)")
	_check(m.state.board.in_palace("red", 5, 9), "red palace contains (5,9)")
	_check(not m.state.board.in_palace("red", 6, 8), "red palace excludes x=6")
	_check(not m.state.board.in_palace("red", 4, 6), "red palace excludes y=6")
	_check(not m.state.board.in_palace("black", 3, 3), "black palace excludes y=3")
	# 士 (3,9):只能在宫内走斜线
	var shi := _piece(m.state, "red", 3, 9)
	shi.x = 5
	shi.y = 7   # 移到宫内另一角 (5,7)
	var moves := MoveGen.piece_moves(m.state, shi)
	for mv in moves:
		_check(m.state.board.in_palace("red", mv.to_x, mv.to_y),
			"advisor stays in palace ((%d,%d))" % [mv.to_x, mv.to_y])
	# 帅走法全部在宫内
	for mv in MoveGen.piece_moves(m.state, jiang):
		_check(m.state.board.in_palace("red", mv.to_x, mv.to_y),
			"general stays in palace ((%d,%d))" % [mv.to_x, mv.to_y])

# ---------------------------------------------------------------- M1 地形

func _test_terrain_impassable() -> void:
	print("[terrain: impassable]")
	var m := _new_match()
	# 红车 (0,9) 上方 (0,8) 设禁行格 => 车向上被截断,只能横向滑
	var ju := _piece(m.state, "red", 0, 9)
	m.state.board.cell(0, 8).pass_rule = "impassable"
	# 挪走 (1,9) 红马让出横向滑道((2,7) 空),验证地形只截断纵向
	var horse := _piece(m.state, "red", 1, 9)
	horse.x = 2
	horse.y = 7
	var moves := MoveGen.piece_moves(m.state, ju)
	var targets := {}
	for mv in moves:
		targets[Vector2i(mv.to_x, mv.to_y)] = true
	_check(not targets.has(Vector2i(0, 8)), "chariot blocked at impassable (0,8)")
	_check(not targets.has(Vector2i(0, 7)), "chariot cannot slide past impassable")
	_check(targets.has(Vector2i(1, 9)), "chariot still slides sideways to (1,9)")

func _test_terrain_oneway() -> void:
	print("[terrain: oneway]")
	var m := _new_match()
	# 红兵 (0,6) 前方 (0,5) 设单向:pass_dir=(0,1)(只允许从上往下进入,红兵从下往上 => 禁)
	var bing := _piece(m.state, "red", 0, 6)
	m.state.board.cell(0, 5).pass_rule = "oneway"
	m.state.board.cell(0, 5).pass_dir = Vector2i(0, 1)
	# 未过河兵本可前进 (0,5);单向拦截 => submit 拒绝(piece_moves 不查 oneway,
	# 单向属"进入方向"规则,由 is_legal/oneway_ok 闸把关)
	var mv := m.try_move(bing, 0, 5)
	_check(mv == null, "pawn blocked by oneway (dir mismatch)")
	# 反转 pass_dir:只允许从下往上(红兵前进方向)进入 => 放行
	m.state.board.cell(0, 5).pass_dir = Vector2i(0, -1)
	var mv2 := m.try_move(bing, 0, 5)
	_check(mv2 != null, "pawn passes oneway when dir matches")

func _test_terrain_limited() -> void:
	print("[terrain: limited]")
	var m := _new_match()
	# 红兵 (0,6) 前方 (0,5) 设 limited=1
	var bing := _piece(m.state, "red", 0, 6)
	m.state.board.cell(0, 5).pass_rule = "limited"
	m.state.board.cell(0, 5).pass_limit = 1
	var mv1 := m.try_move(bing, 0, 5)
	_check(mv1 != null, "pawn enters limited cell (1st use)")
	_check(m.state.board.cell(0, 5).pass_limit == 0, "pass_limit consumed to 0")
	# 黑方随便走一步,再验证红方无法再进入(0,5)已占,换黑卒走;然后悔棋验证返还
	var black_bing := _piece(m.state, "black", 0, 3)
	m.try_move(black_bing, 0, 4)
	m.undo_last()
	m.undo_last()
	_check(m.state.board.cell(0, 5).pass_limit == 1, "pass_limit refunded after undo")
	_check(m.state.piece_at(0, 6) == bing, "pawn back at (0,6) after undo")
	# 重新进入后用尽:limit=0 => 不可再入;把兵放回 (0,6) 后 (0,5) 空且 limit=1
	mv1 = m.try_move(bing, 0, 5)
	_check(mv1 != null and m.state.board.cell(0, 5).pass_limit == 0, "re-enter consumes again")
	# 另一红兵从 (2,6) 挪到 (2,5) 不受限;构造第二个红兵进 (0,5)? 已占。清空后直接放新兵:
	m.state.pieces.append(Piece.new(m.piece_types["bing"], "red", 0, 7))
	var bing2 := _piece(m.state, "red", 0, 7)
	m.state.turn = "red"
	var mv2 := m.try_move(bing2, 0, 6)
	_check(mv2 != null, "another pawn passes through non-limited (0,6) fine")

func _test_terrain_limited_undo() -> void:
	print("[terrain: limited undo regression]")
	var m := _new_match()
	var bing := _piece(m.state, "red", 0, 6)
	m.state.board.cell(0, 5).pass_rule = "limited"
	m.state.board.cell(0, 5).pass_limit = 2
	m.try_move(bing, 0, 5)                              # limit 2→1
	var bb := _piece(m.state, "black", 8, 3)
	m.try_move(bb, 8, 4)
	var rb := _piece(m.state, "red", 8, 6)
	m.try_move(rb, 8, 5)                                # 本回合红又走一步
	# 悔棋 3 次(含黑方那步):limited 次数应全额返还,不会因重放而重复扣
	m.undo_last()
	m.undo_last()
	m.undo_last()
	_check(m.state.board.cell(0, 5).pass_limit == 2,
		"pass_limit fully refunded after undo (got %d)" % m.state.board.cell(0, 5).pass_limit)
	_check(m.state.piece_at(0, 6) == bing, "pawn back at (0,6)")
	m.state.turn = "red"
	var re_enter := m.try_move(bing, 0, 5)
	_check(re_enter != null and m.state.board.cell(0, 5).pass_limit == 1,
		"undo left the bridge intact (2 uses, 1 after re-enter)")

# ---------------------------------------------------------------- M1 临时规则生效

func _test_temp_rule_effect() -> void:
	print("[temp rule: no_pao_cross_river]")
	var m := _new_match()
	var pao := _piece(m.state, "red", 1, 7)
	# 神颁布:本局炮不可过河(3 整回合)
	m.rules.add_temp_rule("no_pao_cross_river", 3)
	# 红炮向前(向上)滑:河对岸 y<=4 的格全禁;y>=5 仍可走
	var moves := MoveGen.piece_moves(m.state, pao)
	var has_crossed := false
	var has_own_side := false
	for mv in moves:
		if mv.to_y <= 4:
			has_crossed = true
		elif mv.to_y >= 5:
			has_own_side = true
	_check(not has_crossed, "cannon cannot cross river under temp rule")
	_check(has_own_side, "cannon still moves on own side")
	# 车不受该规则影响:构造红车 (5,5)(空格),沿 5 列北上可达 y<=4
	var ju := Piece.new(m.piece_types["ju"], "red", 5, 5)
	m.state.pieces.append(ju)
	var ju_moves := MoveGen.piece_moves(m.state, ju)
	var ju_cross_ok := false
	for mv in ju_moves:
		if mv.to_y <= 4:
			ju_cross_ok = true
	_check(ju_cross_ok, "chariot unaffected by no_pao_cross_river")
	m.state.pieces.erase(ju)
	# 倒计时:红炮沿 7 行、黑炮沿 2 行各滑 3 步(每步合法且不涉过河列),
	# 3 整回合后规则消失
	var black_pao := _piece(m.state, "black", 1, 2)
	var red_to := [Vector2i(0, 7), Vector2i(2, 7), Vector2i(3, 7)]
	var black_to := [Vector2i(0, 2), Vector2i(2, 2), Vector2i(3, 2)]
	for i in 3:
		if m.try_move(pao, red_to[i].x, red_to[i].y) == null:
			break
		if m.try_move(black_pao, black_to[i].x, black_to[i].y) == null:
			break
	_check(not m.rules.has_temp_rule("no_pao_cross_river"),
		"temp rule expires after 3 full rounds")
	var moves2 := MoveGen.piece_moves(m.state, pao)
	var crossed_restored := false
	for mv in moves2:
		if mv.to_y <= 4:
			crossed_restored = true
	_check(crossed_restored, "cannon crosses river again after expiry")

# ---------------------------------------------------------------- M1 数据驱动胜负

func _test_win_cond_variants() -> void:
	print("[win conditions: data-driven variants]")
	# 1. 歼灭:黑方全卒被吃 => 红胜
	var m := _new_match()
	for p in m.state.pieces:
		if p.faction == "black" and p.type.id == "bing":
			p.alive = false
	m.rules.win_conditions.clear()
	m.rules.win_conditions.append(RuleSet.WinCondition.from_dict(
		{"id": "wipe_bing", "type": "annihilation", "faction": "black", "types": ["bing"]}))
	_check(WinCond.evaluate(m.state, m.rules) == WinCond.Result.RED_WIN,
		"annihilation: red wins when black pawns wiped")
	# 2. 撑过 N 回合:红方撑满 20 整回合 => 红胜
	var m2 := _new_match()
	m2.rules.win_conditions.clear()
	m2.rules.win_conditions.append(RuleSet.WinCondition.from_dict(
		{"id": "survive", "type": "survive_rounds", "faction": "red", "rounds": 20}))
	m2.state.full_rounds = 19
	_check(WinCond.evaluate(m2.state, m2.rules) == WinCond.Result.ONGOING,
		"survive: ongoing at round 19")
	m2.state.full_rounds = 20
	_check(WinCond.evaluate(m2.state, m2.rules) == WinCond.Result.RED_WIN,
		"survive: red wins at round 20")
	# 3. 限回合子力分:回合耗尽,红子力高 => 红胜
	var m3 := _new_match()
	m3.rules.win_conditions.clear()
	m3.rules.win_conditions.append(RuleSet.WinCondition.from_dict(
		{"id": "score", "type": "turn_limit_score", "rounds": 40}))
	m3.state.full_rounds = 39
	_check(WinCond.evaluate(m3.state, m3.rules) == WinCond.Result.ONGOING,
		"turn limit: ongoing before round 40")
	m3.state.full_rounds = 40
	for p in m3.state.pieces:
		if p.faction == "black" and p.type.id in ["ju", "ma", "pao"]:
			p.alive = false   # 红子力占优
	_check(WinCond.evaluate(m3.state, m3.rules) == WinCond.Result.RED_WIN,
		"turn limit: red wins on material at round 40")
	# 4. SET_WIN_CONDITION 替换后立即生效:歼灭条件被神换回经典
	var ops := RuleOps.new()
	ops.apply(m3.state, m3.rules, m3.piece_types, "SET_WIN_CONDITION",
		{"conditions": [{"id": "royal", "type": "royal_captured"}]})
	_check(m3.rules.win_conditions.size() == 1 and m3.rules.win_conditions[0].type == "royal_captured",
		"SET_WIN_CONDITION swaps list")
	_check(WinCond.evaluate(m3.state, m3.rules) == WinCond.Result.ONGOING,
		"after swap: same board no longer scores a win")

# ---------------------------------------------------------------- M1 剧本

func _test_scenario() -> void:
	print("[scenario: god trial script]")
	var pack := _ruleops_with_fantasy()
	var m := Match.new(pack["state"], pack["rules"], pack["piece_types"])
	var f := FileAccess.open("res://data/scenarios/god_trial.json", FileAccess.READ)
	_check(f != null, "god_trial.json readable")
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	_check(parsed is Dictionary, "god_trial.json parses")
	var sc := Scenario.from_dict(parsed, RuleOps.new())
	var forecasts := 0
	var triggered := 0
	sc.event_forecast.connect(func(_t: String) -> void: forecasts += 1)
	sc.event_triggered.connect(func(_l: RuleOps.Log, _t: String) -> void: triggered += 1)
	m.scenario = sc
	# 逐回合推进:首整回合红炮横移、黑卒 (8,3) 南下让出弓箭手落点;
	# 之后双炮横向往返((2,7)↔(0,7) / (1,2)↔(0,2)),每步恒合法可重复。
	# 事件时序:黑方第 k 步结束 => full_rounds=k,round_now=k+1;
	# turn=N 事件在黑第 N-1 步后触发。首回合 + 10 往返 = full_rounds 11
	# => turn≤11 的事件全部触发(造骑士/隆山/断路/神谕/改写胜负),
	# turn=13 未触发 => 剧本未演完
	var red_pao := _piece(m.state, "red", 1, 7)
	var black_pao := _piece(m.state, "black", 1, 2)
	var black_bing := _piece(m.state, "black", 8, 3)
	m.try_move(red_pao, 2, 7)          # 首回合红:炮横移让出 0/1 列滑道
	m.try_move(black_bing, 8, 4)       # 首回合黑:卒南下让出 (8,3)
	var rounds := 1
	while rounds < 11 and m.result == WinCond.Result.ONGOING:
		var rx := 0 if rounds % 2 == 0 else 1
		if m.try_move(red_pao, rx, 7) == null:
			break
		if m.try_move(black_pao, 1 - rx, 2) == null:
			break
		rounds += 1
	# 第 3 回合事件(黑骑士降临)应已触发
	_check(triggered >= 1, "scenario events triggered (got %d)" % triggered)
	_check(forecasts >= 1, "scenario forecasts emitted (got %d)" % forecasts)
	_check(m.state.piece_at(4, 4) != null and m.state.piece_at(4, 4).faction == "black",
		"god-summoned knight present at (4,4)")
	# 第 11 回合:胜负条件被改写为歼灭红兵 + 吃将
	var cond_types := []
	for wc in m.rules.win_conditions:
		cond_types.append(wc.type)
	_check(cond_types.has("annihilation") and cond_types.has("royal_captured"),
		"win conditions rewritten by script (types=%s)" % str(cond_types))
	_check(m.state.board.cell(4, 5).elevation == 2, "hill raised at (4,5) by script")
	_check(not sc.finished(), "scenario has more events pending")



func _ruleops_with_fantasy() -> Dictionary:
	# 经典盘 + 幻想棋子类型合并(piece_types 表扩展)
	var pack := _load()
	var fantasy := PackLoader.load_pack("res://data/packs/god_fantasy")
	for key in fantasy["piece_types"].keys():
		pack["piece_types"][key] = fantasy["piece_types"][key]
	return pack

func _test_ruleops() -> void:
	print("[ruleops: add piece / modify cell / temp rule]")
	var pack := _ruleops_with_fantasy()
	var m := Match.new(pack["state"], pack["rules"], pack["piece_types"])
	var ops := RuleOps.new()
	# 神凭空造黑骑士 (4,4)
	var ok1 := ops.apply(m.state, m.rules, m.piece_types, "ADD_PIECE",
		{"type_id": "knight", "faction": "black", "x": 4, "y": 4})
	_check(ok1 != null, "god summons knight at (4,4)")
	var knight := m.state.piece_at(4, 4)
	_check(knight != null and knight.faction == "black", "knight on board")
	# 骑士 tactics 经济:可移动 + 可攻击各一次
	var knight_moves := MoveGen.piece_moves(m.state, knight)
	_check(knight_moves.size() > 0, "knight has rider moves (no leg-block)")
	m.state.turn = "black"
	var actions := m.legal_moves_for(knight)
	var has_move := false
	for a in actions:
		if a.is_move():
			has_move = true
	_check(has_move, "knight lists MOVE actions")
	# 神改格:(5,6) 隆起高山 elevation=2
	var ok2 := ops.apply(m.state, m.rules, m.piece_types, "MODIFY_CELL",
		{"x": 5, "y": 6, "elevation": 2})
	_check(ok2 != null, "god raises hill at (5,6)")
	_check(m.state.board.cell(5, 6).elevation == 2, "hill elevation recorded")
	# 神颁布临时规则
	var ok3 := ops.apply(m.state, m.rules, m.piece_types, "ADD_TEMP_RULE",
		{"id": "no_pao_cross_river", "duration": 3})
	_check(ok3 != null and m.rules.temp_rules.has("no_pao_cross_river"),
		"temp rule published")

func _test_ruleops_undo() -> void:
	print("[ruleops: undo]")
	var pack := _ruleops_with_fantasy()
	var m := Match.new(pack["state"], pack["rules"], pack["piece_types"])
	var ops := RuleOps.new()
	ops.apply(m.state, m.rules, m.piece_types, "ADD_PIECE",
		{"type_id": "mage", "faction": "black", "x": 4, "y": 4})
	ops.apply(m.state, m.rules, m.piece_types, "MODIFY_CELL",
		{"x": 5, "y": 6, "elevation": 2})
	ops.apply(m.state, m.rules, m.piece_types, "ADD_TEMP_RULE",
		{"id": "no_pao_cross_river", "duration": 3})
	ops.apply(m.state, m.rules, m.piece_types, "SET_WIN_CONDITION",
		{"types": ["royal_captured"]})
	ops.apply(m.state, m.rules, m.piece_types, "NERF_PIECE",
		{"x": 0, "y": 9, "field": "value", "value": 1.0})
	# 逆序全撤
	for i in 5:
		_check(ops.undo_last(m.state, m.rules), "ruleop undo #%d" % (5 - i))
	_check(m.state.piece_at(4, 4) == null, "mage removed after undo")
	_check(m.state.board.cell(5, 6).elevation == 0, "hill flattened after undo")
	_check(not m.rules.temp_rules.has("no_pao_cross_river"), "temp rule revoked")
	_check(m.rules.win_conditions.size() == 3, "win conditions restored")
	_check(m.piece_types["ju"].value == 9.0, "chariot value restored")
	_check(ops.undo_last(m.state, m.rules) == false, "nothing left to undo")

# ---------------------------------------------------------------- M1 α-β AI

func _test_ai_search() -> void:
	print("[ai search]")
	var m := _new_match()
	var ai := AISearch.new(2)
	var act := ai.pick_action(m.state, m.rules, "red")
	_check(act != null, "AI picks an action at depth 2")
	var legal := false
	for mv in MoveGen.all_legal_moves(m.state, "red"):
		if mv.to_x == act.to_x and mv.to_y == act.to_y and mv.piece == act.piece:
			legal = true
	_check(legal, "AI action is a legal red move")
	# 构造白吃车:黑车 (0,3) 挂在红炮 (1,7) 打击线上?直接构造红车吃黑车
	for p in m.state.pieces:
		if not p.type.royal:
			p.alive = false
	# 盘面:黑将退至 (4,2)(宫内后排,红车 (1,0) 沿 0 行够不着,否则 AI 直接
	# 吃将秒杀),(4,3) 黑卒挡住对将线(否则红车横移暴露对脸被禁);
	# 红车 (1,0) 吃 (0,0) 黑车 = 唯一吃子 => 搜索最优
	var black_jiang := _piece(m.state, "black", 4, 0)
	black_jiang.y = 2
	m.state.pieces.append(Piece.new(m.piece_types["bing"], "black", 4, 3))
	m.state.pieces.append(Piece.new(m.piece_types["ju"], "black", 0, 0))
	var red_ju := Piece.new(m.piece_types["ju"], "red", 1, 0)
	m.state.pieces.append(red_ju)
	m.state.turn = "red"
	var ai2 := AISearch.new(2)
	var act2 := ai2.pick_action(m.state, m.rules, "red")
	_check(act2 != null and act2.piece == red_ju and act2.to_x == 0 and act2.to_y == 0,
		"AI captures hanging chariot")

func _test_ai_search_perf() -> void:
	print("[ai search perf]")
	var m := _new_match()
	var ai := AISearch.new(2)
	var t0 := Time.get_ticks_msec()
	var act := ai.pick_action(m.state, m.rules, "red")
	var ms := Time.get_ticks_msec() - t0
	_check(act != null, "depth-2 search returns a move")
	_check(ms < 2000, "depth-2 full-board search under 2s (took %d ms)" % ms)
	_check(ai.nodes <= AISearch.NODE_CAP, "node cap respected (%d nodes)" % ai.nodes)
	print("  ...depth=2 nodes=%d time=%dms" % [ai.nodes, ms])
