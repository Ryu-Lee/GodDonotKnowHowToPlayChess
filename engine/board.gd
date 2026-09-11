## 棋盘:格子、邻接、地形、区域(九宫/河界)。纯逻辑,零渲染依赖。
class_name Board
extends RefCounted

enum Terrain { NORMAL, HILL, RIVER, BRIDGE }

var width: int
var height: int
var river_rows: Array[int] = []   # 河界行(经典为 [4, 5];红方在下)
var palaces: Dictionary = {}      # 双方九宫 key: red/black -> Rect2i
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

func in_palace(faction: String, x: int, y: int) -> bool:
	var r: Rect2i = palaces.get(faction)
	if r == null:
		return false
	return x >= r.position.x and x <= r.end.x and y >= r.position.y and y <= r.end.y

## 是否已过河(相对 faction 方向):红方向上越过河,黑方向下越过河。
func crossed_river(faction: String, y: int) -> bool:
	if river_rows.is_empty():
		return false
	var top: int = river_rows[0]
	var bottom: int = river_rows[river_rows.size() - 1]
	if faction == "black":
		return y > bottom
	return y < top

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
		"palaces": palaces,
		"cells": cells_arr
	}

## 单格状态。elevation 高低差(M0 恒 0),pass 通行规则。
class Cell extends RefCounted:
	var terrain: int = Terrain.NORMAL
	var elevation: int = 0
	var pass_rule: String = ""      # "", "impassable", "oneway", "limited"
	var pass_dir: Vector2i = Vector2i.ZERO  # oneway 方向
	var pass_limit: int = -1        # limited 剩余次数(-1 = 无限)
