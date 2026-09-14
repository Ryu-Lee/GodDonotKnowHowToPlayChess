## 设置菜单:音量(Master/Music/SFX)/ 分辨率(至 1080p)/ 全屏 / 窗口模式。
## ESC 或关闭按钮收起;持久化到 user://settings.cfg。
class_name SettingsMenu
extends Control

signal closed

const SETTINGS_PATH := "user://settings.cfg"
## 分辨率档(最高 1080p;基础设计分辨率 640×360,stretch=viewport 自适应)。
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(640, 360), Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1920, 1080)
]

var _panel: PanelContainer
var _volume_labels: Dictionary = {}   # bus -> Label

func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # 挡住下层输入

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	_panel = PanelContainer.new()
	_panel.position = Vector2(160, 60)
	_panel.size = Vector2(320, 240)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("#e8d3a0"))
	vb.add_child(title)

	# 音量三条总线
	for bus in ["Master", "Music", "SFX"]:
		_add_volume_row(vb, bus)

	vb.add_child(HSeparator.new())

	# 分辨率
	var res_row := HBoxContainer.new()
	res_row.add_child(_caption("分辨率"))
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.add_theme_font_size_override("font_size", 12)
	for r in RESOLUTIONS:
		opt.add_item("%d × %d" % [r.x, r.y])
	opt.item_selected.connect(func(idx: int) -> void: _apply_resolution(idx))
	res_row.add_child(opt)
	vb.add_child(res_row)
	_res_option = opt

	# 全屏
	var fs_btn := CheckButton.new()
	fs_btn.text = "全屏"
	fs_btn.focus_mode = Control.FOCUS_NONE
	fs_btn.add_theme_font_size_override("font_size", 12)
	fs_btn.toggled.connect(func(on: bool) -> void:
		_apply_fullscreen(on)
	)
	_fullscreen_btn = fs_btn
	vb.add_child(fs_btn)

	vb.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "关闭 (ESC)"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.pressed.connect(close)
	vb.add_child(close_btn)

	_load_settings()

var _fullscreen_btn: CheckButton
var _res_option: OptionButton

## 打开/收起。
func open() -> void:
	visible = true
	_sync_ui()

func close() -> void:
	visible = false
	closed.emit()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and \
			event.button_index == MOUSE_BUTTON_LEFT:
		var panel_rect := Rect2(_panel.position, _panel.size)
		if not panel_rect.has_point(event.position):
			close()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- 音量

func _add_volume_row(parent: Control, bus_name: String) -> void:
	var row := HBoxContainer.new()
	row.add_child(_caption(bus_name))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(140, 16)
	slider.focus_mode = Control.FOCUS_NONE
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		slider.value = db_to_linear(AudioServer.get_bus_volume_db(idx))
	slider.value_changed.connect(func(v: float) -> void: _set_volume(bus_name, v))
	row.add_child(slider)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 11)
	label.custom_minimum_size = Vector2(36, 0)
	label.text = "%d%%" % int(round(slider.value * 100))
	slider.value_changed.connect(func(v: float) -> void:
		label.text = "%d%%" % int(round(v * 100))
	)
	row.add_child(label)
	_volume_labels[bus_name] = label
	parent.add_child(row)

func _set_volume(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
	AudioServer.set_bus_mute(idx, v <= 0.001)
	_save_settings()

func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.custom_minimum_size = Vector2(64, 0)
	return l

# ---------------------------------------------------------------- 显示

func _apply_resolution(idx: int) -> void:
	if idx < 0 or idx >= RESOLUTIONS.size():
		return
	var r := RESOLUTIONS[idx]
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		# 全屏下只记录选择,退出全屏时生效
		_save_settings(r)
		return
	if mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
		# 最大化窗口 set_size 是静默 no-op:先退回窗口模式再改尺寸
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_fullscreen_btn.button_pressed = false
	DisplayServer.window_set_size(r)
	_center_window()
	_save_settings()

func _apply_fullscreen(on: bool) -> void:
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var r := _saved_resolution()
		DisplayServer.window_set_size(r)
		_center_window()
	_save_settings()

func _center_window() -> void:
	var screen := DisplayServer.screen_get_usable_rect()
	var w := DisplayServer.window_get_size()
	DisplayServer.window_set_position(
		screen.position + (screen.size - w) / 2)

func _saved_resolution() -> Vector2i:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var w := int(cfg.get_value("display", "width", 960))
		var h := int(cfg.get_value("display", "height", 540))
		return Vector2i(w, h)
	return Vector2i(960, 540)

# ---------------------------------------------------------------- 持久化

func _save_settings(res_override: Vector2i = Vector2i.ZERO) -> void:
	var cfg := ConfigFile.new()
	for bus in _volume_labels.keys():
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			cfg.set_value("audio", bus, db_to_linear(AudioServer.get_bus_volume_db(idx)))
	var mode := DisplayServer.window_get_mode()
	cfg.set_value("display", "fullscreen", mode == DisplayServer.WINDOW_MODE_FULLSCREEN)
	if res_override != Vector2i.ZERO:
		cfg.set_value("display", "width", res_override.x)
		cfg.set_value("display", "height", res_override.y)
	elif mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		var sz := DisplayServer.window_get_size()
		cfg.set_value("display", "width", sz.x)
		cfg.set_value("display", "height", sz.y)
	else:
		var saved := _saved_resolution()
		cfg.set_value("display", "width", saved.x)
		cfg.set_value("display", "height", saved.y)
	cfg.save(SETTINGS_PATH)

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for bus in ["Master", "Music", "SFX"]:
		var v := float(cfg.get_value("audio", bus, 1.0))
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
			AudioServer.set_bus_mute(idx, v <= 0.001)
	var fs := bool(cfg.get_value("display", "fullscreen", false))
	if fs:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		var w := int(cfg.get_value("display", "width", 960))
		var h := int(cfg.get_value("display", "height", 540))
		DisplayServer.window_set_size(Vector2i(w, h))
		_center_window()

## 打开时把 UI 状态同步到当前配置。
func _sync_ui() -> void:
	if _fullscreen_btn != null:
		_fullscreen_btn.button_pressed = \
			DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if _res_option != null:
		var sz := _saved_resolution()
		for i in RESOLUTIONS.size():
			if RESOLUTIONS[i] == sz:
				_res_option.selected = i
				break
