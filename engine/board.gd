## 棋盘:格子、邻接、地形、区域(九宫/河界)。纯逻辑,零渲染依赖。
class_name Board
extends RefCounted

enum Terrain { NORMAL, HILL, RIVER, BRIDGE }

var width: int
var height: int
var river_rows: Array[int] = []   # 河界行(经典为 [4, 5];红方在下)
## 双方九宫 key: red/black -> {x0,x1,y0,y1}(闭区间,避免 Rect2i end 开区间歧义)。
var palaces: Dictionary = {}
var _cells: Array = []
var _exists: Array[bool] = []

func _init(w: int = 9, h: int = 10) -> void:
	width = w
	height = h
	_cells.resize(w * h)
	_exists.resize(w * h)
	for i in w * h:
		_cells[i] = Cell.new()
		_exists[i] = true

func idx(x: int, y: int) -> int:
	return y * width + x

func in_bounds(x: int, y: int) -> bool:
	if x < 0 or x >= width or y < 0 or y >= height:
		return false
	return _exists[idx(x, y)]

func cell(x: int, y: int) -> Cell:
	return _cells[idx(x, y)]

func is_river(y: int) -> bool:
	return river_rows.has(y)

## 九宫闭区间角点(供渲染画斜线:左上/右下)。
func palace_rect(faction: String) -> Rect2i:
	var p: Dictionary = palaces.get(faction)
	if p == null:
		return Rect2i()
	return Rect2i(
		int(p["x0"]), int(p["y0"]),
		int(p["x1"]) - int(p["x0"]) + 1, int(p["y1"]) - int(p["y0"]) + 1
	)

func in_palace(faction: String, x: int, y: int) -> bool:
	var p: Dictionary = palaces.get(faction)
	if p == null:
		return false
	return x >= int(p["x0"]) and x <= int(p["x1"]) \
		and y >= int(p["y0"]) and y <= int(p["y1"])

## 是否已过河(相对 faction 方向)。
## 河界语义:river_rows = [黑侧河岸行, 红侧河岸行],河在两行之间。
## 经典 [4,5]:红兵到 y<=4(踏上黑岸)为过河;黑卒到 y>=5 为过河。
func crossed_river(faction: String, y: int) -> bool:
	if river_rows.is_empty():
		return false
	var top: int = river_rows[0]
	var bottom: int = river_rows[river_rows.size() - 1]
	if faction == "black":
		return y > top
	return y < bottom

## 变更棋盘规格:同坐标旧格保留,界外旧格丢弃,新增区域补空白格。
## 回滚(RESIZE_BOARD undo)由 RuleOps 用快照恢复,不依赖此处保留界外数据。
func resize(w: int, h: int) -> void:
	if w == width and h == height:
		return
	var old_w := width
	var old_h := height
	var old_cells := _cells
	var old_exists := _exists
	width = w
	height = h
	_cells = []
	_exists = []
	_cells.resize(w * h)
	_exists.resize(w * h)
	for y in h:
		for x in w:
			var i := y * w + x
			if x < old_w and y < old_h:
				_cells[i] = old_cells[y * old_w + x]
				_exists[i] = old_exists[y * old_w + x]
			else:
				_cells[i] = Cell.new()
				_exists[i] = true

func serialize() -> Dictionary:
	var cells_arr: Array = []
	for i in _cells.size():
		var c: Cell = _cells[i]
		if not _exists[i]:
			continue
		if c.terrain != Terrain.NORMAL or c.elevation != 0 or c.pass_rule != "":
			cells_arr.append({
				"x": i % width, "y": i / width,
				"terrain": c.terrain, "elevation": c.elevation,
				"pass_rule": c.pass_rule,
				"pass_dir": [c.pass_dir.x, c.pass_dir.y],
				"pass_limit": c.pass_limit
			})
	return {
		"width": width, "height": height,
		"river_rows": river_rows,
		"palace": palaces,
		"cells": cells_arr
	}

## 单格状态。elevation 高低差(M0 恒 0),pass 通行规则。
class Cell extends RefCounted:
	var terrain: int = Terrain.NORMAL
	var elevation: int = 0
	var pass_rule: String = ""      # "", "impassable", "oneway", "limited"
	var pass_dir: Vector2i = Vector2i.ZERO  # oneway 方向
	var pass_limit: int = -1        # limited 剩余次数(-1 = 无限)
