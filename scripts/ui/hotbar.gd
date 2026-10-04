class_name Hotbar
extends PanelContainer
## 화면 아래 핫바. 숫자키 1~9, 마우스 휠, 클릭으로 고른다. 가방 창과 끌어다 놓기로 물건을 주고받는다.

var _slots: Array[ItemSlot] = []


func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for i in Inventory.HOTBAR_SIZE:
		var slot := ItemSlot.new()
		slot.index = i
		slot.show_number = true
		slot.draggable = true
		slot.clicked.connect(GameState.select_slot)
		row.add_child(slot)
		_slots.append(slot)
	Events.inventory_changed.connect(refresh)
	Events.hotbar_selection_changed.connect(func(_i: int) -> void: refresh())
	refresh()


func refresh() -> void:
	for i in _slots.size():
		_slots[i].set_slot(GameState.inventory.get_slot(i))
		_slots[i].set_selected(i == GameState.selected_slot)
