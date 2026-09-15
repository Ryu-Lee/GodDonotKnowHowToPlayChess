## 像素棋盘视图:程序化绘制棋盘/棋子,处理点选走子 + 行动演出动画。
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
## 玩家阵营(由 battle_screen 按关卡配置注入):只允许操作己方棋子。
## 仅按"当前回合阵营"判定的话,AI 的 tactics 棋子移动后未攻击时
## 仍是敌方回合,玩家就能点选敌方特殊棋子替神操作——必须双重校验。
var player_faction := "red"
var selected: Piece = null
var legal_targets: Dictionary = {}   # Vector2i -> Action
## 攻击目标(点击攻击格后暂存,由 main 提交 try_attack)。
var pending_attack: Piece = null

# ---------------------------------------------------------------- 演出动画
## 单次演出(移动滑行 / 攻击突进 / 受击闪红 / 伤害数字)。
## 状态在引擎里已即时结算;动画只在绘制层复现过程,不阻塞交互。
class Anim extends RefCounted:
	var piece: Piece            # 演出主体(可能已阵亡,仍需引用绘制残影)
	var from: Vector2           # 起点屏幕坐标
	var to: Vector2             # 终点屏幕坐标
	var t := 0.0                # 已进行时长(秒)
	var dur := 0.18             # 总时长
	var kind := "move"          # move / attack / hit / dmg
	var text := ""              # dmg 数字文本
	var color := Color.WHITE

## 进行中的动画队列(每帧推进,空则停止重绘)。
var _anims: Array[Anim] = []
## 阵亡淡出:piece -> 剩余时间。引擎已标 dead,这里保留残影。
var _fading: Dictionary = {}
const FADE_DUR := 0.5
## 本帧被动画隐藏的棋子(绘制时跳过其常规渲染,由残影接管)。
var _hidden_pieces: Array[Piece] = []

func _ready() -> void:
	custom_minimum_size = Vector2(640, 360)
	set_anchors_preset(Control.PRESET_FULL_RECT)

func bind_match(m: Match) -> void:
	# 换新对局才清动画;普通落子后的 rebind 不打断进行中的演出
	if m != game:
		_anims.clear()
		_fading.clear()
	game = m
	selected = null
	legal_targets.clear()
	queue_redraw()

## 立即清空全部演出(悔棋/重打时状态跳变,动画已无意义)。
func reset_anims() -> void:
	_anims.clear()
	_fading.clear()
	queue_redraw()

func _process(delta: float) -> void:
	if game == null:
		return
	var active := false
	# 推进动画
	var done: Array[Anim] = []
	for a in _anims:
		a.t += delta
		if a.t >= a.dur:
			done.append(a)
		active = true
	for a in done:
		_anims.erase(a)
	# 推进阵亡淡出
	var fade_done: Array = []
	for p in _fading.keys():
		_fading[p] = float(_fading[p]) - delta
		if float(_fading[p]) <= 0.0:
			fade_done.append(p)
		active = true
	for p in fade_done:
		_fading.erase(p)
	if active:
		queue_redraw()

## 移动演出:从原格滑行到新格(棋子逻辑位置已更新,绘制时反向偏移)。
func anim_move(p: Piece, from_x: int, from_y: int) -> void:
	var a := Anim.new()
	a.piece = p
	a.kind = "move"
	a.from = _to_screen(from_x, from_y)
	a.to = _to_screen(p.x, p.y)
	a.dur = 0.16 + 0.03 * (abs(p.x - from_x) + abs(p.y - from_y))
	_anims.append(a)
	queue_redraw()

## 攻击演出:向目标突进再弹回(棋子不实际移动,视觉冲撞)。
func anim_attack(p: Piece, tx: int, ty: int) -> void:
	var a := Anim.new()
	a.piece = p
	a.kind = "attack"
	a.from = _to_screen(p.x, p.y)
	a.to = _to_screen(tx, ty)
	a.dur = 0.25
	_anims.append(a)
	# 受击者:闪红 + 伤害数字(伤害在 damage_log)
	queue_redraw()

## 受击演出:闪红抖动 + 伤害数字。
func anim_hit(target: Piece, dmg: int, from_x: int, from_y: int) -> void:
	var a := Anim.new()
	a.piece = target
	a.kind = "hit"
	a.from = _to_screen(from_x, from_y)
	a.to = _to_screen(target.x, target.y)
	a.dur = 0.3
	a.text = "-%d" % dmg
	a.color = Color("#ff4a3c")
	_anims.append(a)
	queue_redraw()

## 阵亡淡出(残影渐隐)。
func anim_fade(p: Piece) -> void:
	_fading[p] = FADE_DUR
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
	# 2. 点己方棋子(己方回合)=> 选中(列出走法 + 攻击目标)
	if clicked != null and clicked.faction == player_faction \
			and game.state.turn == player_faction:
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
	_hidden_pieces.clear()
	# 预登记:演出中的棋子跳过常规绘制,由动画层接管
	# (必须先于 _draw_pieces 填充,否则棋子会在新格与插值位置重复绘制;
	#  阵亡者常规绘制本就跳过,本体交给残影层渐隐)
	for a in _anims:
		if a.piece.alive:
			_hidden_pieces.append(a.piece)
	_draw_board()
	_draw_terrain()
	_draw_pieces()
	_draw_anims()
	_draw_fading()
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
		if _hidden_pieces.has(p):
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

## 动画层绘制:移动滑行 / 攻击突进(棋子本体被隐藏,由这里插值绘制)。
func _draw_anims() -> void:
	for a in _anims:
		var k := clampf(a.t / a.dur, 0.0, 1.0)
		match a.kind:
			"move":
				var pos := a.from.lerp(a.to, _ease_out(k))
				# 移动残影轨迹
				draw_line(a.from, pos, Color(1, 1, 1, 0.15), 3.0)
				_draw_piece_at(a.piece, pos, 1.0)
			"attack":
				# 突进 40% 后弹回
				var lunge := _lunge_curve(k)
				var pos := a.from.lerp(a.to, lunge)
				# 冲击线
				if k < 0.5:
					draw_line(a.from, pos, Color(1, 0.4, 0.3, 0.3), 2.0)
				_draw_piece_at(a.piece, pos, 1.0)
				# 撞击瞬间:目标格爆闪
				if k >= 0.38 and k <= 0.55:
					draw_circle(a.to, PIECE_R + 4.0, Color(1, 0.6, 0.3, 0.35))
			"hit":
				# 受击者:位置微抖 + 红闪覆盖
				var shake := (1.0 - k) * 3.0
				var jitter := Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
				if a.piece.alive and not _has_body_anim(a.piece):
					_draw_hit_flash(a.piece, jitter, 1.0 - k)
				else:
					# 阵亡者本体由残影层渐隐;被反击的攻击方本体由攻击演出绘制
					# ——这里只补红闪,不重绘本体
					draw_circle(a.to + jitter, PIECE_R + 1.0,
						Color(1, 0.25, 0.15, 0.45 * (1.0 - k)))
				# 伤害数字:上浮渐隐
				var rise := 10.0 * k
				var alpha := 1.0 - k
				var font := ThemeDB.fallback_font
				draw_string(font, a.to + Vector2(-8, -16 - rise), a.text,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					Color(a.color.r, a.color.g, a.color.b, alpha))

## 该棋子是否有进行中的本体演出(move/attack,由动画层绘制其本体)。
func _has_body_anim(p: Piece) -> bool:
	for a in _anims:
		if a.piece == p and (a.kind == "move" or a.kind == "attack"):
			return true
	return false

## 阵亡残影:渐隐 + 微缩。
func _draw_fading() -> void:
	for p in _fading.keys():
		# 若棋子另有进行中的本体演出(如近战被反击致死,仍在攻击突进动画里),
		# 由攻击动画绘制其本体,残影推迟接管防重绘
		if _has_body_anim(p):
			continue
		var k := float(_fading[p]) / FADE_DUR
		_draw_piece_at(p, _to_screen(p.x, p.y), k, true)

## 在指定位置绘制一枚棋子(动画插值用;alpha 控制渐隐)。
func _draw_piece_at(p: Piece, pos: Vector2, alpha: float, dead := false) -> void:
	var is_red := p.faction == "red"
	var fantasy := p.type.tier == "fantasy"
	var rim := Color("#5a3d16")
	rim.a = alpha
	var face := Color("#e8d3a0")
	face.a = alpha
	var scale := 1.0 if not dead else 0.6 + 0.4 * alpha
	draw_circle(pos, PIECE_R * scale, rim)
	draw_circle(pos, (PIECE_R - 2.5) * scale, face)
	var arc_col := Color("#7a4ad9") if fantasy else Color("#a8865a")
	arc_col.a = alpha
	draw_arc(pos, (PIECE_R - 5.0) * scale, 0, TAU, 40, arc_col, 1.5, true)
	var font := ThemeDB.fallback_font
	var col := Color("#b03030") if is_red else Color("#222222")
	col.a = alpha
	draw_string(font, pos + Vector2(-PIECE_R + 2, 7), _glyph(p),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)

## 受击红闪:半透明红罩 + 原棋子重绘于抖动位置。
func _draw_hit_flash(p: Piece, jitter: Vector2, intensity: float) -> void:
	var pos := _to_screen(p.x, p.y) + jitter
	_draw_piece_at(p, pos, 1.0)
	draw_circle(pos, PIECE_R + 1.0, Color(1, 0.25, 0.15, 0.45 * intensity))

func _ease_out(k: float) -> float:
	return 1.0 - (1.0 - k) * (1.0 - k)

## 突进曲线:前 40% 冲向目标(略过冲),后 60% 弹回。
func _lunge_curve(k: float) -> float:
	if k < 0.4:
		return _ease_out(k / 0.4) * 0.45
	return 0.45 * (1.0 - _ease_out((k - 0.4) / 0.6))

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
