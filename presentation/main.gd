## 主场景:本地双人热座对局(M0)。
extends Control

var game: Match
var board_view: BoardView
var status_label: Label
var hint_label: Label

func _ready() -> void:
	var pack := PackLoader.load_pack("res://data/packs/classic_xiangqi")
	game = Match.new(pack["state"], pack["rules"], pack["piece_types"])

	board_view = BoardView.new()
	add_child(board_view)
	board_view.bind_match(game)
	board_view.move_made.connect(_on_move_made)

	status_label = Label.new()
	status_label.position = Vector2(16, 4)
	status_label.add_theme_font_size_override("font_size", 13)
	add_child(status_label)

	hint_label = Label.new()
	hint_label.position = Vector2(16, 342)
	hint_label.add_theme_font_size_override("font_size", 10)
	hint_label.text = "点选棋子走子(红先) | Z: 悔棋  R: 重开"
	add_child(hint_label)

	_refresh()

func _on_move_made(piece: Piece, to_x: int, to_y: int) -> void:
	game.try_move(piece, to_x, to_y)
	board_view.bind_match(game)
	_refresh()

func _refresh() -> void:
	if game.result != WinCond.Result.ONGOING:
		status_label.text = "%s  —  %s" % [
			"神明不会下棋 M0",
			WinCond.result_name(game.result)
		]
		hint_label.text = "对局结束 | R: 重开"
	else:
		var side := "红方行棋" if game.state.turn == "red" else "黑方行棋"
		status_label.text = "神明不会下棋 M0  —  %s  第 %d 手" % [
			side, game.state.move_count + 1
		]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Z:
				if game.undo_last():
					board_view.bind_match(game)
					_refresh()
			KEY_R:
				get_tree().reload_current_scene()
