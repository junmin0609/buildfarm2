class_name DialogPanel
extends PanelContainer
## 상점 NPC 대화 창 (사용자 요청: 상점 안 NPC에게 말 걸기). 화면 아래쪽에 이름 · 인사 · 고를 것 버튼.
##   [씨앗·비료 사기] [작물·가공품 팔기] [나가기] 처럼 NPC 마다 다르다 (Interior.ROOMS 의 options).
## 고르면 chosen(하는 일) 을 보내고, HUD 가 상점·강화 창을 연다. 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal chosen(action: String)
signal close_requested

var npc: Npc
var _name: Label
var _line: Label
var _buttons: HBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_name = Label.new()
	_name.add_theme_font_override("font", Art.pixel_font(true))
	_name.add_theme_color_override("font_color", Color("c98a2e"))
	box.add_child(_name)
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(860, 0)  # 줄바꿈 글은 폭이 정해져야 높이가 제대로 잡힌다
	box.add_child(_line)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 12)
	box.add_child(_buttons)


func open(target: Npc) -> void:
	npc = target
	_name.text = npc.npc_name
	_line.text = npc.greeting
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for option: Array in npc.options:
		var btn := Button.new()
		btn.text = str(option[0])
		var action := str(option[1])
		btn.pressed.connect(func() -> void: choose(action))
		_buttons.add_child(btn)
	show()
	reset_size()


## 고른다 ("" 이면 그냥 닫기)
func choose(action: String) -> void:
	if action == "":
		close_requested.emit()
	else:
		chosen.emit(action)
