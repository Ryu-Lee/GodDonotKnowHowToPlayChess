## 胜负判定:按 RuleSet.win_conditions 顺序求值,完全数据驱动。
## 神谕 SET_WIN_CONDITION 替换列表后,判定立即随新条件走——引擎不写死任何胜负。
class_name WinCond
extends RefCounted

enum Result { ONGOING, RED_WIN, BLACK_WIN, DRAW }

## 按条件列表顺序求值,首个命中者生效;无命中 = 对局中。
static func evaluate(state: MatchState, rules: RuleSet) -> int:
	for cond in rules.win_conditions:
		var r := _eval_one(state, rules, cond)
		if r != Result.ONGOING:
			return r
	return Result.ONGOING

## 求值单个胜负条件。faction 参数(如有)指定"该条件由谁达成"。
static func _eval_one(state: MatchState, rules: RuleSet, cond: RuleSet.WinCondition) -> int:
	match cond.type:
		"royal_captured":
			return _royal_captured(state)
		"royal_no_legal_moves_under_check":
			return _no_moves_lose(state, true)
		"no_legal_moves_lose":
			return _no_moves_lose(state, false)
		"annihilation":
			return _annihilation(state, cond.params)
		"occupy_hold":
			return _occupy_hold(state, rules, cond.params)
		"survive_rounds":
			return _survive_rounds(state, rules, cond.params)
		"turn_limit_score":
			return _turn_limit_score(state, rules, cond.params)
		_:
			push_error("Unknown win condition type: %s" % cond.type)
			return Result.ONGOING

static func _royal_captured(state: MatchState) -> int:
	if state.royal_of("red") == null:
		return Result.BLACK_WIN
	if state.royal_of("black") == null:
		return Result.RED_WIN
	return Result.ONGOING

## 当前方无合法行动 => 负(将死与困毙统一:under_check 区分仅用于语义播报)。
## 合法行动含 tactics 棋子的攻击(chess 走法为空但仍有攻击可做时不判负)。
static func _no_moves_lose(state: MatchState, _under_check: bool) -> int:
	var side := state.turn
	if not _has_any_action(state, side):
		return Result.BLACK_WIN if side == "red" else Result.RED_WIN
	return Result.ONGOING

## 全部合法行动(chess 走法 + tactics 攻击),与 Match/AISearch 同源。
static func _has_any_action(state: MatchState, faction: String) -> bool:
	if not MoveGen.all_legal_moves(state, faction).is_empty():
		return true
	for p in state.pieces:
		if p.alive and p.faction == faction and p.type.action_economy == "tactics":
			if not Combat.all_attacks(state, p).is_empty():
				return true
	return false

## 歼灭:指定方的指定类型棋子全灭 => 攻击方胜。
## params: {faction: "black", types: ["bing"]} —— 黑方全兵被吃 => 红胜。
static func _annihilation(state: MatchState, params: Dictionary) -> int:
	var target_faction := String(params.get("faction", ""))
	var types: Array = params.get("types", [])
	if target_faction.is_empty() or types.is_empty():
		return Result.ONGOING
	for p in state.pieces:
		if p.alive and p.faction == target_faction and types.has(p.type.id):
			return Result.ONGOING
	# 目标方指定类型全灭:对面胜
	return Result.BLACK_WIN if target_faction == "red" else Result.RED_WIN

## 占领:指定方棋子驻留指定格满 N 回合 => 该方胜。
## params: {faction: "red", cells: [[4,0]], rounds: 3}
## 回合计数由 RuleSet 侧的动态计数表 rules.occupy_counters 维护(Match 每回合结算调用 tick)。
static func _occupy_hold(state: MatchState, rules: RuleSet, params: Dictionary) -> int:
	var faction := String(params.get("faction", ""))
	var cells: Array = params.get("cells", [])
	var rounds := int(params.get("rounds", 1))
	if faction.is_empty() or cells.is_empty():
		return Result.ONGOING
	var held := true
	for c in cells:
		var x := int(c[0])
		var y := int(c[1])
		var occ := state.piece_at(x, y)
		if occ == null or occ.faction != faction:
			held = false
			break
	if not held:
		rules.occupy_counters.erase(faction)
		return Result.ONGOING
	rules.occupy_counters[faction] = int(rules.occupy_counters.get(faction, 0)) + 1
	if int(rules.occupy_counters[faction]) >= rounds:
		return Result.RED_WIN if faction == "red" else Result.BLACK_WIN
	return Result.ONGOING

## 撑过 N 回合:防守方存活满 N 回合 => 防守方胜(被吃将/无行动仍即时判负)。
## params: {faction: "red", rounds: 20} —— 红方撑过 20 回合 => 红胜。
static func _survive_rounds(state: MatchState, rules: RuleSet, params: Dictionary) -> int:
	var faction := String(params.get("faction", ""))
	var rounds := int(params.get("rounds", 1))
	if faction.is_empty():
		return Result.ONGOING
	if state.royal_of(faction) == null:
		return Result.BLACK_WIN if faction == "red" else Result.RED_WIN
	if state.full_rounds >= rounds:
		return Result.RED_WIN if faction == "red" else Result.BLACK_WIN
	return Result.ONGOING

## 限回合子力分:回合耗尽时按子力总分判胜(不分胜负 = 和)。
## params: {rounds: 40}
static func _turn_limit_score(state: MatchState, rules: RuleSet, params: Dictionary) -> int:
	var rounds := int(params.get("rounds", 1))
	if state.full_rounds < rounds:
		return Result.ONGOING
	var red := _material(state, "red")
	var black := _material(state, "black")
	if red > black:
		return Result.RED_WIN
	if black > red:
		return Result.BLACK_WIN
	return Result.DRAW

static func _material(state: MatchState, faction: String) -> float:
	var total := 0.0
	for p in state.pieces:
		if p.alive and p.faction == faction:
			total += p.type.value
	return total

static func result_name(r: int) -> String:
	match r:
		Result.RED_WIN: return "红方胜"
		Result.BLACK_WIN: return "黑方胜"
		Result.DRAW: return "和棋"
	return "对局中"
