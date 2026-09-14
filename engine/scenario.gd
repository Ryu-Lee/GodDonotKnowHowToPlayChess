## 剧本驱动器:按回合触发表执行神谕(RuleOps 管线)。
## 神的剧本 AI 单独一层:与棋力 AI 解耦,只负责"何时耍赖"。
## 预告机制:事件触发前 1 回合发 forecast(演出层订阅播报)——耍赖必有预告。
class_name Scenario
extends RefCounted

signal event_forecast(text: String)          # 预告征兆(提前 1 回合)
signal event_triggered(entry: RuleOps.Log, text: String)   # 神谕颁布

## 单条剧本事件。
class Event extends RefCounted:
	var turn: int = 0                  # 触发回合(整回合,黑方行动结束 = +1)
	var forecast: String = ""          # 预告文案
	var ops: Array = []                # [{op, params}]

	static func from_dict(d: Dictionary) -> Event:
		var e := Event.new()
		e.turn = int(d.get("turn", 0))
		e.forecast = String(d.get("forecast", ""))
		for op in d.get("ops", []):
			e.ops.append({
				"op": String(op.get("op", "")),
				"params": op.get("params", {})
			})
		return e

var name: String = ""
var description: String = ""
var events: Array[Event] = []
var rule_ops: RuleOps = null

## 已触发/已预告的事件序号。
var _triggered: Array[int] = []
var _forecasted: Array[int] = []

static func from_dict(d: Dictionary, ops: RuleOps) -> Scenario:
	var sc := Scenario.new()
	sc.name = String(d.get("name", ""))
	sc.description = String(d.get("description", ""))
	sc.rule_ops = ops
	for e in d.get("events", []):
		sc.events.append(Event.from_dict(e))
	sc.events.sort_custom(func(a: Event, b: Event) -> bool: return a.turn < b.turn)
	return sc

## 回合开始神谕阶段:检查当前整回合应触发的事件。
## 预告在前 1 回合(turn - 1)发出;触发在事件回合本身。
## 返回本回合执行的 Log 列表(演出层播报)。
func on_round_start(state: MatchState, rules: RuleSet, piece_types: Dictionary) -> Array[RuleOps.Log]:
	var out: Array[RuleOps.Log] = []
	var round_now: int = state.full_rounds + 1
	for i in events.size():
		if _triggered.has(i):
			continue
		var e: Event = events[i]
		# 预告:事件回合前 1 回合
		if not _forecasted.has(i) and round_now == e.turn - 1 and not e.forecast.is_empty():
			_forecasted.append(i)
			event_forecast.emit(e.forecast)
		# 触发:事件回合本身
		if round_now == e.turn:
			_triggered.append(i)
			for op in e.ops:
				var log: RuleOps.Log = rule_ops.apply(state, rules, piece_types,
					String(op["op"]), op["params"])
				if log != null:
					out.append(log)
					event_triggered.emit(log, e.forecast)
	return out

## 剧本是否已全部演完。
func finished() -> bool:
	return _triggered.size() >= events.size()
