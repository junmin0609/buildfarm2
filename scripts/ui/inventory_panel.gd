class_name InventoryPanel
extends PanelContainer
## 가방 창. 칸을 끌어다 놓으면 자리를 바꾸거나 같은 물건끼리 합친다 (핫바와도). 맨 윗줄이 핫바다.
## 설명은 아래 고정 칸 대신 커서 옆 툴팁(ItemTooltip)으로 보여 준다 (§45).

signal close_requested

var _slots: Array[ItemSlot] = []


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
	hint.text = "끌어다 놓으면 자리가 바뀌거나 같은 물건끼리 합쳐져요. 맨 윗줄이 핫바예요."
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
		slot.draggable = true
		slot.clicked.connect(_on_slot_clicked)
		grid.add_child(slot)
		_slots.append(slot)

	Events.inventory_changed.connect(refresh)
	refresh()


func open() -> void:
	refresh()
	show()


func refresh() -> void:
	for i in _slots.size():
		_slots[i].set_slot(GameState.inventory.get_slot(i))
		_slots[i].set_selected(i == GameState.selected_slot and i < Inventory.HOTBAR_SIZE)


## 맨 윗줄(핫바) 칸을 누르면 그 칸을 손에 든다
func _on_slot_clicked(index: int) -> void:
	if index < Inventory.HOTBAR_SIZE:
		GameState.select_slot(index)
