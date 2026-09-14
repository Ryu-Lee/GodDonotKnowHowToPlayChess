## 神谕管线:对局中改写规则的操作(RuleOp)统一入口。
## 一切"神耍赖"最终都落到这里:引擎只认数据,不认剧本。
## 每个 op 返回一条日志(供演出层播报);undo 逆序回滚。
class_name RuleOps
extends RefCounted

## 一次神谕的执行记录(带逆操作所需的最小快照)。
class Log extends RefCounted:
	var op: String = ""            # RuleOp 类型
	var payload: Dictionary = {}   # 原始参数
	var rollback: Dictionary = {}  # 逆操作所需现场快照

## 预告阶段:M1 预留(演出层在颁布前 1 回合给征兆)。
signal decree_forecast(op: Log)

var logs: Array[Log] = []

# ---------------------------------------------------------------- 执行入口

## 执行一条神谕。params 见各 _do_* 实现;失败返回 null。
func apply(
	state: MatchState, rules: RuleSet, piece_types: Dictionary,
	op: String, params: Dictionary
) -> Log:
	var entry := Log.new()
	entry.op = op
	entry.payload = params.duplicate()
	var ok := false
	match op:
		"ADD_PIECE":
			ok = _do_add_piece(state, piece_types, params, entry)
		"REMOVE_PIECE":
			ok = _do_remove_piece(state, params, entry)
		"MODIFY_CELL":
			ok = _do_modify_cell(state, params, entry)
		"RESIZE_BOARD":
			ok = _do_resize_board(state, params, entry)
		"ADD_TEMP_RULE":
			ok = _do_add_temp_rule(rules, params, entry)
		"REMOVE_TEMP_RULE":
			ok = _do_remove_temp_rule(rules, params, entry)
		"SET_WIN_CONDITION":
			ok = _do_set_win_condition(rules, params, entry)
		"GRANT_ABILITY":
			ok = _do_grant_ability(state, params, entry)
		"NERF_PIECE":
			ok = _do_nerf_piece(state, params, entry)
		_:
			push_error("Unknown RuleOp: %s" % op)
	if not ok:
		return null
	logs.append(entry)
	return entry

# ---------------------------------------------------------------- 棋子增删

## params: {type_id, faction, x, y}
func _do_add_piece(
	state: MatchState, piece_types: Dictionary, params: Dictionary, entry: Log
) -> bool:
	var pt: PieceType = piece_types.get(String(params.get("type_id", "")))
	if pt == null:
		push_error("ADD_PIECE: unknown type %s" % params.get("type_id"))
		return false
	var x := int(params.get("x", -1))
	var y := int(params.get("y", -1))
	if not state.board.in_bounds(x, y) or state.piece_at(x, y) != null:
		return false
	var p := Piece.new(pt, String(params.get("faction", "black")), x, y)
	state.pieces.append(p)
	entry.rollback = {"piece": p}
	return true

## params: {x, y} 定位棋子;{piece} 直接引用(剧本用)。
func _do_remove_piece(state: MatchState, params: Dictionary, entry: Log) -> bool:
	var p: Piece = params.get("piece")
	if p == null:
		p = state.piece_at(int(params.get("x", -1)), int(params.get("y", -1)))
	if p == null or not p.alive:
		return false
	entry.rollback = {"piece": p, "x": p.x, "y": p.y}
	state.pieces.erase(p)
	return true

# ---------------------------------------------------------------- 棋盘改写

## params: {x, y, elevation?, pass_rule?, pass_dir?, pass_limit?, terrain?}
## 未给的字段不动;rollback 记录改前现场。
func _do_modify_cell(state: MatchState, params: Dictionary, entry: Log) -> bool:
	var x := int(params.get("x", -1))
	var y := int(params.get("y", -1))
	if not state.board.in_bounds(x, y):
		return false
	var c := state.board.cell(x, y)
	entry.rollback = {
		"x": x, "y": y,
		"terrain": c.terrain, "elevation": c.elevation,
		"pass_rule": c.pass_rule,
		"pass_dir": [c.pass_dir.x, c.pass_dir.y],
		"pass_limit": c.pass_limit
	}
	if params.has("terrain"):
		c.terrain = int(params["terrain"])
	if params.has("elevation"):
		c.elevation = int(params["elevation"])
	if params.has("pass_rule"):
		c.pass_rule = String(params["pass_rule"])
	if params.has("pass_dir"):
		var d: Array = params["pass_dir"]
		c.pass_dir = Vector2i(int(d[0]), int(d[1]))
	if params.has("pass_limit"):
		c.pass_limit = int(params["pass_limit"])
	return true

## params: {width, height}:扩容保留旧格;缩容仅当裁掉区域无存活棋子。
func _do_resize_board(state: MatchState, params: Dictionary, entry: Log) -> bool:
	var w := int(params.get("width", 0))
	var h := int(params.get("height", 0))
	var b := state.board
	if w <= 0 or h <= 0 or (w == b.width and h == b.height):
		return false
	entry.rollback = {
		"width": b.width, "height": b.height,
		"cells": b.serialize()["cells"],
		"gone_pieces": _pieces_outside(state, w, h)
	}
	for p in _pieces_outside(state, w, h):
		state.pieces.erase(p)
	b.resize(w, h)
	return true

func _pieces_outside(state: MatchState, w: int, h: int) -> Array[Piece]:
	var out: Array[Piece] = []
	for p in state.pieces:
		if p.alive and (p.x >= w or p.y >= h):
			out.append(p)
	return out

# ---------------------------------------------------------------- 临时规则

## params: {id, duration}:duration <= 0 = 本局有效。
## 生效语义由 rules.temp_rules 消费方(走法/攻击/胜负)自行检查。
func _do_add_temp_rule(rules: RuleSet, params: Dictionary, entry: Log) -> bool:
	var id := String(params.get("id", ""))
	if id.is_empty():
		return false
	entry.rollback = {"had": rules.temp_rules.has(id),
		"old": rules.temp_rules.get(id, {}).duplicate()}
	rules.add_temp_rule(id, int(params.get("duration", 0)))
	return true

## params: {id}
func _do_remove_temp_rule(rules: RuleSet, params: Dictionary, entry: Log) -> bool:
	var id := String(params.get("id", ""))
	entry.rollback = {"had": rules.temp_rules.has(id),
		"old": rules.temp_rules.get(id, {}).duplicate()}
	if not rules.temp_rules.has(id):
		return false
	rules.remove_temp_rule(id)
	return true

## params: {conditions: [{id?, type, ...params}]} 或 {types: ["royal_captured", ...]}(无参简写)
func _do_set_win_condition(rules: RuleSet, params: Dictionary, entry: Log) -> bool:
	var conds: Array = params.get("conditions", [])
	var types: Array = params.get("types", [])
	if conds.is_empty() and types.is_empty():
		return false
	entry.rollback = {"conditions": rules.win_conditions.duplicate()}
	rules.win_conditions.clear()
	if not conds.is_empty():
		for c in conds:
			rules.win_conditions.append(RuleSet.WinCondition.from_dict(c))
	else:
		for t in types:
			var wc := RuleSet.WinCondition.new()
			wc.type = String(t)
			rules.win_conditions.append(wc)
	return true

# ---------------------------------------------------------------- 强化/削弱

## params: {x, y, ability} 或 {piece, ability}:追加技能标记。
func _do_grant_ability(state: MatchState, params: Dictionary, entry: Log) -> bool:
	var p: Piece = params.get("piece")
	if p == null:
		p = state.piece_at(int(params.get("x", -1)), int(params.get("y", -1)))
	if p == null or not p.alive:
		return false
	var ability := String(params.get("ability", ""))
	if ability.is_empty() or p.type.abilities.has(ability):
		return false
	entry.rollback = {"piece_type": p.type, "abilities": p.type.abilities.duplicate()}
	p.type.abilities.append(ability)
	return true

## params: {x, y, field, value} 直接改写棋子类型数值(hp/value/power/range)。
func _do_nerf_piece(state: MatchState, params: Dictionary, entry: Log) -> bool:
	var p: Piece = params.get("piece")
	if p == null:
		p = state.piece_at(int(params.get("x", -1)), int(params.get("y", -1)))
	if p == null or not p.alive:
		return false
	var field := String(params.get("field", ""))
	var value = params.get("value")
	if value == null:
		return false
	var pt := p.type
	entry.rollback = {"piece_type": pt, "field": field, "old": pt.get(field)}
	if not _set_field(pt, field, value):
		entry.rollback = {}
		return false
	return true

func _set_field(pt: PieceType, field: String, value) -> bool:
	match field:
		"hp":
			pt.hp = int(value)
		"value":
			pt.value = float(value)
		"attack_power":
			pt.attack_power = int(value)
		"attack_range":
			pt.attack_range = int(value)
		_:
			push_error("NERF_PIECE: unsupported field %s" % field)
			return false
	return true

# ---------------------------------------------------------------- 回滚

## 撤销最近一条神谕(演出层的"时间回溯"也可用)。
func undo_last(state: MatchState, rules: RuleSet) -> bool:
	if logs.is_empty():
		return false
	var entry := logs.pop_back() as Log
	match entry.op:
		"ADD_PIECE":
			state.pieces.erase(entry.rollback["piece"])
		"REMOVE_PIECE":
			var rp: Piece = entry.rollback["piece"]
			rp.x = int(entry.rollback["x"])
			rp.y = int(entry.rollback["y"])
			rp.alive = true
			state.pieces.append(rp)
		"MODIFY_CELL":
			_restore_cell(state, entry.rollback)
		"RESIZE_BOARD":
			_restore_board(state, entry.rollback)
		"ADD_TEMP_RULE":
			var rule_id := String(entry.payload.get("id", ""))
			if bool(entry.rollback["had"]):
				rules.temp_rules[rule_id] = entry.rollback["old"]
			else:
				rules.temp_rules.erase(rule_id)
		"REMOVE_TEMP_RULE":
			if bool(entry.rollback["had"]):
				rules.temp_rules[String(entry.payload.get("id", ""))] = entry.rollback["old"]
			else:
				rules.temp_rules.erase(String(entry.payload.get("id", "")))
		"SET_WIN_CONDITION":
			rules.win_conditions = entry.rollback["conditions"]
		"GRANT_ABILITY":
			var pt_g: PieceType = entry.rollback["piece_type"]
			pt_g.abilities = entry.rollback["abilities"]
		"NERF_PIECE":
			var pt_n: PieceType = entry.rollback["piece_type"]
			_set_field(pt_n, String(entry.rollback["field"]), entry.rollback["old"])
	return true

func _restore_cell(state: MatchState, rb: Dictionary) -> void:
	var x := int(rb["x"])
	var y := int(rb["y"])
	if not state.board.in_bounds(x, y):
		return
	var c := state.board.cell(x, y)
	c.terrain = int(rb["terrain"])
	c.elevation = int(rb["elevation"])
	c.pass_rule = String(rb["pass_rule"])
	var d: Array = rb["pass_dir"]
	c.pass_dir = Vector2i(int(d[0]), int(d[1]))
	c.pass_limit = int(rb["pass_limit"])

func _restore_board(state: MatchState, rb: Dictionary) -> void:
	var w := int(rb["width"])
	var h := int(rb["height"])
	state.board.resize(w, h)
	for cd in rb["cells"]:
		var x := int(cd["x"])
		var y := int(cd["y"])
		var c := state.board.cell(x, y)
		c.terrain = int(cd["terrain"])
		c.elevation = int(cd["elevation"])
		c.pass_rule = String(cd["pass_rule"])
		var dir: Array = cd["pass_dir"]
		c.pass_dir = Vector2i(int(dir[0]), int(dir[1]))
		c.pass_limit = int(cd["pass_limit"])
	for p in rb["gone_pieces"]:
		p.alive = true
		state.pieces.append(p)

## 神谕日志摘要(演出层公告用)。
func announce() -> Array[String]:
	var out: Array[String] = []
	for entry in logs:
		out.append("%s %s" % [entry.op, JSON.stringify(entry.payload)])
	return out
