## 规则集:从 rules.json 解析;持有临时规则与胜负条件(带参数,数据驱动)。
## 神谕(SET_WIN_CONDITION / ADD_TEMP_RULE / REMOVE_TEMP_RULE)直接改写这里,判定随之变化。
class_name RuleSet
extends RefCounted

## 胜负条件:type + params(求值语义见 WinCond)。
class WinCondition extends RefCounted:
	var id: String = ""
	var type: String = ""
	var params: Dictionary = {}

	static func from_dict(d: Dictionary) -> WinCondition:
		var wc := WinCondition.new()
		wc.id = String(d.get("id", ""))
		wc.type = String(d.get("type", ""))
		var p: Dictionary = d.get("params", {})
		# 允许平铺参数(annihilation.faction 等直接写在条件上)
		for key in d.keys():
			if key in ["id", "type", "params"]:
				continue
			p[key] = d[key]
		wc.params = p
		return wc

var id: String = ""
var display_name: String = ""
## 临时规则:{id: {duration: int}} duration<=0 = 本局有效;每整回合结束递减。
var temp_rules: Dictionary = {}
## 胜负条件列表,按顺序求值。
var win_conditions: Array[WinCondition] = []

## 占领驻留计数(动态状态):{faction: rounds_held}。
var occupy_counters: Dictionary = {}

static func from_dict(d: Dictionary) -> RuleSet:
	var rs := RuleSet.new()
	rs.id = d.get("rule_set_id", "")
	rs.display_name = d.get("name", "")
	for tr in d.get("temp_rules", []):
		if tr is Dictionary:
			rs.add_temp_rule(String(tr.get("id", "")), int(tr.get("duration", 0)))
		else:
			rs.add_temp_rule(String(tr), 0)
	for wc in d.get("win_conditions", []):
		rs.win_conditions.append(WinCondition.from_dict(wc))
	return rs

func clone() -> RuleSet:
	var rs := RuleSet.new()
	rs.id = id
	rs.display_name = display_name
	rs.temp_rules = temp_rules.duplicate(true)
	rs.win_conditions = win_conditions.duplicate()
	return rs

# ---------------------------------------------------------------- 临时规则

func add_temp_rule(rule_id: String, duration: int) -> void:
	temp_rules[rule_id] = {"duration": duration}

func remove_temp_rule(rule_id: String) -> void:
	temp_rules.erase(rule_id)

func has_temp_rule(rule_id: String) -> bool:
	return temp_rules.has(rule_id)

## 整回合结束:递减所有带期限临时规则;归零撤销。
func tick_temp_rules() -> void:
	var expired: Array[String] = []
	for rule_id in temp_rules.keys():
		var d: Dictionary = temp_rules[rule_id]
		var dur := int(d.get("duration", 0))
		if dur > 0:
			dur -= 1
			d["duration"] = dur
			if dur == 0:
				expired.append(rule_id)
	for rule_id in expired:
		temp_rules.erase(rule_id)
