## 战役界面:列出战役 JSON 中的关卡(战役模式入口)。
## 数据驱动:campaign JSON -> {base_pack, extra_packs, ai, scenario} 每关一套。
class_name CampaignScreen
extends Control

## 战斗配置(点击关卡时发出,由 battle_screen 消费)。
signal battle_selected(battle: Dictionary)

var battles: Array = []
var _info_label: Label
var _start_button: Button
var _selected: int = -1

const CAMPAIGN_PATH := "res://data/campaigns/gods_trial.json"

func _ready() -> void:
	custom_minimum_size = Vector2(640, 360)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#1a1208")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "战役 · 神明不会下棋"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#e8d3a0"))
	title.position = Vector2(24, 12)
	add_child(title)

	var back := Button.new()
	back.text = "← 返回"
	back.position = Vector2(540, 10)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func() -> void:
		var flow := get_parent()
		if flow != null and flow.has_method("show_title"):
			flow.show_title()
	)
	add_child(back)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color("#c8b088"))
	_info_label.position = Vector2(24, 250)
	_info_label.size = Vector2(420, 90)
	add_child(_info_label)

	_start_button = Button.new()
	_start_button.text = "开始战斗"
	_start_button.position = Vector2(480, 300)
	_start_button.size = Vector2(120, 32)
	_start_button.focus_mode = Control.FOCUS_NONE
	_start_button.disabled = true
	_start_button.add_theme_font_size_override("font_size", 13)
	_start_button.pressed.connect(func() -> void:
		if _selected >= 0 and _selected < battles.size():
			battle_selected.emit(battles[_selected])
	)
	add_child(_start_button)

	_load_battles()

func _load_battles() -> void:
	var f := FileAccess.open(CAMPAIGN_PATH, FileAccess.READ)
	if f == null:
		push_error("Cannot open campaign: %s" % CAMPAIGN_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary):
		push_error("Invalid campaign JSON: %s" % CAMPAIGN_PATH)
		return
	battles = parsed.get("battles", [])
	var y := 60
	for i in battles.size():
		var b: Dictionary = battles[i]
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, String(b.get("name", "?"))]
		btn.position = Vector2(24, y)
		btn.size = Vector2(260, 34)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		var idx := i
		btn.pressed.connect(func() -> void: _select(idx))
		add_child(btn)
		y += 44
	if not battles.is_empty():
		_select(0)

func _select(idx: int) -> void:
	_selected = idx
	var b: Dictionary = battles[idx]
	_info_label.text = "%s\n%s" % [String(b.get("name", "")), String(b.get("description", ""))]
	_start_button.disabled = false

## ESC 支持(设置菜单由 flow 层统一接管,这里只标记不消费)。
func _unhandled_input(event: InputEvent) -> void:
	pass
