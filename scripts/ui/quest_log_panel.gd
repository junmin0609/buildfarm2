class_name QuestLogPanel
extends PanelContainer
## 퀘스트 목록 (스토리 2단계, Q). 메인 퀘스트 20개를 장별로: 진행 중 / 완료(보상 받음·대기) / 잠김.
## 진행 중·완료 퀘스트는 설명·목표 진행도·보상, 잠긴 퀘스트는 제목만 흐리게.
## 맨 위에 지금 시대 (기존 저장은 '기존 저장 · 모든 기술 해금') 와 열린 기술.
## [기술·복구] 탭 (3단계): 시대별 기술 (열림 / 잠김 + 해금 조건) 과 복구 프로젝트 (필요·넣은 양·가진 양, [넣기]).
## 다른 창처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

const LIST_HEIGHT := 520
const TEXT := Color("5b3a29")
const TEXT_SOFT := Color("9a7457")
const ACTIVE := Color("c98a2e")
const DONE := Color("5f9a5d")
const LOCKED := Color("b8a58c")

var quests: QuestManager
## 보이는 탭: "quests" 퀘스트 / "tech" 기술·복구
var tab := "quests"
var _tab_buttons := {}
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
	for t: Array in [["quests", "퀘스트"], ["tech", "기술·복구"]]:
		var tb := Button.new()
		tb.text = t[1]
		tb.toggle_mode = true
		var key: String = t[0]
		tb.pressed.connect(func() -> void: show_tab(key))
		_tab_buttons[key] = tb
		header.add_child(tb)
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


func show_tab(key: String) -> void:
	tab = key
	refresh()


## 퀘스트 상태 글: 진행 중 / 완료 · 보상 받음 / 완료 · 보상 대기 / 잠김
static func state_text(state: String) -> String:
	return {QuestManager.ACTIVE: "진행 중", QuestManager.REWARDED: "완료 · 보상 받음", QuestManager.COMPLETED: "완료 · 보상 대기 (가방 자리 필요)"}.get(state, "잠김")


func refresh() -> void:
	if not is_node_ready() or not visible or quests == null:
		return
	_era.text = "시대: " + quests.era_label()
	_techs.text = "열린 기술: " + " · ".join(quests.unlocked_tech_names())
	for key: String in _tab_buttons:
		(_tab_buttons[key] as Button).button_pressed = key == tab
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if tab == "tech":
		_fill_tech()
		return
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


## 기술·복구 탭: 시대별 기술, 그 아래 복구 프로젝트
func _fill_tech() -> void:
	var all: Dictionary = QuestManager.data().get("techs", {})
	var ids := QuestManager.era_ids()
	for e: Dictionary in QuestManager.data().get("eras", []):
		var here: bool = not quests.legacy and str(e.id) == quests.era
		var reached: bool = quests.legacy or ids.find(e.id) <= ids.find(quests.era)
		_list.add_child(_heading("%s%s" % [e.name, "  (지금)" if here else ""], ACTIVE if here else (TEXT if reached else LOCKED)))
		for tech_id: String in all:
			if all[tech_id].era != e.id:
				continue
			var t: Dictionary = all[tech_id]
			var items: Array = t.get("items", [])
			var names := " · ".join(items.map(func(i: String) -> String: return _thing_name(i)))
			var line := "%s%s" % [t.name, ("  (" + names + ")") if names != "" else ""]
			if quests.is_unlocked(tech_id):
				_list.add_child(_small("· 열림  " + line, DONE))
			else:
				_list.add_child(_small("· 잠김  %s — %s에서 해금" % [line, QuestManager.tech_source(tech_id)], LOCKED))
	_list.add_child(_heading("복구 프로젝트", TEXT))
	for pid: String in QuestManager.project_defs():
		_list.add_child(_project_row(pid))


func _project_row(pid: String) -> Control:
	var p: Dictionary = QuestManager.project_defs()[pid]
	var box := VBoxContainer.new()
	box.name = pid
	box.add_theme_constant_override("separation", 2)
	var done := quests.project_done(pid)
	var problem := quests.project_problem(pid)
	var state := "완료" if done else ("진행 가능" if problem == "" else problem)
	var head := Label.new()
	head.text = "%s · %s" % [p.name, state]
	head.add_theme_color_override("font_color", DONE if done else (ACTIVE if problem == "" else LOCKED))
	box.add_child(head)
	if p.get("todo", false):
		box.add_child(_small("조건은 나중에 공개돼요.", LOCKED))
		return box
	for row: Dictionary in quests.project_rows(pid):
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var left := int(row.need) - int(row.given)
		var txt := _small("· %s  넣은 양 %d/%d  ·  가진 것 %d%s" % [row.name, row.given, row.need, row.have, ("  ·  남은 것 %d" % left) if left > 0 else ""], DONE if left <= 0 else TEXT)
		txt.custom_minimum_size = Vector2(760, 0)
		line.add_child(txt)
		if not done and left > 0:
			var btn := Button.new()
			btn.text = "내기" if row.key == "money" else "넣기"
			btn.disabled = problem != "" or int(row.have) <= 0
			var key: String = row.key
			btn.pressed.connect(func() -> void:
				var n := quests.donate(pid, key)
				Events.toast.emit(("%s %d 넣었어요." % [row.name, n]) if n > 0 else "넣을 수 없어요."))
			line.add_child(btn)
		box.add_child(line)
	var unlock: Array = p.get("unlock", [])
	if not unlock.is_empty():
		var all: Dictionary = QuestManager.data().get("techs", {})
		box.add_child(_small("완료하면: " + " · ".join(unlock.map(func(t: String) -> String: return str(all.get(t, {}).get("name", t)))) + " 해금", TEXT_SOFT))
	return box


func _heading(text: String, color: Color) -> Label:
	var h := Label.new()
	h.text = text
	h.add_theme_font_override("font", Art.pixel_font(true))
	h.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	h.add_theme_color_override("font_color", color)
	return h


## 아이템·시설 이름 (아이템이 아니면 시설 정의에서)
static func _thing_name(id: String) -> String:
	var it := ItemDB.get_item(id)
	if it:
		return it.name
	var def := PlaceableDB.get_def(id)
	return def.name if def else id


func _small(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(940, 0)
	return l
