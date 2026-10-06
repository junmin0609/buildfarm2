class_name TitleScreen
extends Control
## 시작 화면 (BUILD_FARM_AI_BRIDGE: UI 마감 단계의 타이틀 화면). 게임을 켜면 가장 먼저 뜬다.
##   이어하기  저장이 있을 때만. 저장한 곳에서 이어서 (SaveManager.load_on_start)
##   새 게임   저장이 있으면 한 번 더 눌러야 시작 (다음 자동 저장 때 덮어쓴다)
##   설정      전체 화면 켜기/끄기, 조작 방법
##   종료
## 뒤에는 농장 풍경을 도트로 그린다 (TitleBackground).

const MAIN_SCENE := "res://scenes/main.tscn"
const TITLE_SCENE := "res://scenes/title.tscn"
const TEXT := HUD.TEXT
const TEXT_SOFT := HUD.TEXT_SOFT

## 게임 화면으로 넘어가는 방법 (점검에서는 바꿔 끼워 장면이 바뀌지 않게 한다)
var open_main := func() -> void: get_tree().change_scene_to_file(MAIN_SCENE)

var _menu: VBoxContainer
var _settings: VBoxContainer
var _continue: Button
var _new_game: Button
var _save_info: Label
var _fullscreen: Button
var _confirm_new := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = HUD.ui_theme()
	get_tree().paused = false
	GameState.clear_pauses_and_locks()

	var bg := TitleBackground.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "BuildFarm"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", Art.pixel_font(true))
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("6b8a3a"))
	box.add_child(title)
	var sub := _small("농사 · 건축 · 자동화")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	# 메인 메뉴
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	box.add_child(_menu)
	_continue = _button("이어하기", continue_game, _menu)
	_save_info = _small("")
	_save_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(_save_info)
	_new_game = _button("새 게임", new_game, _menu)
	_button("설정", func() -> void: _show_settings(true), _menu)
	_button("종료", func() -> void: get_tree().quit(), _menu)

	# 설정
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 10)
	_settings.hide()
	box.add_child(_settings)
	_fullscreen = _button("", _toggle_fullscreen, _settings)
	var keys := _small("조작 방법\nWASD 이동 · 클릭 도구 사용 · E 상호작용\nI 가방 · B 건설 · R 회전 · 1~9 핫바 · Esc 메뉴")
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings.add_child(keys)
	_button("돌아가기", func() -> void: _show_settings(false), _settings)

	refresh()


func _button(text: String, action: Callable, parent: Container) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(action)
	parent.add_child(btn)
	return btn


func _small(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", TEXT_SOFT)
	return label


func refresh() -> void:
	var info := SaveManager.describe_save()
	var has_save := FileAccess.file_exists(SaveManager.slot_path)
	_continue.disabled = not has_save
	_save_info.text = "저장: %s" % info if has_save else "저장된 게임이 없어요"
	_new_game.text = "정말 새로 시작할까요? (한 번 더 누르기)" if _confirm_new else "새 게임"
	_fullscreen.text = "전체 화면: %s" % ("켜짐" if Settings.fullscreen else "꺼짐")


func continue_game() -> void:
	if not FileAccess.file_exists(SaveManager.slot_path):
		return
	SaveManager.skip_load_once = false
	SaveManager.load_on_start = true
	open_main.call()


## 저장이 있으면 한 번 더 눌러야 시작한다 (실수로 진행을 덮어쓰지 않게)
func new_game() -> void:
	if FileAccess.file_exists(SaveManager.slot_path) and not _confirm_new:
		_confirm_new = true
		refresh()
		return
	_confirm_new = false
	SaveManager.skip_load_once = true
	GameState.new_game()
	open_main.call()


func _show_settings(on: bool) -> void:
	_confirm_new = false
	_menu.visible = not on
	_settings.visible = on
	refresh()


func _toggle_fullscreen() -> void:
	Settings.set_fullscreen(not Settings.fullscreen)
	refresh()
