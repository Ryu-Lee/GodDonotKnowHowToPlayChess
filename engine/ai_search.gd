## α-β 搜索 AI:与规则引擎同源——不写死任何规则,读同一份局面数据搜索。
## 神改了数据(造子/改地形/削数值),AI 的搜索空间随之变化,零适配成本。
## 性能:搜索内只用伪合法走法(旧版每节点全盘"送将过滤"枚举导致卡死);
## 将死由"将被吃"终局分在搜索中自然涌现;根节点行动仍过引擎合法性闸,
## 保证落子必被 Match 接受。终局检测只走便宜的数据驱动条件 + 节点数兜底。
class_name AISearch
extends RefCounted

const MATE_SCORE := 100000.0
const MOBILITY_WEIGHT := 0.03
## 节点数上限:神造子海时兜底,超出即静态评估,保证 AI 永不卡死。
const NODE_CAP := 20000

var depth: int = 2          # 搜索深度(难度档位)
var nodes: int = 0          # 统计

func _init(d: int = 2) -> void:
	depth = d

## 选出当前方最佳行动(移动或攻击)。无行动返回 null。
func pick_action(state: MatchState, rules: RuleSet, faction: String) -> Action:
	nodes = 0
	var acts := _root_actions(state, rules, faction)
	if acts.is_empty():
		return null
	_sort_actions(state, acts)
	var best: Action = null
	var best_score := -INF
	var alpha := -INF
	for act in acts:
		_do(state, act)
		var score := -_negamax(state, rules, _enemy(faction), depth - 1, -INF, -alpha, 1)
		_undo(state, act)
		if score > best_score:
			best_score = score
			best = act
		if best_score > alpha:
			alpha = best_score
	return best

# ---------------------------------------------------------------- 搜索核心

func _negamax(state: MatchState, rules: RuleSet, faction: String, depth: int,
		alpha: float, beta: float, ply: int) -> float:
	nodes += 1
	var term := _terminal_score(state, rules, faction, ply)
	if not is_nan(term):
		return term
	if depth <= 0 or nodes > NODE_CAP:
		return _evaluate(state, faction)
	var acts := _search_actions(state, faction)
	if acts.is_empty():
		return -MATE_SCORE + ply   # 无路可走 = 负(将死/困毙统一)
	_sort_actions(state, acts)
	var best := -INF
	for act in acts:
		_do(state, act)
		var score := -_negamax(state, rules, _enemy(faction), depth - 1,
			-beta, -alpha, ply + 1)
		_undo(state, act)
		if score > best:
			best = score
		if best > alpha:
			alpha = best
		if alpha >= beta:
			break   # 剪枝
	return best

## 便宜终局检测:将被吃 / 数据驱动歼灭条件。
## 返回 faction(当前行动方)视角的终局分;非终局返回 NAN。
func _terminal_score(state: MatchState, rules: RuleSet, faction: String, ply: int) -> float:
	if state.royal_of(faction) == null:
		return -MATE_SCORE + ply
	if state.royal_of(_enemy(faction)) == null:
		return MATE_SCORE - ply
	for cond in rules.win_conditions:
		if cond.type == "annihilation":
			var tf := String(cond.params.get("faction", ""))
			var types: Array = cond.params.get("types", [])
			if tf.is_empty() or types.is_empty():
				continue
			var any_alive := false
			for p in state.pieces:
				if p.alive and p.faction == tf and types.has(p.type.id):
					any_alive = true
					break
			if not any_alive:
				return (-MATE_SCORE + ply) if tf == faction else (MATE_SCORE - ply)
	return NAN

# ---------------------------------------------------------------- 行动枚举与执行

## 根节点行动:走法过引擎合法性闸(不送将),保证 try_move 必被接受;
## 攻击由 Combat 生成即为合法(攻击不位移,无送将概念)。
func _root_actions(state: MatchState, _rules: RuleSet, faction: String) -> Array[Action]:
	var out: Array[Action] = []
	out.append_array(MoveGen.all_legal_moves(state, faction))
	for p in state.pieces:
		if p.alive and p.faction == faction and p.type.action_economy == "tactics":
			out.append_array(Combat.all_attacks(state, p))
	return out

## 搜索内行动:伪合法走法 + tactics 攻击(不做逐手送将模拟——
## 送将的后果由对方下一手"吃将"终局分回传,标准伪合法搜索做法)。
func _search_actions(state: MatchState, faction: String) -> Array[Action]:
	var out: Array[Action] = []
	out.append_array(MoveGen.all_moves(state, faction))
	for p in state.pieces:
		if p.alive and p.faction == faction and p.type.action_economy == "tactics":
			out.append_array(Combat.all_attacks(state, p))
	return out

## 搜索内执行:模拟落子/攻击。回合翻转由递归换 faction 完成。
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

# ---------------------------------------------------------------- 排序启发

## 吃子/攻击优先(按目标价值降序),提升剪枝率。
## 落点占位查询走一次性快照字典,避免逐个 piece_at 线性扫。
func _sort_actions(state: MatchState, acts: Array[Action]) -> void:
	if acts.size() < 2:
		return
	var occ := {}
	for p in state.pieces:
		if p.alive:
			occ[Vector2i(p.x, p.y)] = p
	acts.sort_custom(func(a: Action, b: Action) -> bool:
		return _ord(occ, a) > _ord(occ, b)
	)

func _ord(occ: Dictionary, act: Action) -> float:
	if act.is_attack():
		if act.target != null:
			return 100.0 + act.target.type.value
		return 1.0   # 溅射地面打击垫底
	var t: Piece = occ.get(Vector2i(act.to_x, act.to_y))
	if t != null:
		return 100.0 + t.type.value   # 走吃(象棋经济)
	return 0.0

# ---------------------------------------------------------------- 评估

## 叶评估(相对 faction 视角):子力 + 残血折价 + 机动性(伪合法走法数差)。
## 不做将军检测(昂贵):将安全由搜索深度的"将被吃"威胁自然体现。
func _evaluate(state: MatchState, faction: String) -> float:
	var score := 0.0
	for p in state.pieces:
		if not p.alive:
			continue
		var v := float(p.type.value)
		if p.type.royal:
			v = 100.0   # 将的价值兜底;其安危由终局分体现
		elif p.type.action_economy == "tactics" and p.type.hp > 1:
			v *= float(p.hp) / float(p.type.hp)   # 残血战术单位折价
		if p.faction == faction:
			score += v
		else:
			score -= v
	var my_mob := MoveGen.all_moves(state, faction).size()
	var foe_mob := MoveGen.all_moves(state, _enemy(faction)).size()
	score += float(my_mob - foe_mob) * MOBILITY_WEIGHT
	return score
