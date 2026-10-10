class_name QuestTracker
extends PanelContainer
## 화면 왼쪽 위 작은 퀘스트 추적 (스토리 2단계). 진행 중인 메인 퀘스트 하나의 제목과 목표 최대 2개 (진행도/필요 수량).
## 진행 중인 퀘스트가 없으면 숨는다. 클릭을 막지 않는다 (mouse_filter IGNORE). Q 로 퀘스트 목록.

const MAX_LINES := 2
const TEXT := Color("5b3a29")
const TEXT_SOFT := Color("9a7457")
const DONE := Color("5f9a5d")

var quests: QuestManager
var _title: Label
var _lines: Array[Label] = []
## 복구 프로젝트 안내 (4단계): "Q → 기술·복구 탭에서 납품 (또는 …)"
var _hint: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(340, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title = _label(Art.FONT_SIZE, TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var key := _label(Art.FONT_SIZE_SMALL, TEXT_SOFT)
	key.text = "Q 퀘스트"
	head.add_child(key)
	box.add_child(head)
	for i in MAX_LINES:
		var l := _label(Art.FONT_SIZE_SMALL, TEXT_SOFT)
		_lines.append(l)
		box.add_child(l)
	_hint = _label(Art.FONT_SIZE_SMALL, Color("c98a2e"))
	box.add_child(_hint)
	Events.quest_changed.connect(func(_id: String) -> void: refresh())
	Events.game_loaded.connect(refresh)
	refresh()


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func refresh() -> void:
	if not is_node_ready():
		return
	var q: Dictionary = quests.tracked() if quests else {}
	visible = not q.is_empty()
	if q.is_empty():
		return
	_title.text = q.title
	var objs: Array = q.get("objectives", [])
	for i in MAX_LINES:
		var l := _lines[i]
		l.visible = i < objs.size()
		if not l.visible:
			continue
		var line := quests.objective_line(q, i)
		var done := int(quests.progress_of(q.id)[i]) >= int(objs[i].get("count", 1))
		l.text = "· " + line
		l.add_theme_color_override("font_color", DONE if done else TEXT_SOFT)
	_hint.text = quests.project_hint()
	_hint.visible = _hint.text != ""
	reset_size()
