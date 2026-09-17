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
		"walk":
			_scan_walk(state, p, out)
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
	if _temp_rule_blocks(state, p, tx, ty):
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
	if _temp_rule_blocks(state, p, tx, ty):
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
	var depth := p.type.move_range if p.type.move_range > 0 else MAX_DEPTH_SCAN
	for i in depth:
		cx += v.x
		cy += v.y
		if not board.in_bounds(cx, cy):
			return
		if not passable(state, p, cx, cy):
			return
		if _temp_rule_blocks(state, p, cx, cy):
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

# ---------------------------------------------------------------- walk(战棋步行)

## 战棋式移动:正交步进 BFS,曼哈顿距离 <= move_range 的可达空格皆为落点;
## 途中格须通行(地形)+ 无人占据(不可穿子),终点可落在敌格(占据式吃)。
## 与象棋模型的区别:不按 pattern 向量,按"步行距离"衡量机动性,路径可拐弯绕障。
static func _scan_walk(state: MatchState, p: Piece, out: Array[Action]) -> void:
	var board := state.board
	var range := p.type.move_range
	if range <= 0:
		range = MAX_DEPTH_SCAN
	var start := Vector2i(p.x, p.y)
	var dist := {start: 0}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if dist[cur] >= range:
			continue
		for dv in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nxt: Vector2i = cur + dv
			if nxt.x < 0 or nxt.x >= board.width or nxt.y < 0 or nxt.y >= board.height:
				continue
			if dist.has(nxt):
				continue
			# 途经格必须无人:敌我棋子皆挡路(不可穿越)
			var occ := state.piece_at(nxt.x, nxt.y)
			if occ != null:
				# 敌子:可作终点(占据式吃),不继续扩展
				if occ.faction != p.faction:
					var dd: int = dist[cur] + 1
					dist[nxt] = dd
					if dd <= range and passable(state, p, nxt.x, nxt.y) \
							and not _temp_rule_blocks(state, p, nxt.x, nxt.y):
						out.append(Action.new(p, nxt.x, nxt.y, Action.Kind.MOVE))
				continue
			# 空格:通行 + 无临时规则禁令 => 落点,继续扩展
			if not passable(state, p, nxt.x, nxt.y):
				continue
			dist[nxt] = dist[cur] + 1
			if not _temp_rule_blocks(state, p, nxt.x, nxt.y):
				out.append(Action.new(p, nxt.x, nxt.y, Action.Kind.MOVE))
			queue.append(nxt)

# ---------------------------------------------------------------- 临时规则(M1)

## 临时规则 id -> 走法否决回调表。数据驱动:新增规则在此注册判定即可。
## 返回 true = 该走法被临时规则禁止。
static func _temp_rule_blocks(state: MatchState, p: Piece, tx: int, ty: int) -> bool:
	if state.rules == null:
		return false
	for rule_id in state.rules.temp_rules.keys():
		match rule_id:
			"no_pao_cross_river":
				# 本局炮(双方)不可过河:目标是河对岸即禁
				if p.type.id == "pao" and state.board.crossed_river(p.faction, ty):
					return true
			_:
				pass
	return false

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
## 幂等:同一 Action 只消费一次(悔棋重放安全)。
static func consume_pass(state: MatchState, act: Action) -> void:
	if act.consumed_pass:
		return
	var board := state.board
	if not board.in_bounds(act.to_x, act.to_y):
		return
	var c := board.cell(act.to_x, act.to_y)
	if c.pass_rule == "limited" and c.pass_limit > 0:
		c.pass_limit -= 1
		act.consumed_pass = true

## 消费返还(悔棋)。
static func refund_pass(state: MatchState, act: Action) -> void:
	if not act.consumed_pass:
		return
	var board := state.board
	if not board.in_bounds(act.to_x, act.to_y):
		act.consumed_pass = false
		return
	var c := board.cell(act.to_x, act.to_y)
	if c.pass_rule == "limited":
		c.pass_limit += 1
	act.consumed_pass = false

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
## 注意:M1 起不再用于走法合法性过滤(允许败着);保留供演出层"将军"播报等。
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
	return false

## 双将对脸判定:同列、中间无子。
static func _flying_general_exposed(state: MatchState, faction: String, royal: Piece) -> bool:
	var enemy_royal := state.royal_of("black" if faction == "red" else "red")
	if enemy_royal == null or royal == null or enemy_royal.x != royal.x:
		return false
	var step := 1 if enemy_royal.y > royal.y else -1
	var y := royal.y + step
	while y != enemy_royal.y:
		if state.piece_at(royal.x, y) != null:
			return false
		y += step
	return true

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

## 走法合法性:目标在生成列表中 + 单向/地形检查 + 不造成双将对脸。
## 注意:不阻止"走完被将军"的送将步——玩家有权走出败着,
## 将被吃时由 royal_captured 胜负条件直接结算(将死=无合法走法+被将,仍判负)。
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
	# 双将对脸(飞将)是棋盘结构规则(同蹩马腿),仍禁止:
	# 模拟后己方暴露在对将线上 => 非法
	var faction := act.piece.faction
	apply(state, act)
	var exposed := _flying_general_exposed(state, faction, state.royal_of(faction))
	undo(state, act)
	return not exposed

## faction 全部合法走法(不含送将过滤,见 is_legal 注释)。
static func all_legal_moves(state: MatchState, faction: String) -> Array[Action]:
	var out: Array[Action] = []
	for act in all_moves(state, faction):
		if is_legal(state, act):
			out.append(act)
	return out
