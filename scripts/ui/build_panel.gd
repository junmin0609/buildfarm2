class_name BuildPanel
extends PanelContainer
## 건설 창 (B). 설치할 시설을 고르거나, 이미 놓은 시설을 옮기기·철거하기 모드로 들어간다.
## 목록은 data/placeables.json 에서 자동으로 만든다.

signal close_requested

var _list: VBoxContainer
var _money: Label


func _ready() -> void:
	custom_minimum_size = Vector2(720, 0)
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
	hint.text = "농장 땅 위에 시설을 놓아요. 장애물은 먼저 치워야 해요. 철거하면 값을 모두 돌려받아요."
	hint.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(hint)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)

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
		_list.add_child(_row(def))


func _row(def: PlaceableDef) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var thumb := TextureRect.new()
	thumb.texture = def.texture
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
	desc.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	desc.add_theme_color_override("font_color", Color("9a7457"))
	info.add_child(desc)
	row.add_child(info)
	var price := Label.new()
	price.text = "%d G" % def.price
	price.add_theme_color_override("font_color", Color("c98a2e"))
	row.add_child(price)
	var btn := Button.new()
	btn.text = "배치"
	btn.disabled = GameState.money < def.price
	btn.pressed.connect(_choose.bind("place", def.id))
	row.add_child(btn)
	return row


func _choose(what: String, def_id: String) -> void:
	close_requested.emit()
	Events.build_requested.emit(what, def_id)
