## 对局控制器:串联 movegen/wincond,提供走子 API、悔棋、记谱。
class_name Match
extends RefCounted

var state: MatchState
var rules: RuleSet
var piece_types: Dictionary
var history: Array[Move] = []
var result: int = WinCond.Result.ONGOING

func _init(s: MatchState, r: RuleSet, ptypes: Dictionary) -> void:
	state = s
	rules = r
	piece_types = ptypes

func try_move(piece: Piece, to_x: int, to_y: int) -> Move:
	if result != WinCond.Result.ONGOING:
		return null
	if piece.faction != state.turn:
		return null
	var mv := Move.new(piece, to_x, to_y)
	if not MoveGen.is_legal(state, mv):
		return null
	MoveGen.apply(state, mv)
	history.append(mv)
	result = WinCond.evaluate(state, rules)
	return mv

func legal_moves_for(piece: Piece) -> Array[Move]:
	if result != WinCond.Result.ONGOING or piece.faction != state.turn:
		return []
	return MoveGen.all_legal_moves(state, piece.faction).filter(
		func(m: Move) -> bool: return m.piece == piece
	)

func undo_last() -> bool:
	if history.is_empty():
		return false
	var mv := history.pop_back() as Move
	MoveGen.undo(state, mv)
	result = WinCond.Result.ONGOING
	return true

func notation_log() -> Array[String]:
	var out: Array[String] = []
	for mv in history:
		out.append(mv.to_notation())
	return out
