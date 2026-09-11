## 合法走法生成器:引擎核心。
## 走法模型完备集:step / zone_step / leaper / rider(+screen 炮吃)。
## 一切判定只依赖 MatchState + 邻接抽象,不假设渲染。
class_name MoveGen
extends RefCounted

const MAX_DEPTH_SCAN := 64   # rider 单方向最大滑行格数

## 生成 faction 所有合法走法(不含"送将"判定,那是 apply 前的模拟层做的)。
static func all_moves(state: MatchState, faction: String) -> Array[Move]:
	var out: Array[Move] = []
	for p in state.pieces:
		if p.alive and p.faction == faction:
			out.append_array(piece_moves(state, p))
	return out

## 生成单个棋子的走法。
static func piece_moves(state: MatchState, p: Piece) -> Array[Move]:
	var out: Array[Move] = []
	var pt := p.type
	var board := state.board

	# pattern 选择:兵过河后换 crossed_pattern
	var use_pattern := pt.pattern
	if not pt.crossed_pattern.is_empty() and board.crossed_river(p.faction, p.y):
		use_pattern = pt.crossed_pattern

	match pt.move_type:
		"step", "zone_step":
			for v in use_pattern:
				_try_step(state, p, v, out)
		"leaper":
			for v in use_pattern:
				_try_leap(state, p, v, out)
		"rider":
			for v in use_pattern:
				_scan_rider(state, p, v, out)
		"script":
			push_error("Script move type not implemented yet (M1+)")
	return out

# ---------------------------------------------------------------- step/zone

static func _try_step(state: MatchState, p: Piece, v: Vector2i, out: Array[Move]) -> void:
	var tx := p.x + v.x
	var ty := p.y + v.y
	if not _zone_ok(state, p, tx, ty):
		return
	if not _passable(state, p, tx, ty):
		return
	var target := state.piece_at(tx, ty)
	if target != null and target.faction == p.faction:
		return
	out.append(Move.new(p, tx, ty))

# ---------------------------------------------------------------- leaper(马/象)

static func _try_leap(state: MatchState, p: Piece, v: Vector2i, out: Array[Move]) -> void:
	var tx := p.x + v.x
	var ty := p.y + v.y
	var board := state.board
	if not board.in_bounds(tx, ty):
		return
	if not _zone_ok(state, p, tx, ty):
		return
	# 阻挡判定:蹩马腿 / 塞象眼
	for blocker_id in p.type.blockers:
		var leg := _blocker_offset(blocker_id, v)
		if leg != Vector2i.ZERO:
			var lx: int = p.x + leg.x
			var ly: int = p.y + leg.y
			if state.piece_at(lx, ly) != null:
				return
	var target := state.piece_at(tx, ty)
	if target != null and target.faction == p.faction:
		return
	out.append(Move.new(p, tx, ty))

## 阻挡格偏移:马腿 = 方向分量较大的轴的半程;象眼 = 半程点。
static func _blocker_offset(blocker_id: String, v: Vector2i) -> Vector2i:
	match blocker_id:
		"ma_leg":
			if abs(v.x) > abs(v.y):
				return Vector2i(sign(v.x) * 1, 0)
			return Vector2i(0, sign(v.y) * 1)
		"xiang_eye":
			return Vector2i(v.x / 2, v.y / 2)
	return Vector2i.ZERO

# ---------------------------------------------------------------- rider(车/炮)

static func _scan_rider(state: MatchState, p: Piece, v: Vector2i, out: Array[Move]) -> void:
	var board := state.board
	var cx := p.x
	var cy := p.y
	var screens := 0    # 已越过的炮架数
	for i in MAX_DEPTH_SCAN:
		cx += v.x
		cy += v.y
		if not board.in_bounds(cx, cy):
			return
		if not _passable(state, p, cx, cy):
			return
		var occ := state.piece_at(cx, cy)
		if occ == null:
			out.append(Move.new(p, cx, cy))
			continue
		# 有棋子:车直接吃;炮第一个炮架后越过去,第二个炮架后可吃
		if p.type.capture_mode == "screen":
			screens += 1
			if screens == 2:
				if occ.faction != p.faction:
					out.append(Move.new(p, cx, cy))
				return
			continue
		if occ.faction != p.faction:
			out.append(Move.new(p, cx, cy))
		return

# ---------------------------------------------------------------- 判定辅助

## 区域限制:九宫 / 己方半场 / 兵过河前只许直行。
static func _zone_ok(state: MatchState, p: Piece, tx: int, ty: int) -> bool:
	var board := state.board
	if not board.in_bounds(tx, ty):
		return false
	match p.type.zone:
		"palace_own":
			return board.in_palace(p.faction, tx, ty)
		"own_half":
			# 象不过河:黑方只能在 0..river_top,红方只能在 river_bottom..height-1
			if board.river_rows.is_empty():
				return true
			var top: int = board.river_rows[0]
			var bottom: int = board.river_rows[board.river_rows.size() - 1]
			if p.faction == "black":
				return ty <= top
			return ty >= bottom
		"forward_only_before_cross":
			# 过河前只允许沿朝向走(zone 已由 crossed_pattern 接管横向,这里只防倒退)
			return true
	return true

## 地形通行(M0 恒通过;地形系统 M1 接入,此处是接口保证)。
static func _passable(_state: MatchState, _p: Piece, _tx: int, _ty: int) -> bool:
	return true

## 模拟走一步后,faction 的将是否被攻击(用于送将/将死判定)。
static func is_in_check(state: MatchState, faction: String) -> bool:
	var royal := state.royal_of(faction)
	if royal == null:
		return false
	var enemy: String = "black" if faction == "red" else "red"
	for mv in all_moves(state, enemy):
		if mv.to_x == royal.x and mv.to_y == royal.y:
			return true
	return false

## 应用走法(真正落子)。返回被吃棋子。不验证合法性——调用方先验。
static func apply(state: MatchState, mv: Move) -> Piece:
	mv.captured = state.piece_at(mv.to_x, mv.to_y)
	if mv.captured != null:
		mv.captured.alive = false
	mv.piece.x = mv.to_x
	mv.piece.y = mv.to_y
	state.move_count += 1
	state.turn = "black" if state.turn == "red" else "red"
	return mv.captured

## 撤销走法(悔棋/模拟回滚)。
static func undo(state: MatchState, mv: Move) -> void:
	mv.piece.x = mv.from_x
	mv.piece.y = mv.from_y
	if mv.captured != null:
		mv.captured.alive = true
		mv.captured.x = mv.to_x
		mv.captured.y = mv.to_y
	state.move_count -= 1
	state.turn = "black" if state.turn == "red" else "red"

## 走法合法性:边界内 + 目标无己方 + 模拟后己方不被将(对将也算被将)。
static func is_legal(state: MatchState, mv: Move) -> bool:
	var mvs := piece_moves(state, mv.piece)
	var found := false
	for m in mvs:
		if m.to_x == mv.to_x and m.to_y == mv.to_y:
			found = true
			break
	if not found:
		return false
	var faction := mv.piece.faction
	apply(state, mv)
	var in_check := is_in_check(state, faction)
	undo(state, mv)
	return not in_check

## faction 的全部"不送将"合法走法。
static func all_legal_moves(state: MatchState, faction: String) -> Array[Move]:
	var out: Array[Move] = []
	for mv in all_moves(state, faction):
		if is_legal(state, mv):
			out.append(mv)
	return out
