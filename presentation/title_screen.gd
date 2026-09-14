## 标题界面:开始(战役)/ 设置 / 退出。
class_name TitleScreen
extends Control

signal start_pressed
signal settings_pressed

func _ready() -> void:
	custom_minimum_size = Vector2(640, 360)
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color("#1a1208")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "神明不会下棋"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color("#e8d3a0"))
	title.position = Vector2(180, 80)
	title.size = Vector2(280, 60)
	add_child(title)

	var subtitle := Label.new()
	subtitle.text = "God Don't Know How To Play Chess"
	subtitle.add_theme_font_size_override("font_size", 11)
	subtitle.add_theme_color_override("font_color", Color("#8a6a3f"))
	subtitle.position = Vector2(180, 140)
	subtitle.size = Vector2(280, 20)
	add_child(subtitle)

	var start_btn := _button("开始游戏", Vector2(240, 200), 160)
	start_btn.pressed.connect(func() -> void: start_pressed.emit())
	add_child(start_btn)

	var settings_btn := _button("设置", Vector2(240, 240), 160)
	settings_btn.pressed.connect(func() -> void: settings_pressed.emit())
	add_child(settings_btn)

	var quit_btn := _button("退出游戏", Vector2(240, 280), 160)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	add_child(quit_btn)

	var hint := Label.new()
	hint.text = "ESC: 设置"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color("#6b5a3f"))
	hint.position = Vector2(16, 342)
	add_child(hint)

func _button(text: String, pos: Vector2, w: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.position = pos
	btn.size = Vector2(w, 32)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 14)
	return btn
