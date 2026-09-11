## 胜负判定:按 RuleSet 的 win_condition_types 顺序求值。
## 经典规则:吃掉对方将 / 将死 / 困毙(无合法走法判负)。
class_name WinCond
extends RefCounted

enum Result { ONGOING, RED_WIN, BLACK_WIN, DRAW }

static func evaluate(state: MatchState, _rules: RuleSet) -> int:
	# 1. 将被吃(royal 不存活)
	var red_royal := state.royal_of("red")
	var black_royal := state.royal_of("black")
	if red_royal == null:
		return Result.BLACK_WIN
	if black_royal == null:
		return Result.RED_WIN

	# 2. 当前方无合法走法 => 当前方负(将死与困毙统一)
	var side := state.turn
	var moves := MoveGen.all_legal_moves(state, side)
	if moves.is_empty():
		return Result.BLACK_WIN if side == "red" else Result.RED_WIN

	return Result.ONGOING

static func result_name(r: int) -> String:
	match r:
		Result.RED_WIN: return "红方胜"
		Result.BLACK_WIN: return "黑方胜"
		Result.DRAW: return "和棋"
	return "对局中"
