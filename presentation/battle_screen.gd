## 对局界面:由战役关卡配置驱动(base_pack + extra_packs + ai + scenario)。
## 战斗逻辑从旧 main.gd 迁移:双模式对局、神谕演出、AI 应手。
## ESC:翻出设置菜单(设置层接管),不暂停对局逻辑本身。
class_name BattleScreen
extends Control

const BOARD_VIEW := preload("res://presentation/board_view.gd")

## 对局结束请求(演出层给出按钮:重打 / 返回战役)。
signal battle_finished(result: int)
signal back_pressed

var game: Match
var board_view: BoardView
var status_label: Label
var hint_label: Label
var decree_label: Label
## 本关配置(campaign battles[i])。
var battle: Dictionary = {}
var ai: AISearch = null
## AI 难度档(搜索深度)。
var ai_depth := 2
## AI 搜索进行中(防重入:等待期间玩家又落子/悔棋)。
var _ai_busy := false

func _ready() -> void:
	custom_minimum_size = Vector2(640, 360)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_layout()

func start(battle_cfg: Dictionary) -> void:
	battle = battle_cfg
	var ai_cfg: Dictionary = battle.get("ai", {})
	ai_depth = int(ai_cfg.get("depth", 2))
	_start_battle()

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

	var back_btn := Button.new()
	back_btn.text = "← 战役"
	back_btn.position = Vector2(470, 2)
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_size_override("font_size", 12)
	back_btn.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back_btn)

# ---------------------------------------------------------------- 开局

func _start_battle() -> void:
	var pack := PackLoader.load_pack("res://data/packs/%s" % battle.get("base_pack", "classic_xiangqi"))
	for extra in battle.get("extra_packs", []):
		var ext := PackLoader.load_pack("res://data/packs/%s" % extra)
		for key in ext["piece_types"].keys():
			pack["piece_types"][key] = ext["piece_types"][key]
	game = Match.new(pack["state"], pack["rules"], pack["piece_types"])
	# 剧本(可选):神谕按回合触发
	var scenario_path := String(battle.get("scenario", ""))
	if not scenario_path.is_empty():
		var f := FileAccess.open(scenario_path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				var ops := RuleOps.new()
				game.scenario = Scenario.from_dict(parsed, ops)
				game.scenario.event_forecast.connect(_on_forecast)
				game.scenario.event_triggered.connect(_on_decree)
	var ai_cfg: Dictionary = battle.get("ai", {})
	ai = AISearch.new(ai_depth) if bool(ai_cfg.get("enabled", false)) else null
	decree_label.text = ""
	_bind()
	_refresh()

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

## AI 行动(敌方回合)。推迟一帧再搜索:玩家落子先渲染,避免画面冻结。
## 重入保护:等待期间局面已变(玩家悔棋/重打/再落子)则放弃本次应手。
func _ai_move() -> void:
	if ai == null or _ai_busy:
		return
	if game.result != WinCond.Result.ONGOING or game.state.turn != "black":
		return
	_ai_busy = true
	_do_ai_move.call_deferred()

func _do_ai_move() -> void:
	await get_tree().process_frame
	_ai_busy = false
	if ai == null or game == null:
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

func _bind() -> void:
	board_view.bind_match(game)

func _refresh() -> void:
	var title := "神明不会下棋 M1"
	var ai_on := ai != null
	if game.result != WinCond.Result.ONGOING:
		status_label.text = "%s  —  %s" % [title, WinCond.result_name(game.result)]
		hint_label.text = "对局结束 | Z: 悔棋  R: 重打  ←: 返回战役"
	else:
		var side := "红方行棋" if game.state.turn == "red" else (
			"神在思考…" if ai_on else "黑方行棋")
		status_label.text = "%s  —  %s  第 %d 手" % [title, side, game.state.move_count + 1]
		hint_label.text = "点选棋子走子(红先) | Z: 悔棋  ESC: 设置  ←: 返回战役"

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# 设置菜单打开时不吃快捷键(避免菜单底下误操作)
	var menu := get_parent().get_node_or_null("SettingsMenu") as SettingsMenu
	if menu != null and menu.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Z:
				if game != null and game.undo_last():
					_bind()
					_refresh()
			KEY_R:
				if game != null and not battle.is_empty():
					_start_battle()
