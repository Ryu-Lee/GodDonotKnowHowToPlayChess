## 攻击系统:接触式/远程单体/远程范围 + 视线 + 反击结算。数据驱动,零渲染依赖。
class_name Combat
extends RefCounted

## 生成棋子的攻击行动列表(tactics 经济且 attack != displace 时才有独立攻击)。
static func all_attacks(state: MatchState, p: Piece) -> Array[Action]:
	var out: Array[Action] = []
	if p.type.action_economy != "tactics":
		return out
	match p.type.attack_type:
		"melee":
			for v in _melee_pattern(p):
				var tx := p.x + v.x
				var ty := p.y + v.y
				if not state.board.in_bounds(tx, ty):
					continue
				var occ := state.piece_at(tx, ty)
				if occ != null and occ.faction != p.faction:
					out.append(Action.new(p, tx, ty, Action.Kind.ATTACK, occ))
		"ranged":
			for cell in _ranged_targets(state, p):
				var occ := state.piece_at(cell.x, cell.y)
				if occ != null and occ.faction != p.faction:
					out.append(Action.new(p, cell.x, cell.y, Action.Kind.ATTACK, occ))
		"splash":
			# 溅射目标 = 射程内任意格(空格也可打,用于覆盖走位预判)
			for cell in _splash_centers(state, p):
				out.append(Action.new(p, cell.x, cell.y, Action.Kind.ATTACK, null))
		_:
			pass
	return out

## 结算一次攻击(不验证合法性,调用方先验)。返回伤害记录。
static func apply_attack(state: MatchState, act: Action) -> Array:
	act.damage_log.clear()
	match act.piece.type.attack_type:
		"melee":
			_apply_melee(state, act)
		"ranged":
			_apply_ranged(state, act)
		"splash":
			_apply_splash(state, act)
		_:
			pass
	return act.damage_log

static func _apply_melee(state: MatchState, act: Action) -> void:
	var attacker := act.piece
	var power := _attack_power(state, attacker)
	if act.target != null and act.target.alive:
		_deal(act, act.target, power)
		# 反击:目标存活且 counter 允许 => 反伤攻击方
		if act.target.alive and _can_counter(state, act.target, attacker):
			_deal(act, attacker, _attack_power(state, act.target))

static func _apply_ranged(state: MatchState, act: Action) -> void:
	var power := _attack_power(state, act.piece)
	if act.target != null and act.target.alive:
		_deal(act, act.target, power)

static func _apply_splash(state: MatchState, act: Action) -> void:
	var attacker := act.piece
	var power := _attack_power(state, attacker)
	for v in attacker.type.splash_pattern:
		var tx := act.to_x + v.x
		var ty := act.to_y + v.y
		if not state.board.in_bounds(tx, ty):
			continue
		var occ := state.piece_at(tx, ty)
		if occ != null and occ.alive:
			_deal(act, occ, power)   # 不分敌我:溅射误伤

## 撤销攻击(悔棋):按 damage_log 逆序回血。
## state 保留参数:将来地形加成回滚/数值快照需要读取局面。
static func undo_attack(_state: MatchState, act: Action) -> void:
	for i in range(act.damage_log.size() - 1, -1, -1):
		var entry: Dictionary = act.damage_log[i]
		var p: Piece = entry["piece"]
		p.hp += int(entry["dmg"])
		if p.hp > 0:
			p.alive = true
		p.x = int(entry["x"])
		p.y = int(entry["y"])

# ---------------------------------------------------------------- 目标域

static func _melee_pattern(p: Piece) -> Array[Vector2i]:
	if not p.type.attack_pattern.is_empty():
		return p.type.attack_pattern
	# 默认:正交四邻
	return [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

## 远程单体目标:射程内且视线可达的格子上的敌人。
static func _ranged_targets(state: MatchState, p: Piece) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var range := _effective_range(state, p)
	for dy in range(-range, range + 1):
		for dx in range(-range, range + 1):
			if dx == 0 and dy == 0:
				continue
			# 切比雪夫射程(八方)
			if max(abs(dx), abs(dy)) > range:
				continue
			var tx := p.x + dx
			var var_y := p.y + dy
			if not state.board.in_bounds(tx, var_y):
				continue
			if _has_line_of_sight(state, p.x, p.y, tx, var_y):
				out.append(Vector2i(tx, var_y))
	return out

## 溅射中心:射程内视线可达格(中心自身也要视线可达)。
static func _splash_centers(state: MatchState, p: Piece) -> Array[Vector2i]:
	return _ranged_targets(state, p)

# ---------------------------------------------------------------- 视线与数值

## 直线视线(布雷森汉姆);被 elevation 严格高于连线两端最大值的格子遮挡。
## 高地上的射击者/目标自身不被低地阻挡。中间棋子同样遮挡视线。
static func _has_line_of_sight(state: MatchState, x0: int, y0: int, x1: int, y1: int) -> bool:
	if x0 == x1 and y0 == y1:
		return true
	var board := state.board
	var from_h := board.cell(x0, y0).elevation
	var to_h := board.cell(x1, y1).elevation
	var min_h: int = max(from_h, to_h)
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x1 > x0 else -1
	var sy := 1 if y1 > y0 else -1
	var err := dx - dy
	var cx := x0
	var var_y := y0
	while not (cx == x1 and var_y == y1):
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			var_y += sy
		if cx == x1 and var_y == y1:
			break
		var c := board.cell(cx, var_y)
		if not board.in_bounds(cx, var_y):
			return false
		if c.elevation > min_h:
			return false
		if state.piece_at(cx, var_y) != null:
			return false
	return true

## 有效射程:基础 + 高地加成。
static func _effective_range(state: MatchState, p: Piece) -> int:
	var r := p.type.attack_range
	if state.board.cell(p.x, p.y).elevation > 0:
		r += 1
	return r

## 攻击力:预留地形/状态加成钩子(高地弓箭手加攻等),M1 基础值直取。
static func _attack_power(_state: MatchState, p: Piece) -> int:
	return p.type.attack_power

## 反击资格:近战互殴才反击;远程/溅射单位被贴脸无反击(射手怕近身)。
static func _can_counter(_state: MatchState, defender: Piece, _attacker: Piece) -> bool:
	if not defender.type.counter_attack:
		return false
	# 只有近战可反击近战;远程棋子被贴脸无反击(射手怕近身)
	if defender.type.attack_type == "ranged" or defender.type.attack_type == "splash":
		return false
	return true

static func _deal(act: Action, target: Piece, dmg: int) -> void:
	target.hp -= dmg
	act.damage_log.append({
		"piece": target, "dmg": dmg, "x": target.x, "y": target.y
	})
	if target.hp <= 0:
		target.hp = 0
		target.alive = false
