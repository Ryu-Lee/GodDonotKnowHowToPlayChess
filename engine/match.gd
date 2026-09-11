## 对局控制器:串联 movegen/combat/wincond,统一走 Action(移动/攻击)。
## 行动经济:chess = 一步一事(走即吃);tactics = 一回合内移动+攻击各一次。
class_name Match
extends RefCounted

var state: MatchState
var rules: RuleSet
var piece_types: Dictionary
## 完整行动历史(含攻击),悔棋用。
var history: Array[Action] = []
var result: int = WinCond.Result.ONGOING
## 本回合 tactics 棋子已行动记录 {piece_instance_id: {"moved": bool, "attacked": bool}}。
var acted: Dictionary = {}

func _init(s: MatchState, r: RuleSet, ptypes: Dictionary) -> void:
	state = s
	rules = r
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
	if _ends_turn(act.piece, act.kind):
		_pass_turn()
	result = WinCond.evaluate(state, rules)
	return act

## 行动经济闸:tactics 棋子本回合已做过的行动类型不可重复。
func _economy_allows(act: Action) -> bool:
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
## limited 地形消费随重放重新结算(consumed_pass 幂等保证不重复扣)。
func _rebuild_turn_state() -> void:
	acted.clear()
	state.turn = "red"
	state.move_count = 0
	var replayed: Array[Action] = []
	for act in history:
		act.consumed_pass = false
		replayed.append(act)
	history.clear()
	for act in replayed:
		# 纯逻辑回放:不再校验,直接按经济结算
		if act.is_move():
			MoveGen.apply(state, act)
			MoveGen.consume_pass(state, act)
		else:
			Combat.apply_attack(state, act)
		history.append(act)
		if _ends_turn(act.piece, act.kind):
			_pass_turn()

func notation_log() -> Array[String]:
	var out: Array[String] = []
	for act in history:
		out.append(act.notation())
	return out
