## 棋子实例:对局中的具体棋子。
class_name Piece
extends RefCounted

var type: PieceType
var faction: String                  # red / black
var x: int
var y: int
var hp: int
var alive: bool = true

func _init(p_type: PieceType, p_faction: String, px: int, py: int) -> void:
	type = p_type
	faction = p_faction
	x = px
	y = py
	hp = p_type.hp

func id() -> String:
	return type.id

func pos() -> Vector2i:
	return Vector2i(x, y)

func serialize() -> Dictionary:
	return {
		"type": type.id, "faction": faction,
		"x": x, "y": y, "hp": hp, "alive": alive
	}
