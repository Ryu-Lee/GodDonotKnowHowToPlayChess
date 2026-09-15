## 像素棋盘视图:程序化绘制棋盘/棋子,处理点选走子。
## 坐标系:引擎 (x,y) 0-based,黑在上红在下;屏幕 y 向下,引擎 y 向下同向(黑 y=0 在顶部)。
class_name BoardView
extends Control

signal move_made(piece: Piece, to_x: int, to_y: int)
## 点选任意棋子(敌我皆可) => 信息面板显示说明。
signal piece_inspected(piece: Piece)

const CELL := 34          # 格距(像素,640×360 下 9×10 棋盘 = 272×306 内含边距)
## 居中偏移:棋盘含边框 324×326;右侧留 150px 信息面板 => 板心 x = (640-150-324)/2 + 26
const MARGIN_X := 109.0
const MARGIN_Y := 27.0
const PIECE_R := 14.0

var game: Match
var selected: Piece = null
var legal_targets: Dictionary = {}   # Vector2i -> Action
## 攻击目标(点击攻击格后暂存,由 main 提交 try_attack)。
var pending_attack: Piece = null

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
	# 1. 已选且点击目标在合法行动中 => 走子 / 攻击
	if selected != null and legal_targets.has(Vector2i(x, y)):
		var act: Action = legal_targets[Vector2i(x, y)]
		if act.is_attack():
			pending_attack = act.target
		move_made.emit(act.piece, act.to_x, act.to_y)
		selected = null
		legal_targets.clear()
		queue_redraw()
		return
	# 2. 点己方棋子 => 选中(列出走法 + 攻击目标)
	if clicked != null and clicked.faction == game.state.turn:
		selected = clicked
		legal_targets.clear()
		for act in game.legal_moves_for(clicked):
			legal_targets[Vector2i(act.to_x, act.to_y)] = act
		queue_redraw()
		piece_inspected.emit(clicked)
		return
	# 3. 点敌方棋子 => 不选中,只展示信息
	if clicked != null:
		selected = null
		legal_targets.clear()
		queue_redraw()
		piece_inspected.emit(clicked)
		return
	# 4. 其他 => 取消
	selected = null
	legal_targets.clear()
	queue_redraw()

func _draw() -> void:
	if game == null:
		return
	_draw_board()
	_draw_terrain()
	_draw_pieces()
	_draw_selection()

## 地形渲染:山(棕隆起)/ 河纹 / 禁行叉。elevation 越高颜色越深。
func _draw_terrain() -> void:
	var b := game.state.board
	for y in b.height:
		for x in b.width:
			if not b.in_bounds(x, y):
				continue
			var c := b.cell(x, y)
			var center := _to_screen(x, y)
			if c.terrain == Board.Terrain.HILL or c.elevation > 0:
				var r := 12.0
				draw_circle(center, r, Color("#6b4a2a"))
				draw_circle(center, r - 3.0, Color("#8a6a3f"))
				draw_circle(center + Vector2(0, -2), r - 7.0, Color("#a8865a"))
			elif c.terrain == Board.Terrain.RIVER:
				draw_circle(center, 9.0, Color("#3a6a8a"))
			if c.pass_rule == "impassable":
				var col := Color("#c04a3a")
				draw_line(center + Vector2(-6, -6), center + Vector2(6, 6), col, 2.0)
				draw_line(center + Vector2(6, -6), center + Vector2(-6, 6), col, 2.0)
			elif c.pass_rule == "oneway":
				var d := c.pass_dir
				var tip := center + Vector2(d.x, d.y) * 8.0
				draw_line(center - Vector2(d.x, d.y) * 6.0, tip, Color("#e0a83a"), 2.0)
				draw_circle(tip, 2.0, Color("#e0a83a"))

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
		draw_string(font, Vector2(205, mid_y + 8), "楚 河          汉 界",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#8a6a2f"))
	# 九宫斜线(闭区间角点:左上-右下 / 右上-左下)
	for faction in ["red", "black"]:
		var r: Rect2i = b.palace_rect(faction)
		if r.size == Vector2i.ZERO:
			continue
		draw_line(_to_screen(r.position.x, r.position.y), _to_screen(r.end.x - 1, r.end.y - 1), line, 1.5)
		draw_line(_to_screen(r.end.x - 1, r.position.y), _to_screen(r.position.x, r.end.y - 1), line, 1.5)
	# 兵/炮位起点标记(实际棋盘的短十字折线)
	for x in [0, 2, 4, 6, 8]:
		_start_mark(x, 3)
		_start_mark(x, 6)
	for x in [1, 7]:
		_start_mark(x, 2)
		_start_mark(x, 7)

func _start_mark(x: int, y: int) -> void:
	var line := Color("#3a2408")
	var c := _to_screen(x, y)
	var gap := 4.0    # 与纵线留缝
	var len := 6.0
	var b := game.state.board
	for side in [-1, 1]:
		if x + side >= 0 and x + side < b.width:
			var dx := float(side)
			draw_line(c + Vector2(gap * dx, 0), c + Vector2((gap + len) * dx, 0), line, 1.0)
			draw_line(c + Vector2(gap * dx, 0), c + Vector2(gap * dx, -len), line, 1.0)
			draw_line(c + Vector2(gap * dx, 0), c + Vector2(gap * dx, len), line, 1.0)

func _draw_pieces() -> void:
	for p in game.state.pieces:
		if not p.alive:
			continue
		var c := _to_screen(p.x, p.y)
		var is_red := p.faction == "red"
		var fantasy := p.type.tier == "fantasy"
		var rim := Color("#5a3d16")
		var face := Color("#e8d3a0") if is_red else Color("#e8d3a0")
		draw_circle(c, PIECE_R, rim)
		draw_circle(c, PIECE_R - 2.5, face)
		# fantasy 棋子:紫描边统一(神造物)
		draw_arc(c, PIECE_R - 5.0, 0, TAU, 40,
			Color("#7a4ad9") if fantasy else Color("#a8865a"), 1.5, true)
		# 多血棋子:血点显示
		if p.type.hp > 1:
			for i in p.hp:
				draw_circle(c + Vector2(-6.0 + 4.0 * i, 9.0), 1.6, Color("#b03030"))
		var glyph: String = _glyph(p)
		var font := ThemeDB.fallback_font
		var col := Color("#b03030") if is_red else Color("#222222")
		draw_string(font, c + Vector2(-PIECE_R + 2, 7), glyph,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)

func _glyph(p: Piece) -> String:
	var is_red := p.faction == "red"
	var glyphs := {
		"jiang": ["帥", "將"],
		"shi": ["仕", "士"],
		"xiang": ["相", "象"],
		"ma": ["馬", "馬"],
		"ju": ["車", "車"],
		"pao": ["炮", "砲"],
		"bing": ["兵", "卒"],
		"knight": ["骑", "骑"],
		"archer": ["弓", "弓"],
		"mage": ["法", "法"]
	}
	var pair: Array = glyphs.get(p.id(), ["?", "?"])
	return pair[0] if is_red else pair[1]

func _draw_selection() -> void:
	if selected != null:
		var c := _to_screen(selected.x, selected.y)
		draw_arc(c, PIECE_R + 3.0, 0, TAU, 48, Color("#ffd94a"), 2.5, true)
	for t in legal_targets.keys():
		var act: Action = legal_targets[t]
		var c := _to_screen(t.x, t.y)
		if act.is_attack():
			# 攻击目标:紫红 X 圈(splash 空格落点同)
			draw_arc(c, PIECE_R + 3.0, 0, TAU, 48, Color("#b04ad9"), 2.5, true)
			draw_line(c + Vector2(-4, -4), c + Vector2(4, 4), Color("#b04ad9"), 2.0)
			draw_line(c + Vector2(4, -4), c + Vector2(-4, 4), Color("#b04ad9"), 2.0)
		else:
			var occupant := game.state.piece_at(t.x, t.y)
			if occupant != null:
				draw_arc(c, PIECE_R + 3.0, 0, TAU, 48, Color("#ff5a3c"), 2.5, true)  # 可吃:红圈
			else:
				draw_circle(c, 4.0, Color("#3a2408"))                                  # 可走:圆点
