## α-β 搜索 AI:与规则引擎同源——不写死任何规则,读同一份局面数据搜索。
## 神改了数据(造子/改地形/削数值),AI 的搜索空间随之变化,零适配成本。
## 评估函数:子力值(数据驱动 value)+ 机动性 + 将安全。
class_name AISearch
extends RefCounted

const MATE_SCORE := 100000.0

var depth: int = 2          # 搜索深度(难度档位)
var nodes: int = 0          # 统计

func _init(d: int = 2) -> void:
	depth = d

## 选出当前方最佳行动(移动或攻击)。无行动返回 null。
func pick_action(state: MatchState, rules: RuleSet, faction: String) -> Action:
	nodes = 0
	var best: Action = null
	var best_score := -INF
	var acts := _root_actions(state, rules, faction)
	for act in acts:
		_do(state, act)
		var score := -_negamax(state, rules, _enemy(faction), depth - 1, -INF, INF)
		_undo(state, act)
		if score > best_score:
			best_score = score
			best = act
	return best

# ---------------------------------------------------------------- 搜索核心

func _negamax(state: MatchState, rules: RuleSet, faction: String, depth: int,
		alpha: float, beta: float) -> float:
	nodes += 1
	if _terminal(state, rules, faction):
		return -MATE_SCORE   # 当前方无将/无路:输
	if depth <= 0:
		return _evaluate(state, faction)
	var best := -INF
	for act in _root_actions(state, rules, faction):
		_do(state, act)
		var score := -_negamax(state, rules, _enemy(faction), depth - 1, -beta, -alpha)
		_undo(state, act)
		if score > best:
			best = score
		if best > alpha:
			alpha = best
		if alpha >= beta:
			break   # 剪枝
	return best

func _terminal(state: MatchState, rules: RuleSet, faction: String) -> bool:
	# 也将死/困毙统一视为终局:Mate 检测走 WinCond 简化路径
	var r := WinCond.evaluate(state, rules)
	if r != WinCond.Result.ONGOING:
		return true
	return MoveGen.all_legal_moves(state, faction).is_empty() and \
		_tactics_exhausted(state, faction)

## tactics 棋子是否还有攻击可做(chess 棋子无走法即困毙)。
func _tactics_exhausted(state: MatchState, faction: String) -> bool:
	for p in state.pieces:
		if p.alive and p.faction == faction and p.type.action_economy == "tactics":
			if not Combat.all_attacks(state, p).is_empty():
				return false
	return true

# ---------------------------------------------------------------- 行动枚举与执行

## 当前方的全部合法行动(chess 走法 + tactics 移动/攻击)。
## 与 Match.all_legal_actions 同源,但不依赖回合/经济账本(搜索内自行推演)。
func _root_actions(state: MatchState, _rules: RuleSet, faction: String) -> Array[Action]:
	var out: Array[Action] = []
	out.append_array(MoveGen.all_legal_moves(state, faction))
	for p in state.pieces:
		if p.alive and p.faction == faction and p.type.action_economy == "tactics":
			out.append_array(Combat.all_attacks(state, p))
	return out

## 搜索内执行:模拟落子/攻击。回合翻转由调用方在递归里换 faction 完成。
func _do(state: MatchState, act: Action) -> void:
	if act.is_move():
		MoveGen.apply(state, act)
	else:
		Combat.apply_attack(state, act)

func _undo(state: MatchState, act: Action) -> void:
	if act.is_move():
		MoveGen.undo(state, act)
	else:
		Combat.undo_attack(state, act)

func _enemy(faction: String) -> String:
	return "black" if faction == "red" else "red"

# ---------------------------------------------------------------- 评估

## 局面评估(相对 faction 视角):子力 + 机动性 + 将威胁。
func _evaluate(state: MatchState, faction: String) -> float:
	var score := 0.0
	for p in state.pieces:
		if not p.alive:
			continue
		var v := p.type.value
		if p.type.royal:
			v = 100.0   # 将的安全由威胁项度量,这里只兜底
		if p.faction == faction:
			score += v
		else:
			score -= v
	# 机动性:合法走法数差(轻量启发,粗略但同源)
	var my_moves := MoveGen.all_moves(state, faction).size()
	var foe_moves := MoveGen.all_moves(state, _enemy(faction)).size()
	score += (my_moves - foe_moves) * 0.05
	# 将威胁:被将军方扣分
	if MoveGen.is_in_check(state, faction):
		score -= 5.0
	if MoveGen.is_in_check(state, _enemy(faction)):
		score += 5.0
	return score
