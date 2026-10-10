class_name BuildPanel
extends PanelContainer
## 건설 창 (B). 설치할 시설을 고르거나, 이미 놓은 시설을 옮기기·철거하기 모드로 들어간다.
## 목록은 data/placeables.json 에서 자동으로 만든다.

signal close_requested

## 기준 화면 1280x720 안에 창 전체(제목·안내·목록·옮기기/철거 버튼)가 들어가는 높이
const LIST_HEIGHT := 440

var _list: VBoxContainer
var _money: Label


func _ready() -> void:
	custom_minimum_size = Vector2(1100, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var title := Label.new()
	title.text = "건설"
	title.add_theme_font_override("font", Art.pixel_font(true))
	header.add_child(title)
	_money = Label.new()
	_money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_money)
	var close := Button.new()
	close.text = "닫기 (B)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)

	var hint := Label.new()
	hint.text = "농장 땅 위에 시설을 놓아요. 기계는 기계상점(용광로는 대장간)에서 사서 가방에 있어야 놓을 수 있어요. 철거하면 모두 돌려받아요."
	hint.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(hint)

	# 시설이 많아져 화면을 넘지 않도록 목록은 스크롤
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	box.add_child(scroll)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 12)
	tools.alignment = BoxContainer.ALIGNMENT_END
	for entry: Array in [["옮기기", "move"], ["철거하기", "remove"]]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.pressed.connect(_choose.bind(entry[1], ""))
		tools.add_child(btn)
	box.add_child(tools)

	Events.money_changed.connect(func(_m: int) -> void: refresh())


func open() -> void:
	refresh()
	show()
	reset_size()


func refresh() -> void:
	if not is_node_ready():
		return
	_money.text = "가진 돈  %d G" % GameState.money
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for def in PlaceableDB.all():
		if def.data.has("fixture"):
			continue  # 집·출하함·우물은 짓지 않고 [옮기기]로만 고른다
		_list.add_child(_row(def))


func _row(def: PlaceableDef) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var thumb := TextureRect.new()
	thumb.texture = def.texture if def.texture else thumbnail_of(def)
	thumb.custom_minimum_size = Vector2(64, 64)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(thumb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = "%s  %dx%d" % [def.name, def.size.x, def.size.y]
	info.add_child(name_label)
	var desc := Label.new()
	desc.text = def.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # 설명이 길어도 창이 화면 밖으로 넓어지지 않게
	desc.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	desc.add_theme_color_override("font_color", Color("9a7457"))
	info.add_child(desc)
	row.add_child(info)
	var price := Label.new()
	var machine := def.machine_item()
	# 기계는 값 대신 가방에 든 개수 (기계상점에서 사서 놓는다, 사용자 결정)
	price.text = "가방에 %d개" % GameState.inventory.count_of(machine.id) if machine else def.cost_text()
	if machine and GameState.inventory.count_of(machine.id) == 0:
		price.text += "\n대장간에서 사요" if machine.shop == "smith" else "\n기계상점에서 사요"
	# 기술이 잠긴 시설은 해금 조건 (새 게임만, 스토리 3단계). 이미 놓은 것은 그대로 옮길 수 있다
	var lock := QuestManager.lock_reason_now(def.id)
	if lock != "":
		price.text = QuestManager.lock_short_now(def.id)  # 자세한 조건은 퀘스트 창 기술 탭
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.add_theme_color_override("font_color", Color("b8a58c") if lock != "" else Color("c98a2e"))
	row.add_child(price)
	var btn := Button.new()
	btn.text = "배치"
	btn.disabled = lock != "" or def.afford_problem(GameState.inventory) != ""
	btn.pressed.connect(_choose.bind("place", def.id))
	row.add_child(btn)
	return row


## 그림이 없는 시설(컨베이어: 바닥 벨트라 노드가 직접 그림)은 재료 아이템 아이콘으로 보여 준다
static func thumbnail_of(def: PlaceableDef) -> Texture2D:
	for mat_id: String in def.materials:
		var item := ItemDB.get_item(mat_id)
		if item:
			var tex := AtlasTexture.new()
			tex.atlas = Art.ITEMS
			tex.region = Art.item_region(item)
			return tex
	return null


func _choose(what: String, def_id: String) -> void:
	close_requested.emit()
	Events.build_requested.emit(what, def_id)
