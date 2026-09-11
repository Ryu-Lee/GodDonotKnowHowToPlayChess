## 棋子类型:从数据包 JSON 解析出的静态定义(走法/攻击/数值)。
class_name PieceType
extends RefCounted

var id: String
var display_name: String
var tier: String = "classic"          # classic / fantasy
var move_type: String = ""            # step / zone_step / leaper / rider / script
var pattern: Array[Vector2i] = []     # 走法向量
var crossed_pattern: Array[Vector2i] = []  # 兵过河后的 pattern(空 = 同 pattern)
var zone: String = ""                 # "", "palace_own", "own_half", "forward_only_before_cross"
var blockers: Array[String] = []      # 阻挡判定 id: ma_leg / xiang_eye
var capture_mode: String = ""         # "": 普通占据式; "screen": 炮隔子吃
var attack_type: String = "displace"
var action_economy: String = "chess"  # chess / tactics
var hp: int = 1
var value: float = 1.0                # 子力值(AI 评估)
var royal: bool = false               # 是否将帅(胜负关键子)
var abilities: Array[String] = []

static func from_dict(d: Dictionary) -> PieceType:
	var pt := PieceType.new()
	pt.id = d.get("id", "")
	pt.display_name = d.get("name", pt.id)
	pt.tier = d.get("tier", "classic")
	var mv: Dictionary = d.get("move", {})
	pt.move_type = mv.get("type", "step")
	pt.pattern = _to_vecs(mv.get("pattern", []))
	pt.crossed_pattern = _to_vecs(mv.get("crossed_pattern", []))
	pt.zone = mv.get("zone", "")
	pt.blockers = _str_arr(mv.get("blockers", []))
	pt.capture_mode = mv.get("capture_mode", "")
	var atk: Dictionary = d.get("attack", {})
	pt.attack_type = atk.get("type", "displace")
	pt.action_economy = d.get("action_economy", "chess")
	pt.hp = int(d.get("hp", 1))
	pt.value = float(d.get("value", 1.0))
	pt.royal = bool(d.get("royal", false))
	pt.abilities = _str_arr(d.get("abilities", []))
	return pt

static func _to_vecs(arr: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for v in arr:
		out.append(Vector2i(int(v[0]), int(v[1])))
	return out

static func _str_arr(arr: Array) -> Array[String]:
	var out: Array[String] = []
	for v in arr:
		out.append(String(v))
	return out
