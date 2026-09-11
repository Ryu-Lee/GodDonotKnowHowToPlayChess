## 极简 AI(M0):吃子优先的随机走法。数据同源——只依赖 movegen,神改规则后自动适配。
## 真正的 α-β 搜索 AI 在 M1 落地。
class_name AIRandom
extends RefCounted

static func pick_move(state: MatchState, faction: String, rng: RandomNumberGenerator) -> Move:
	var moves := MoveGen.all_legal_moves(state, faction)
	if moves.is_empty():
		return null
	# 简单启发:能吃子吃最大价值子,否则随机
	var best: Move = null
	var best_val := -1.0
	for mv in moves:
		var target := state.piece_at(mv.to_x, mv.to_y)
		if target != null and target.type.value > best_val:
			best_val = target.type.value
			best = mv
	if best != null:
		return best
	return moves[rng.randi_range(0, moves.size() - 1)]
