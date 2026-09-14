## 主场景:游戏流程控制器 —— 标题界面 → 战役界面 → 对局界面。
## 现有玩法(经典热座 / 神的试炼)作为战役「神明不会下棋」的两个关卡加载。
## ESC:任意界面唤出设置菜单(音量/分辨率/全屏,持久化)。
extends Control

const TITLE_SCREEN := preload("res://presentation/title_screen.gd")
const CAMPAIGN_SCREEN := preload("res://presentation/campaign_screen.gd")
const BATTLE_SCREEN := preload("res://presentation/battle_screen.gd")
const SETTINGS_MENU := preload("res://presentation/settings_menu.gd")

var title_screen: TitleScreen
var campaign_screen: CampaignScreen
var battle_screen: BattleScreen
var settings_menu: SettingsMenu

func _ready() -> void:
	title_screen = TITLE_SCREEN.new()
	title_screen.start_pressed.connect(show_campaign)
	title_screen.settings_pressed.connect(_toggle_settings)
	add_child(title_screen)

	campaign_screen = CAMPAIGN_SCREEN.new()
	campaign_screen.visible = false
	campaign_screen.battle_selected.connect(_on_battle_selected)
	add_child(campaign_screen)

	battle_screen = BATTLE_SCREEN.new()
	battle_screen.visible = false
	battle_screen.back_pressed.connect(show_campaign)
	add_child(battle_screen)

	settings_menu = SETTINGS_MENU.new()
	settings_menu.name = "SettingsMenu"
	add_child(settings_menu)

# ---------------------------------------------------------------- 界面切换

func show_title() -> void:
	title_screen.visible = true
	campaign_screen.visible = false
	battle_screen.visible = false

func show_campaign() -> void:
	title_screen.visible = false
	campaign_screen.visible = true
	battle_screen.visible = false

func show_battle() -> void:
	title_screen.visible = false
	campaign_screen.visible = false
	battle_screen.visible = true

func _on_battle_selected(battle: Dictionary) -> void:
	show_battle()
	battle_screen.start(battle)

# ---------------------------------------------------------------- 设置

func _toggle_settings() -> void:
	settings_menu.open()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE and not settings_menu.visible:
		settings_menu.open()
