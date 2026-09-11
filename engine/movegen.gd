## 合法走法生成器:引擎核心。
## 走法模型完备集:step / zone_step / leaper / rider(+screen 炮吃)。
## M1:返回 Action(MOVE);passable 接入地形通行规则;视线暴露给 Combat。
class_name MoveGen
extends RefCounted

const MAX_DEPTH_SCAN := 64   # rider 单方向最大滑行格数

## 最近一次 apply 的被吃子(供 Match 记录)。
static var last_captured: Piece = null

## 生成 faction 所有走法(不含送将过滤)。
static func all_moves(state: MatchState, faction: String) -> Array[Action]:
	var out: Array[Action] = []
	for p in state.pieces:
		if p.alive and p.faction == faction:
			out.append_array(piece_moves(state, p))
	return out

## 生成单个棋子的走法。
static func piece_moves(state: MatchState, p: Piece) -> Array[Action]:
	var out: Array[Action] = []
	var pt := p.type
	var board := state.board

	var use_pattern := _oriented_pattern(p, pt.pattern)
	if not pt.crossed_pattern.is_empty() and board.crossed_river(p.faction, p.y):
		use_pattern = _oriented_pattern(p, pt.crossed_pattern)

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
			push_error("Script move type not implemented yet")
	return out

## pattern 朝向校正:数据包 pattern 以黑方视角书写(前进 = +y);红方 y 分量取反。
static func _oriented_pattern(p: Piece, pattern: Array[Vector2i]) -> Array[Vector2i]:
	if p.faction == "black":
		return pattern
	var out: Array[Vector2i] = []
	for v in pattern:
		out.append(Vector2i(v.x, -v.y))
	return out

# ---------------------------------------------------------------- step/zone

static func _try_step(state: MatchState, p: Piece, v: Vector2i, out: Array[Action]) -> void:
	var tx := p.x + v.x
	var ty := p.y + v.y
	if not _zone_ok(state, p, tx, ty):
		return
	if not passable(state, p, tx, ty):
		return
	var target := state.piece_at(tx, ty)
	if target != null and target.faction == p.faction:
		return
	out.append(Action.new(p, tx, ty, Action.Kind.MOVE))

# ---------------------------------------------------------------- leaper(马/象)

static func _try_leap(state: MatchState, p: Piece, v: Vector2i, out: Array[Action]) -> void:
	var tx := p.x + v.x
	var ty := p.y + v.y
	var board := state.board
	if not board.in_bounds(tx, ty):
		return
	if not _zone_ok(state, p, tx, ty):
		return
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
	out.append(Action.new(p, tx, ty, Action.Kind.MOVE))

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

static func _scan_rider(state: MatchState, p: Piece, v: Vector2i, out: Array[Action]) -> void:
	var board := state.board
	var cx := p.x
	var cy := p.y
	var screens := 0
	var screened := false   # 炮已越架:此后空格不再是合法落点
	for i in MAX_DEPTH_SCAN:
		cx += v.x
		cy += v.y
		if not board.in_bounds(cx, cy):
			return
		if not passable(state, p, cx, cy):
			return
		var occ := state.piece_at(cx, cy)
		if occ == null:
			if not screened:
				out.append(Action.new(p, cx, cy, Action.Kind.MOVE))
			continue
		# 有棋子:车直接吃;炮第一个炮架后越过去,第二个炮架后可吃
		elif p.type.capture_mode == "screen":
			screens += 1
			if screens == 2:
				if occ.faction != p.faction:
					out.append(Action.new(p, cx, cy, Action.Kind.MOVE))
				return
			screened = true
			continue
		else:
			if occ.faction != p.faction:
				out.append(Action.new(p, cx, cy, Action.Kind.MOVE))
			return

# ---------------------------------------------------------------- 地形通行(M1)

## 地形通行判定:impassable 恒禁;oneway 只允许沿 pass_dir;limited 检查剩余次数。
## 起点格不做检查(否则会被自己困死)。
## p 预留:将来按棋子类别(飞行单位无视地形等)细分通行。
static func passable(state: MatchState, _p: Piece, tx: int, ty: int) -> bool:
	var board := state.board
	if not board.in_bounds(tx, ty):
		return false
	var c := board.cell(tx, ty)
	match c.pass_rule:
		"impassable":
			return false
		"oneway":
			# 单向:移动向量必须与 pass_dir 一致(马等跳跃按主方向判定)
			return true   # M1 简化:由 limited/teleport 语义细化;先放行,见 pass_dir 检查
		"limited":
			return c.pass_limit > 0 or c.pass_limit < 0
	return true

## 单向通行检查:进入该格的移动向量必须匹配 pass_dir(或其相反,取决于"来向")。
## 语义定义:pass_dir = 允许的通行方向(进入方向)。
static func oneway_ok(state: MatchState, from_x: int, from_y: int, tx: int, ty: int) -> bool:
	var board := state.board
	var c := board.cell(tx, ty)
	if c.pass_rule != "oneway":
		return true
	var d := Vector2i(tx - from_x, ty - from_y)
	# 马步等斜跳:主方向分量判定
	if c.pass_dir.x != 0 and c.pass_dir.y != 0:
		return sign(d.x) == sign(c.pass_dir.x) or sign(d.y) == sign(c.pass_dir.y)
	if c.pass_dir.x != 0:
		return sign(d.x) == sign(c.pass_dir.x)
	return sign(d.y) == sign(c.pass_dir.y)

## 有限次数通过消费(每次实际进入扣 1;扣到 0 后不可通行)。
static func consume_pass(state: MatchState, act: Action) -> void:
	var board := state.board
	if not board.in_bounds(act.to_x, act.to_y):
		return
	var c := board.cell(act.to_x, act.to_y)
	if c.pass_rule == "limited" and c.pass_limit > 0:
		c.pass_limit -= 1

# ---------------------------------------------------------------- 判定辅助

## 区域限制:九宫 / 己方半场。
static func _zone_ok(state: MatchState, p: Piece, tx: int, ty: int) -> bool:
	var board := state.board
	if not board.in_bounds(tx, ty):
		return false
	match p.type.zone:
		"palace_own":
			return board.in_palace(p.faction, tx, ty)
		"own_half":
			if board.river_rows.is_empty():
				return true
			var top: int = board.river_rows[0]
			var bottom: int = board.river_rows[board.river_rows.size() - 1]
			# 黑方半场:黑岸行(top)及以上;红方半场:红岸行(bottom)及以下
			if p.faction == "black":
				return ty <= top
			return ty >= bottom
	return true

## 模拟行动后,faction 的将是否被攻击。
## 覆盖:displace 走法 / tactics 攻击 / 双将对脸(飞将)。
static func is_in_check(state: MatchState, faction: String) -> bool:
	var royal := state.royal_of(faction)
	if royal == null:
		return false
	var enemy: String = "black" if faction == "red" else "red"
	# 飞将(对将):两帅同列且中间无子 => 行动方立即处于被"飞"状态
	if _flying_general_exposed(state, faction, royal):
		return true
	# displace 走法
	for act in all_moves(state, enemy):
		if act.to_x == royal.x and act.to_y == royal.y:
			return true
	# tactics 攻击(近战/远程直接打将)
	for p in state.pieces:
		if p.alive and p.faction == enemy and p.type.action_economy == "tactics":
			for atk in Combat.all_attacks(state, p):
				if atk.target == royal:
					return true
				if atk.target == null and _splash_covers(p, atk, royal):
					return true
	return false

## 双将对脸判定:同列、中间无子。
static func _flying_general_exposed(state: MatchState, faction: String, royal: Piece) -> bool:
	var enemy_royal := state.royal_of("black" if faction == "red" else "red")
	if enemy_royal == null or enemy_royal.x != royal.x:
		return false
	var step := 1 if enemy_royal.y > royal.y else -1
	var y := royal.y + step
	while y != enemy_royal.y:
		if state.piece_at(royal.x, y) != null:
			return false
		y += step
	return true

## splash 打击域是否覆盖 royal(中心 + splash_pattern 相对格)。
static func _splash_covers(p: Piece, atk: Action, royal: Piece) -> bool:
	if atk.to_x == royal.x and atk.to_y == royal.y:
		return true
	for v in p.type.splash_pattern:
		if atk.to_x + v.x == royal.x and atk.to_y + v.y == royal.y:
			return true
	return false

## 应用走法(落子)。返回被吃子。
static func apply(state: MatchState, act: Action) -> Piece:
	last_captured = null
	var occ := state.piece_at(act.to_x, act.to_y)
	if occ != null and occ.faction != act.piece.faction:
		occ.alive = false
		last_captured = occ
		act.captured = occ
	act.piece.x = act.to_x
	act.piece.y = act.to_y
	state.move_count += 1
	return occ

## 撤销走法。
static func undo(state: MatchState, act: Action) -> void:
	act.piece.x = act.from_x
	act.piece.y = act.from_y
	if act.captured != null:
		act.captured.alive = true
		act.captured.x = act.to_x
		act.captured.y = act.to_y
	state.move_count -= 1

## 走法合法性:目标在生成列表中 + 单向/地形检查 + 模拟后不被将。
static func is_legal(state: MatchState, act: Action) -> bool:
	var acts := piece_moves(state, act.piece)
	var found := false
	for a in acts:
		if a.to_x == act.to_x and a.to_y == act.to_y:
			found = true
			break
	if not found:
		return false
	if not oneway_ok(state, act.from_x, act.from_y, act.to_x, act.to_y):
		return false
	var faction := act.piece.faction
	apply(state, act)
	var in_check := is_in_check(state, faction)
	undo(state, act)
	return not in_check

## faction 全部"不送将"合法走法。
static func all_legal_moves(state: MatchState, faction: String) -> Array[Action]:
	var out: Array[Action] = []
	for act in all_moves(state, faction):
		if is_legal(state, act):
			out.append(act)
	return out
