## 一次行动(意图)。M0 为象棋式:单棋子单步,displace 吃子。
class_name Move
extends RefCounted

var piece: Piece
var from_x: int
var from_y: int
var to_x: int
var to_y: int
var captured: Piece = null   # 结算时填充(供悔棋)

func _init(p: Piece, tx: int, ty: int) -> void:
	piece = p
	from_x = p.x
	from_y = p.y
	to_x = tx
	to_y = ty

func is_capture() -> bool:
	return captured != null

func to_notation() -> String:
	return "%s(%d,%d)->(%d,%d)" % [piece.type.display_name, from_x, from_y, to_x, to_y]
