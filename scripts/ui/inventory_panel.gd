class_name InventoryPanel
extends PanelContainer
## 가방 창. 칸을 하나 누르고 다른 칸을 누르면 두 칸이 자리를 바꾼다. 맨 윗줄이 핫바다.

signal close_requested

var _slots: Array[ItemSlot] = []
var _picked := -1
var _info: Label


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "가방"
	title.add_theme_font_size_override("font_size", Art.FONT_SIZE)
	title.add_theme_font_override("font", Art.pixel_font(true))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "닫기 (I)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)

	var hint := Label.new()
	hint.text = "맨 윗줄이 핫바예요. 칸을 누른 뒤 다른 칸을 누르면 자리가 바뀌어요."
	hint.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(hint)

	var grid := GridContainer.new()
	grid.columns = Inventory.HOTBAR_SIZE
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for i in GameState.inventory.size():
		var slot := ItemSlot.new()
		slot.index = i
		slot.show_number = i < Inventory.HOTBAR_SIZE
		slot.clicked.connect(_on_slot_clicked)
		slot.mouse_entered.connect(_show_info.bind(i))
		grid.add_child(slot)
		_slots.append(slot)

	_info = Label.new()
	_info.custom_minimum_size = Vector2(0, 60)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info)

	Events.inventory_changed.connect(refresh)
	refresh()


func open() -> void:
	_picked = -1
	_info.text = ""
	refresh()
	show()


func refresh() -> void:
	for i in _slots.size():
		_slots[i].set_slot(GameState.inventory.get_slot(i))
		_slots[i].picked = i == _picked
		_slots[i].set_selected(i == GameState.selected_slot and i < Inventory.HOTBAR_SIZE)


func _on_slot_clicked(index: int) -> void:
	if _picked == -1:
		if GameState.inventory.get_slot(index) != null:
			_picked = index
	else:
		GameState.inventory.swap(_picked, index)
		_picked = -1
	refresh()


func _show_info(index: int) -> void:
	var inv := GameState.inventory
	var item := inv.item_at(index)
	if item == null:
		_info.text = ""
		return
	var q := inv.quality_at(index)
	var price := "  ·  기준가 %d G" % Pricing.quality_price(item, q) if item.is_sellable() else ""
	var water := int(inv.slot_value(index, "water", -1)) if item.capacity > 0 else -1
	var lines := ItemSlot.describe(item, q, water).split("\n")
	lines[0] += price
	_info.text = "\n".join(lines)
