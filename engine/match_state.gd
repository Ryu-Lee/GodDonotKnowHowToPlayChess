## 对局状态:棋盘 + 双方棋子 + 回合。全部可序列化(快照/悔棋/回放的基础)。
class_name MatchState
extends RefCounted

var board: Board
## 规则集引用(临时规则消费方:movegen/combat/wincond 经 state 读取)。引擎内部数据,非渲染依赖。
var rules: RuleSet = null
var pieces: Array[Piece] = []
var turn: String = "red"            # 当前行动方
var move_count: int = 0             # 总步数(半回合)
var full_rounds: int = 0            # 整回合数(黑方行动结束 +1)

func _init(b: Board) -> void:
	board = b

func pieces_of(faction: String) -> Array[Piece]:
	var out: Array[Piece] = []
	for p in pieces:
		if p.alive and p.faction == faction:
			out.append(p)
	return out

func piece_at(x: int, y: int) -> Piece:
	for p in pieces:
		if p.alive and p.x == x and p.y == y:
			return p
	return null

func royal_of(faction: String) -> Piece:
	for p in pieces:
		if p.alive and p.faction == faction and p.type.royal:
			return p
	return null

## 朝向向量:red 朝上(0,-1),black 朝下(0,1)。
func forward(faction: String) -> Vector2i:
	return Vector2i(0, -1) if faction == "red" else Vector2i(0, 1)

func clone() -> MatchState:
	var ms := MatchState.new(board)
	ms.turn = turn
	ms.move_count = move_count
	ms.full_rounds = full_rounds
	for p in pieces:
		var np := Piece.new(p.type, p.faction, p.x, p.y)
		np.hp = p.hp
		np.alive = p.alive
		ms.pieces.append(np)
	return ms

func serialize() -> Dictionary:
	var arr: Array = []
	for p in pieces:
		arr.append(p.serialize())
	return { "turn": turn, "move_count": move_count, "full_rounds": full_rounds, "pieces": arr }

func deserialize(d: Dictionary, piece_types: Dictionary) -> void:
	pieces.clear()
	for pd in d.get("pieces", []):
		var pt: PieceType = piece_types.get(String(pd.get("type", "")))
		if pt == null:
			push_error("Unknown piece type: %s" % pd.get("type"))
			continue
		var p := Piece.new(pt, String(pd.get("faction", "")), int(pd.get("x", 0)), int(pd.get("y", 0)))
		p.hp = int(pd.get("hp", 1))
		p.alive = bool(pd.get("alive", true))
		pieces.append(p)
	turn = String(d.get("turn", "red"))
	move_count = int(d.get("move_count", 0))
	full_rounds = int(d.get("full_rounds", 0))
