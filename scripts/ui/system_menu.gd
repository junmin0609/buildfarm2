class_name SystemMenu
extends PanelContainer
## 시스템 메뉴 (Esc). 수동 저장·불러오기·새 게임. 열려 있는 동안 HUD 가 게임과 시간을 멈춘다.
## 실제 저장·불러오기는 SaveManager 가 한다 (Events.save_requested 등으로 요청).

signal close_requested

var _status: Label
var _new_game_btn: Button
var _confirm_new := false
var _title_btn: Button
var _confirm_title := false


func _ready() -> void:
	custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := Label.new()
	title.text = "메뉴"
	title.add_theme_font_override("font", Art.pixel_font(true))
	box.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_status.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(_status)
	for entry: Array in [["계속하기", _on_continue], ["저장하기", _on_save], ["불러오기", _on_load]]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.pressed.connect(entry[1])
		box.add_child(btn)
	_new_game_btn = Button.new()
	_new_game_btn.pressed.connect(_on_new_game)
	box.add_child(_new_game_btn)
	_title_btn = Button.new()
	_title_btn.pressed.connect(_on_title)
	box.add_child(_title_btn)
	Events.game_saved.connect(func(_kind: String) -> void: _refresh())


func open() -> void:
	_confirm_new = false
	_confirm_title = false
	_refresh()
	show()
	reset_size()


func _refresh() -> void:
	if not is_node_ready():
		return
	_new_game_btn.text = "정말 새로 시작할까요? (한 번 더 누르기)" if _confirm_new else "새 게임"
	_title_btn.text = "저장 안 한 진행은 사라져요 (한 번 더 누르기)" if _confirm_title else "시작 화면으로"
	var info := SaveManager.describe_save()
	_status.text = "저장 슬롯 1: %s" % info if info != "" else "저장 슬롯 1: 비어 있음"


func _on_continue() -> void:
	close_requested.emit()


func _on_save() -> void:
	Events.save_requested.emit()


func _on_load() -> void:
	close_requested.emit()
	Events.load_requested.emit()


## 새 게임은 한 번 더 눌러야 시작한다 (실수로 지금 진행을 잃지 않게)
func _on_new_game() -> void:
	if not _confirm_new:
		_confirm_new = true
		_refresh()
		return
	close_requested.emit()
	Events.new_game_requested.emit()


## 시작 화면으로 (한 번 더 눌러야 간다. 마지막 저장 뒤의 진행은 사라짐)
func _on_title() -> void:
	if not _confirm_title:
		_confirm_title = true
		_refresh()
		return
	close_requested.emit()
	get_tree().paused = false
	GameState.clear_pauses_and_locks()
	get_tree().change_scene_to_file(TitleScreen.TITLE_SCENE)
