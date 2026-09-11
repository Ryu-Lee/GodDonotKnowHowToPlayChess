## 规则集:从 rules.json 解析;持有临时规则与胜负条件。
## M0 仅实现经典规则;temp_rules/RuleOp 管线为 M1 预留接口。
class_name RuleSet
extends RefCounted

var id: String = ""
var display_name: String = ""
## 已启用的临时规则 id 列表(M1)。
var temp_rules: Array[String] = []
## 胜负条件类型列表,按顺序求值。
var win_condition_types: Array[String] = []

static func from_dict(d: Dictionary) -> RuleSet:
	var rs := RuleSet.new()
	rs.id = d.get("rule_set_id", "")
	rs.display_name = d.get("name", "")
	for wc in d.get("win_conditions", []):
		rs.win_condition_types.append(String(wc.get("type", "")))
	return rs

func clone() -> RuleSet:
	var rs := RuleSet.new()
	rs.id = id
	rs.display_name = display_name
	rs.temp_rules = temp_rules.duplicate()
	rs.win_condition_types = win_condition_types.duplicate()
	return rs
