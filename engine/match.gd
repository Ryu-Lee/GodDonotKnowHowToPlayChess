## 对局控制器:串联 movegen/combat/wincond,统一走 Action(移动/攻击)。
## 行动经济:chess = 一步一事(走即吃);tactics = 一回合内移动+攻击各一次。
class_name Match
extends RefCounted

var state: MatchState
var rules: RuleSet
var piece_types: Dictionary
## 神的剧本(可选):回合开始神谕阶段由此触发。
var scenario: Scenario = null
## 完整行动历史(含攻击),悔棋用。
var history: Array[Action] = []
var result: int = WinCond.Result.ONGOING
## 本回合 tactics 棋子已行动记录 {piece_instance_id: {"moved": bool, "attacked": bool}}。
var acted: Dictionary = {}
## 本回合已行动的棋子(同回合只能操作同一棋子: tactics 棋子移动/攻击后,
## 本回合内不可再换其他棋子行动;回合结束清空)。null = 本回合尚未有棋子行动。
var turn_piece: Piece = null

func _init(s: MatchState, r: RuleSet, ptypes: Dictionary) -> void:
	state = s
	rules = r
	state.rules = r
	piece_types = ptypes

# ---------------------------------------------------------------- 回合结构

## 行动后是否结束本方回合。
func _ends_turn(p: Piece, kind: int) -> bool:
	if p.type.action_economy == "chess":
		return true
	# tactics:移动+攻击各一次;用完则结束
	var rec: Dictionary = acted.get_or_add(p.get_instance_id(), {})
	if kind == Action.Kind.MOVE:
		rec["moved"] = true
	else:
		rec["attacked"] = true
	acted[p.get_instance_id()] = rec
	return rec.get("moved", false) and rec.get("attacked", false)

func _pass_turn() -> void:
	acted.clear()
	turn_piece = null
	# 黑方行动结束 = 整回合结束:临时规则倒计时 + 神谕阶段(下一回合开始)
	if state.turn == "black":
		state.full_rounds += 1
		rules.tick_temp_rules()
		if scenario != null:
			scenario.on_round_start(state, rules, piece_types)
	state.turn = "black" if state.turn == "red" else "red"

# ---------------------------------------------------------------- 行动 API

## 提交行动(移动或攻击)。校验合法 → 结算 → 回合推进 → 胜负判定。
## 返回结算后的 Action;拒绝(非法/重复经济/非本回合)返回 null。
func submit(act: Action) -> Action:
	if result != WinCond.Result.ONGOING or act.piece.faction != state.turn:
		return null
	if not _economy_allows(act):
		return null
	if act.is_move():
		if not MoveGen.is_legal(state, act):
			return null
		MoveGen.apply(state, act)
		MoveGen.consume_pass(state, act)
	else:
		if not _is_legal_attack(act):
			return null
		Combat.apply_attack(state, act)
	history.append(act)
	turn_piece = act.piece
	act.round = state.full_rounds + 1   # 1 基回合号(红先手即回合1)
	act.ended_turn = _ends_turn(act.piece, act.kind)
	if act.ended_turn:
		_pass_turn()
	result = WinCond.evaluate(state, rules)
	return act

## 行动经济闸:tactics 棋子本回合已做过的行动类型不可重复;
## 且本回合已有棋子行动时,后续行动必须是同一棋子(单子操作锁)。
func _economy_allows(act: Action) -> bool:
	if turn_piece != null and act.piece != turn_piece:
		return false
	var rec: Dictionary = acted.get_or_add(act.piece.get_instance_id(), {})
	if act.is_move() and rec.get("moved", false):
		return false
	if act.is_attack() and rec.get("attacked", false):
		return false
	return true

## 走子(象棋式便捷封装)。
func try_move(piece: Piece, to_x: int, to_y: int) -> Action:
	return submit(Action.new(piece, to_x, to_y, Action.Kind.MOVE))

## 攻击。
func try_attack(piece: Piece, to_x: int, to_y: int, target: Piece = null) -> Action:
	return submit(Action.new(piece, to_x, to_y, Action.Kind.ATTACK, target))

func _is_legal_attack(act: Action) -> bool:
	var legal := Combat.all_attacks(state, act.piece)
	for a in legal:
		if a.to_x == act.to_x and a.to_y == act.to_y and a.target == act.target:
			return true
	return false

# ---------------------------------------------------------------- 查询

func legal_moves_for(piece: Piece) -> Array[Action]:
	if result != WinCond.Result.ONGOING or piece.faction != state.turn:
		return []
	# 单子操作锁:本回合已有其他棋子行动 => 此棋子不可再动
	if turn_piece != null and piece != turn_piece:
		return []
	var out: Array[Action] = []
	var rec: Dictionary = acted.get_or_add(piece.get_instance_id(), {})
	if not rec.get("moved", false):
		for mv in MoveGen.all_legal_moves(state, piece.faction):
			if mv.piece == piece:
				out.append(Action.new(piece, mv.to_x, mv.to_y, Action.Kind.MOVE))
	if not rec.get("attacked", false):
		out.append_array(Combat.all_attacks(state, piece))
	return out

## 当前方全部合法行动(chess 走法 + tactics 移动/攻击)。
func all_legal_actions(faction: String) -> Array[Action]:
	var out: Array[Action] = []
	if result != WinCond.Result.ONGOING or faction != state.turn:
		return out
	for p in state.pieces:
		if p.alive and p.faction == faction:
			out.append_array(legal_moves_for(p))
	return out

## 死锁兜底:当前方经济耗尽(如 tactics 棋子只攻击且无处可走)又无任何
## 合法行动时,自动弃权过回合。返回 true = 已过手。
func pass_if_stuck() -> bool:
	if result != WinCond.Result.ONGOING:
		return false
	if not all_legal_actions(state.turn).is_empty():
		return false
	_pass_turn()
	result = WinCond.evaluate(state, rules)
	return true

## 悔棋到指定阵营行动前:连续弹出直至重新轮到 faction
## (AI 的应手与玩家的上一手一并撤销,标准"悔我上一手"语义)。
## 返回是否弹出了行动。
func undo_until(faction: String) -> bool:
	var popped := false
	while not history.is_empty():
		if not undo_last():
			break
		popped = true
		if state.turn == faction:
			break
	return popped

# ---------------------------------------------------------------- 悔棋

func undo_last() -> bool:
	if history.is_empty():
		return false
	var act := history.pop_back() as Action
	if act.is_move():
		MoveGen.undo(state, act)
		MoveGen.refund_pass(state, act)
	else:
		Combat.undo_attack(state, act)
	# 回合回退:若该行动没结束回合,回合不变;否则翻回
	# 判定:撤掉后 acted 状态需重建 —— 简化:M1 悔棋回退整个回合边界
	# 通过重放历史重建 acted 与 turn。
	_rebuild_turn_state()
	result = WinCond.Result.ONGOING
	return true

## 重放历史恢复回合状态(悔棋后)。
## limited 地形消费与攻击伤害:重放前按原始结算记录逐条逆序返还
## (否则重放会重复扣通行次数 / 伤害翻倍)。
func _rebuild_turn_state() -> void:
	acted.clear()
	turn_piece = null
	state.move_count = 0
	state.full_rounds = 0   # 回放重计;_pass_turn 的副作用(神谕/倒计时)不重触发
	# 逆序返还所有已消费的 limited 通行,重放时再按当下棋盘状态重新结算
	for act in history:
		if act.is_move():
			MoveGen.refund_pass(state, act)
	# 逆序返还攻击伤害(含反击;位置随 damage_log 复原,重放时再结算)
	for i in range(history.size() - 1, -1, -1):
		var a: Action = history[i]
		if not a.is_move():
			Combat.undo_attack(state, a)
	var replayed: Array[Action] = history.duplicate()
	history.clear()
	# 起始回合 = 首个行动的阵营(悔棋可能弃掉红方全部行动,只剩黑方中途回合)
	state.turn = replayed[0].piece.faction if not replayed.is_empty() else "red"
	for act in replayed:
		# 纯逻辑回放:不再校验,直接按经济结算
		act.consumed_pass = false
		if act.is_move():
			# 被吃子已死仍占坐标:apply 会把 act.captured 覆写为 null
			# (piece_at 跳过死子)=> 先存后还原,否则后续悔棋无法复活被吃子
			var saved_captured := act.captured
			MoveGen.apply(state, act)
			act.captured = saved_captured
			MoveGen.consume_pass(state, act)
		else:
			Combat.apply_attack(state, act)
		history.append(act)
		turn_piece = act.piece
		act.round = state.full_rounds + 1
		act.ended_turn = _ends_turn(act.piece, act.kind)
		if act.ended_turn:
			# 纯翻面 + 回合计数(不走 _pass_turn:重放不重触发神谕/临时规则倒计时)
			if state.turn == "black":
				state.full_rounds += 1
			state.turn = "black" if state.turn == "red" else "red"
			turn_piece = null

func notation_log() -> Array[String]:
	var out: Array[String] = []
	for act in history:
		out.append(act.notation())
	return out
