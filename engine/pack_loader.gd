## 数据包加载器:读取 board.json / pieces.json / rules.json,构建 Board + PieceType 表 + RuleSet。
class_name PackLoader
extends RefCounted

static func load_pack(pack_dir: String) -> Dictionary:
	var board_d := _read_json(pack_dir + "/board.json")
	var pieces_d := _read_json(pack_dir + "/pieces.json")
	var rules_d := _read_json(pack_dir + "/rules.json")

	var board: Board = _build_board(board_d)
	var piece_types := _build_piece_types(pieces_d)
	var rules := RuleSet.from_dict(rules_d)

	var state := _setup_state(board, board_d, piece_types)
	return {
		"board": board, "state": state,
		"piece_types": piece_types, "rules": rules
	}

static func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Cannot open: %s (err=%d)" % [path, FileAccess.get_open_error()])
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary):
		push_error("Invalid JSON: %s" % path)
		return {}
	return parsed

static func _build_board(d: Dictionary) -> Board:
	var b := Board.new(int(d.get("width", 9)), int(d.get("height", 10)))
	for r in d.get("river", {}).get("rows", []):
		b.river_rows.append(int(r))
	var pal: Dictionary = d.get("palace", {})
	for faction in ["red", "black"]:
		var pd: Dictionary = pal.get(faction, {})
		if pd.is_empty():
			continue
		var xr: Array = pd.get("x_range", [0, 0])
		var yr: Array = pd.get("y_range", [0, 0])
		var rect := Rect2i(
			int(xr[0]), int(yr[0]),
			int(xr[1] - xr[0]) + 1, int(yr[1] - yr[0]) + 1
		)
		b.palaces[faction] = rect
	# 地形格(M0 数据为空,M1 接入)
	for cd in d.get("cells", []):
		var x := int(cd.get("x", 0))
		var y := int(cd.get("y", 0))
		var c := b.cell(x, y)
		c.terrain = int(cd.get("terrain", 0))
		c.elevation = int(cd.get("elevation", 0))
		c.pass_rule = String(cd.get("pass_rule", ""))
		var dir: Array = cd.get("pass_dir", [0, 0])
		c.pass_dir = Vector2i(int(dir[0]), int(dir[1]))
		c.pass_limit = int(cd.get("pass_limit", -1))
	return b

static func _build_piece_types(d: Dictionary) -> Dictionary:
	var types := {}
	for key in d.get("piece_types", {}).keys():
		var td: Dictionary = d["piece_types"][key]
		var pt := PieceType.from_dict(td)
		pt.id = String(key)
		types[String(key)] = pt
	return types

static func _setup_state(board: Board, d: Dictionary, piece_types: Dictionary) -> MatchState:
	var state := MatchState.new(board)
	var setup: Dictionary = d.get("setup", {})
	for faction in ["red", "black"]:
		for entry in setup.get(faction, []):
			var pt: PieceType = piece_types.get(String(entry[0]))
			if pt == null:
				push_error("Setup references unknown type: %s" % entry[0])
				continue
			state.pieces.append(Piece.new(pt, faction, int(entry[1]), int(entry[2])))
	return state
