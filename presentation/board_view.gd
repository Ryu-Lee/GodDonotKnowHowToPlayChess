## 像素棋盘视图:程序化绘制棋盘/棋子,处理点选走子。
## 坐标系:引擎 (x,y) 0-based,黑在上红在下;屏幕 y 向下,引擎 y 向下同向(黑 y=0 在顶部)。
class_name BoardView
extends Control

signal move_made(piece: Piece, to_x: int, to_y: int)

const CELL := 34          # 格距(像素,640×360 下 9×10 棋盘 = 272×340 内含边距)
const MARGIN_X := 44.0
const MARGIN_Y := 8.0
const PIECE_R := 14.0

var game: Match
var selected: Piece = null
var legal_targets: Dictionary = {}   # Vector2i -> Move

func _ready() -> void:
	custom_minimum_size = Vector2(640, 360)
	set_anchors_preset(Control.PRESET_FULL_RECT)

func bind_match(m: Match) -> void:
	game = m
	selected = null
	legal_targets.clear()
	queue_redraw()

func _to_screen(x: int, y: int) -> Vector2:
	return Vector2(MARGIN_X + x * CELL, MARGIN_Y + y * CELL)

func _to_grid(pos: Vector2) -> Vector2i:
	var gx := int(round((pos.x - MARGIN_X) / CELL))
	var gy := int(round((pos.y - MARGIN_Y) / CELL))
	var b := game.state.board
	if gx < 0 or gx >= b.width or gy < 0 or gy >= b.height:
		return Vector2i(-1, -1)
	# 吸附:距交点太远不算
	var center := _to_screen(gx, gy)
	if center.distance_to(pos) > CELL * 0.45:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if game == null or game.result != WinCond.Result.ONGOING:
			return
		var g := _to_grid(event.position)
		if g.x < 0:
			selected = null
			legal_targets.clear()
			queue_redraw()
			return
		_on_click(g.x, g.y)

func _on_click(x: int, y: int) -> void:
	var clicked := game.state.piece_at(x, y)
	# 1. 已选且点击目标在合法走法中 => 走子
	if selected != null and legal_targets.has(Vector2i(x, y)):
		var mv: Move = legal_targets[Vector2i(x, y)]
		move_made.emit(mv.piece, mv.to_x, mv.to_y)
		selected = null
		legal_targets.clear()
		queue_redraw()
		return
	# 2. 点己方棋子 => 选中
	if clicked != null and clicked.faction == game.state.turn:
		selected = clicked
		legal_targets.clear()
		for mv in game.legal_moves_for(clicked):
			legal_targets[Vector2i(mv.to_x, mv.to_y)] = mv
		queue_redraw()
		return
	# 3. 其他 => 取消
	selected = null
	legal_targets.clear()
	queue_redraw()

func _draw() -> void:
	if game == null:
		return
	_draw_board()
	_draw_pieces()
	_draw_selection()

func _draw_board() -> void:
	var b := game.state.board
	var bg := Rect2(0, 0, 640, 360)
	draw_rect(bg, Color("#2b1d0e"))
	var board_rect := Rect2(
		MARGIN_X - 26, MARGIN_Y - 10,
		(b.width - 1) * CELL + 52, (b.height - 1) * CELL + 20
	)
	draw_rect(board_rect, Color("#d9b96c"))
	draw_rect(board_rect, Color("#5a3d16"), false, 2.0)
	var line := Color("#3a2408")
	# 横线
	for y in b.height:
		draw_line(_to_screen(0, y), _to_screen(b.width - 1, y), line, 2.0)
	# 竖线(河界中断)
	var river_top := b.river_rows[0] if not b.river_rows.is_empty() else -1
	var river_bottom := b.river_rows[b.river_rows.size() - 1] if not b.river_rows.is_empty() else -1
	for x in b.width:
		if river_top >= 0 and x != 0 and x != b.width - 1:
			draw_line(_to_screen(x, 0), _to_screen(x, river_top), line, 2.0)
			draw_line(_to_screen(x, river_bottom), _to_screen(x, b.height - 1), line, 2.0)
		else:
			draw_line(_to_screen(x, 0), _to_screen(x, b.height - 1), line, 2.0)
	# 楚河汉界
	if river_top >= 0:
		var mid_y: float = (_to_screen(0, river_top).y + _to_screen(0, river_bottom).y) / 2.0
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(150, mid_y + 7), "楚 河          汉 界",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#8a6a2f"))
	# 九宫斜线
	for faction in ["red", "black"]:
		var r: Rect2i = b.palaces.get(faction)
		if r == null:
			continue
		draw_line(_to_screen(r.position.x, r.position.y), _to_screen(r.end.x, r.end.y), line, 1.5)
		draw_line(_to_screen(r.end.x, r.position.y), _to_screen(r.position.x, r.end.y), line, 1.5)

func _draw_pieces() -> void:
	for p in game.state.pieces:
		if not p.alive:
			continue
		var c := _to_screen(p.x, p.y)
		var is_red := p.faction == "red"
		var rim := Color("#5a3d16")
		var face := Color("#e8d3a0") if is_red else Color("#e8d3a0")
		draw_circle(c, PIECE_R, rim)
		draw_circle(c, PIECE_R - 2.5, face)
		draw_arc(c, PIECE_R - 5.0, 0, TAU, 40, Color("#a8865a"), 1.5, true)
		var glyph: String = _glyph(p)
		var font := ThemeDB.fallback_font
		var col := Color("#b03030") if is_red else Color("#222222")
		draw_string(font, c + Vector2(-PIECE_R + 3, 6), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)

func _glyph(p: Piece) -> String:
	var is_red := p.faction == "red"
	var glyphs := {
		"jiang": ["帥", "將"],
		"shi": ["仕", "士"],
		"xiang": ["相", "象"],
		"ma": ["馬", "馬"],
		"ju": ["車", "車"],
		"pao": ["炮", "砲"],
		"bing": ["兵", "卒"]
	}
	var pair: Array = glyphs.get(p.id(), ["?", "?"])
	return pair[0] if is_red else pair[1]

func _draw_selection() -> void:
	if selected != null:
		var c := _to_screen(selected.x, selected.y)
		draw_arc(c, PIECE_R + 3.0, 0, TAU, 48, Color("#ffd94a"), 2.5, true)
	for t in legal_targets.keys():
		var c := _to_screen(t.x, t.y)
		var occupant := game.state.piece_at(t.x, t.y)
		if occupant != null:
			draw_arc(c, PIECE_R + 3.0, 0, TAU, 48, Color("#ff5a3c"), 2.5, true)  # 可吃:红圈
		else:
			draw_circle(c, 4.0, Color("#3a2408"))                                  # 可走:圆点
