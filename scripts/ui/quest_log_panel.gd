class_name QuestLogPanel
extends PanelContainer
## 퀘스트 목록 (스토리 2단계, Q). 메인 퀘스트 20개를 장별로: 진행 중 / 완료(보상 받음·대기) / 잠김.
## 진행 중·완료 퀘스트는 설명·목표 진행도·보상, 잠긴 퀘스트는 제목만 흐리게.
## 맨 위에 지금 시대 (기존 저장은 '기존 저장 · 모든 기술 해금') 와 열린 기술.
## 다른 창처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

const LIST_HEIGHT := 520
const TEXT := Color("5b3a29")
const TEXT_SOFT := Color("9a7457")
const ACTIVE := Color("c98a2e")
const DONE := Color("5f9a5d")
const LOCKED := Color("b8a58c")

var quests: QuestManager
var _era: Label
var _techs: Label
var _list: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(1000, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var title := Label.new()
	title.text = "퀘스트"
	title.add_theme_font_override("font", Art.pixel_font(true))
	header.add_child(title)
	_era = Label.new()
	_era.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_era.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_era.add_theme_color_override("font_color", ACTIVE)
	header.add_child(_era)
	var close := Button.new()
	close.text = "닫기 (Q)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)
	_techs = Label.new()
	_techs.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_techs.add_theme_color_override("font_color", TEXT_SOFT)
	_techs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_techs.custom_minimum_size = Vector2(960, 0)
	box.add_child(_techs)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	box.add_child(scroll)
	Events.quest_changed.connect(func(_id: String) -> void: refresh())


func open() -> void:
	show()
	refresh()


## 퀘스트 상태 글: 진행 중 / 완료 · 보상 받음 / 완료 · 보상 대기 / 잠김
static func state_text(state: String) -> String:
	return {QuestManager.ACTIVE: "진행 중", QuestManager.REWARDED: "완료 · 보상 받음", QuestManager.COMPLETED: "완료 · 보상 대기 (가방 자리 필요)"}.get(state, "잠김")


func refresh() -> void:
	if not is_node_ready() or not visible or quests == null:
		return
	_era.text = "시대: " + quests.era_label()
	_techs.text = "열린 기술: " + " · ".join(quests.unlocked_tech_names())
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var chapter := 0
	for q: Dictionary in QuestManager.quest_defs():
		if int(q.chapter) != chapter:
			chapter = int(q.chapter)
			var ch := Label.new()
			ch.text = "제%d장" % chapter
			ch.add_theme_font_override("font", Art.pixel_font(true))
			ch.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
			_list.add_child(ch)
		_list.add_child(_row(q))


func _row(q: Dictionary) -> Control:
	var st := quests.state_of(q.id)
	var row := VBoxContainer.new()
	row.name = q.id
	row.add_theme_constant_override("separation", 0)
	var head := Label.new()
	head.text = "%s  %s · %s" % [q.id, q.title, state_text(st)]
	head.add_theme_color_override("font_color", {QuestManager.ACTIVE: ACTIVE, QuestManager.REWARDED: DONE, QuestManager.COMPLETED: DONE}.get(st, LOCKED))
	row.add_child(head)
	if st == QuestManager.LOCKED:
		row.add_child(_small("앞 퀘스트를 끝내면 열려요.", LOCKED))
		return row
	row.add_child(_small(str(q.get("description", "")), TEXT_SOFT))
	var objs: Array = q.get("objectives", [])
	for i in objs.size():
		var done := st != QuestManager.ACTIVE or int(quests.progress_of(q.id)[i]) >= int(objs[i].get("count", 1))
		row.add_child(_small("· " + quests.objective_line(q, i), DONE if done else TEXT))
	row.add_child(_small("보상: %s%s" % [quests.reward_text(q), "  (받음)" if st == QuestManager.REWARDED else ""], TEXT_SOFT))
	return row


func _small(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(940, 0)
	return l
