## 一次行动意图。M1 起支持两种:移动(displace 吃随移动)与攻击(独立结算)。
class_name Action
extends RefCounted

enum Kind { MOVE, ATTACK }

var kind: int = Kind.MOVE
var piece: Piece
var from_x: int
var from_y: int
var to_x: int
var to_y: int
## 攻击目标(splash 可为空——纯地面打击)。
var target: Piece = null
## 结算记录(供悔棋/演出)。
var captured: Piece = null
## 攻击造成的伤害序列 [{piece, dmg}]。
var damage_log: Array = []
## 本行动是否消费了 limited 地形次数(悔棋时返还)。
var consumed_pass := false

func _init(p: Piece, tx: int, ty: int, k: int = Kind.MOVE, tgt: Piece = null) -> void:
	piece = p
	from_x = p.x
	from_y = p.y
	to_x = tx
	to_y = ty
	kind = k
	target = tgt

func is_move() -> bool:
	return kind == Kind.MOVE

func is_attack() -> bool:
	return kind == Kind.ATTACK

func notation() -> String:
	if kind == Kind.MOVE:
		return "%s(%d,%d)->(%d,%d)" % [
			piece.type.display_name, from_x, from_y, to_x, to_y
		]
	return "%s(%d,%d)攻(%d,%d)" % [
		piece.type.display_name, from_x, from_y, to_x, to_y
	]
