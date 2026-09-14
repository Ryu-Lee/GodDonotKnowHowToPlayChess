## 主场景:双模式对局 —— 经典热座(红先)与"神的试炼"剧本局(玩家执红 vs AI 神)。
## 神谕公告:剧本事件触发时顶部公告条 + 震屏演出(预告→发生→适应的节奏)。
extends Control

enum Mode { CLASSIC_HOTSEAT, GOD_TRIAL }

const BOARD_VIEW := preload("res://presentation/board_view.gd")

var game: Match
var board_view: BoardView
var status_label: Label
var hint_label: Label
var decree_label: Label
var mode: int = Mode.CLASSIC_HOTSEAT
var ai: AISearch
## AI 难度档(搜索深度)。
var ai_depth := 2

func _ready() -> void:
	_layout()
	start_classic()

func _layout() -> void:
	board_view = BOARD_VIEW.new()
	add_child(board_view)
	board_view.move_made.connect(_on_move_made)

	status_label = Label.new()
	status_label.position = Vector2(16, 4)
	status_label.add_theme_font_size_override("font_size", 13)
	add_child(status_label)

	hint_label = Label.new()
	hint_label.position = Vector2(16, 342)
	hint_label.add_theme_font_size_override("font_size", 10)
	add_child(hint_label)

	decree_label = Label.new()
	decree_label.position = Vector2(16, 22)
	decree_label.add_theme_font_size_override("font_size", 11)
	decree_label.add_theme_color_override("font_color", Color("#d9a8ff"))
	add_child(decree_label)

# ---------------------------------------------------------------- 模式启动

func start_classic() -> void:
	mode = Mode.CLASSIC_HOTSEAT
	var pack := PackLoader.load_pack("res://data/packs/classic_xiangqi")
	game = Match.new(pack["state"], pack["rules"], pack["piece_types"])
	ai = null
	_bind()
	_refresh()

func start_god_trial() -> void:
	mode = Mode.GOD_TRIAL
	var pack := PackLoader.load_pack("res://data/packs/classic_xiangqi")
	var fantasy := PackLoader.load_pack("res://data/packs/god_fantasy")
	for key in fantasy["piece_types"].keys():
		pack["piece_types"][key] = fantasy["piece_types"][key]
	game = Match.new(pack["state"], pack["rules"], pack["piece_types"])
	# 剧本:神谕按回合触发
	var f := FileAccess.open("res://data/scenarios/god_trial.json", FileAccess.READ)
	if f != null:
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			var ops := RuleOps.new()
			game.scenario = Scenario.from_dict(parsed, ops)
			game.scenario.event_forecast.connect(_on_forecast)
			game.scenario.event_triggered.connect(_on_decree)
	ai = AISearch.new(ai_depth)
	_bind()
	_refresh()

func _bind() -> void:
	board_view.bind_match(game)

# ---------------------------------------------------------------- 交互

func _on_move_made(piece: Piece, to_x: int, to_y: int) -> void:
	var act: Action = null
	if board_view.pending_attack != null:
		act = game.try_attack(piece, to_x, to_y, board_view.pending_attack)
		board_view.pending_attack = null
	if act == null:
		act = game.try_move(piece, to_x, to_y)
	_bind()
	_refresh()
	_ai_move()

## AI 神行动(剧本模式黑方)。
func _ai_move() -> void:
	if mode != Mode.GOD_TRIAL or ai == null:
		return
	if game.result != WinCond.Result.ONGOING or game.state.turn != "black":
		return
	var act := ai.pick_action(game.state, game.rules, "black")
	if act == null:
		return
	if act.is_move():
		game.try_move(act.piece, act.to_x, act.to_y)
	else:
		game.try_attack(act.piece, act.to_x, act.to_y, act.target)
	_bind()
	_refresh()

# ---------------------------------------------------------------- 演出

func _on_forecast(text: String) -> void:
	decree_label.text = "【征兆】" + text
	_shake()

func _on_decree(_log: RuleOps.Log, text: String) -> void:
	decree_label.text = "【神谕】" + ("" if text.is_empty() else text + " ") + _describe(_log)
	_shake()

func _describe(log: RuleOps.Log) -> String:
	match log.op:
		"ADD_PIECE":
			return "神凭空造子!敌军 %s 降临。" % String(log.payload.get("type_id", "?"))
		"REMOVE_PIECE":
			return "神抹除了一枚棋子。"
		"MODIFY_CELL":
			return "棋盘变形了!"
		"RESIZE_BOARD":
			return "棋盘规格被改写!"
		"ADD_TEMP_RULE":
			return "临时规则颁布:%s" % String(log.payload.get("id", ""))
		"REMOVE_TEMP_RULE":
			return "临时规则被撤销。"
		"SET_WIN_CONDITION":
			return "胜负条件被改写了——打开规则面板看清当前规则!"
		"GRANT_ABILITY":
			return "神赐予了强化。"
		"NERF_PIECE":
			return "神削弱了你的棋子。"
	return log.op

## 震屏:神谕时刻棋盘颤抖。
func _shake() -> void:
	var tween := create_tween()
	var origin := board_view.position
	for i in 6:
		var amp := 4.0 * (1.0 - float(i) / 6.0)
		tween.tween_property(board_view, "position",
			origin + Vector2(randf_range(-amp, amp), randf_range(-amp, amp)), 0.03)
	tween.tween_property(board_view, "position", origin, 0.03)

# ---------------------------------------------------------------- 状态栏

func _refresh() -> void:
	var title := "神明不会下棋 M1"
	if mode == Mode.GOD_TRIAL:
		title += "  ·  神的试炼"
	if game.result != WinCond.Result.ONGOING:
		status_label.text = "%s  —  %s" % [title, WinCond.result_name(game.result)]
		hint_label.text = "对局结束 | R: 重开  T: 切换模式"
	else:
		var side := "红方行棋" if game.state.turn == "red" else (\
			"神在思考…" if mode == Mode.GOD_TRIAL else "黑方行棋")
		status_label.text = "%s  —  %s  第 %d 手" % [title, side, game.state.move_count + 1]
		if mode == Mode.GOD_TRIAL:
			hint_label.text = "你执红 | Z: 悔棋  T: 热座  R: 重开"
		else:
			hint_label.text = "点选棋子走子(红先) | Z: 悔棋  R: 重开  G: 神的试炼"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Z:
				if game.undo_last():
					_bind()
					_refresh()
			KEY_R:
				if mode == Mode.GOD_TRIAL:
					start_god_trial()
				else:
					start_classic()
			KEY_T:
				start_classic()
			KEY_G:
				start_god_trial()
