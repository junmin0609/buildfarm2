class_name WarehousePanel
extends PanelContainer
## 창고 창 (§67, §68). 위: 창고 칸 / 아래: 가방 칸.
##   칸 클릭 = 한 묶음 옮기기, 우클릭 = 1개만 옮기기 (창고 ↔ 가방)
##   받을 물건(필터)은 위쪽에서 고른다. "지정 아이템"이면 [가방에서 고르기] 를 누른 뒤 가방 칸을 클릭해 추가하고,
##   추가된 아이콘을 누르면 뺀다. 필터에 맞지 않는 가방 물건은 흐리게 보인다.
## 출하함처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

const VISIBLE_ROWS := 3
const COLUMNS := 9

var warehouse: Warehouse
## true 면 가방 칸 클릭이 "지정 아이템 필터에 추가"가 된다
var picking := false

var _title: Label
var _filter: OptionButton
var _chips: HBoxContainer
var _pick: Button
var _scroll: ScrollContainer
var _store_grid: GridContainer
var _store_slots: Array[ItemSlot] = []
var _bag_slots: Array[ItemSlot] = []
var _upgrade: Button
var _upgrade_cost: Label
var _deposit_all: Button


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)

	var header := HBoxContainer.new()
	_title = Label.new()
	_title.add_theme_font_override("font", Art.pixel_font(true))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)

	# 필터 줄
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 10)
	var filter_label := _small_label("받을 물건", Color("c98a2e"))
	filter_row.add_child(filter_label)
	_filter = OptionButton.new()
	_filter.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	for mode: String in Warehouse.FILTERS:
		_filter.add_item(Warehouse.FILTERS[mode])
		_filter.set_item_metadata(_filter.item_count - 1, mode)
	_filter.item_selected.connect(_on_filter_selected)
	filter_row.add_child(_filter)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 4)
	filter_row.add_child(_chips)
	_pick = Button.new()
	_pick.toggle_mode = true
	_pick.text = "가방에서 고르기"
	_pick.tooltip_text = "누른 뒤 가방 칸을 클릭하면 받을 물건에 추가돼요. 위 아이콘을 누르면 빠져요."
	_pick.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_pick.toggled.connect(func(on: bool) -> void:
		picking = on
		refresh())
	filter_row.add_child(_pick)
	box.add_child(filter_row)

	# 창고 칸 (단계가 오르면 칸이 늘어나므로 스크롤)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, VISIBLE_ROWS * (ItemSlot.SLOT_SIZE + 6) - 6)
	_store_grid = _grid()
	_scroll.add_child(_store_grid)
	box.add_child(_scroll)

	# 증축 / 모두 넣기
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	_upgrade = Button.new()
	_upgrade.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_upgrade.pressed.connect(_on_upgrade)
	actions.add_child(_upgrade)
	_upgrade_cost = _small_label("", Color("9a7457"))
	_upgrade_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_upgrade_cost)
	_deposit_all = Button.new()
	_deposit_all.text = "가방 물건 모두 넣기"
	_deposit_all.tooltip_text = "핫바(맨 윗줄)를 뺀 가방 칸 중 받을 수 있는 물건을 모두 넣어요."
	_deposit_all.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_deposit_all.pressed.connect(_on_deposit_all)
	actions.add_child(_deposit_all)
	box.add_child(actions)

	box.add_child(_small_label("가방 — 칸 클릭: 한 묶음 옮기기 · 우클릭: 1개만", Color("c98a2e")))
	var bag_grid := _grid()
	box.add_child(bag_grid)
	for i in GameState.inventory.size():
		var slot := ItemSlot.new()
		slot.index = i
		slot.show_number = i < Inventory.HOTBAR_SIZE
		slot.clicked.connect(_on_bag_clicked)
		slot.right_clicked.connect(_on_bag_right_clicked)
		bag_grid.add_child(slot)
		_bag_slots.append(slot)

	Events.inventory_changed.connect(refresh)
	Events.warehouse_changed.connect(refresh)
	Events.money_changed.connect(func(_m: int) -> void: refresh())


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	return grid


func _small_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", color)
	return label


func open(target: Warehouse) -> void:
	warehouse = target
	picking = false
	_pick.set_pressed_no_signal(false)
	_scroll.scroll_vertical = 0
	refresh()
	show()
	reset_size()


func refresh() -> void:
	if not is_node_ready() or warehouse == null or not is_instance_valid(warehouse):
		return
	var wh := warehouse
	_title.text = "창고  Lv.%d · %d/%d칸 사용" % [wh.level + 1, wh.used_slots(), wh.slot_count()]

	# 필터
	for i in _filter.item_count:
		if _filter.get_item_metadata(i) == wh.filter_mode:
			_filter.select(i)
	var items_mode := wh.filter_mode == "items"
	_pick.visible = items_mode
	if not items_mode and picking:
		picking = false
		_pick.set_pressed_no_signal(false)
	_pick.disabled = wh.filter_items.size() >= wh.max_filter_items() and not picking
	_clear(_chips)
	if items_mode:
		for id in wh.filter_items:
			_chips.add_child(_chip(ItemDB.get_item(id)))
		if wh.filter_items.is_empty():
			_chips.add_child(_small_label("(아직 없음 · 아무것도 안 받아요)", Color("9a7457")))

	# 창고 칸 (단계가 바뀌면 칸 수를 맞춘다)
	while _store_slots.size() < wh.storage.size():
		var slot := ItemSlot.new()
		slot.index = _store_slots.size()
		slot.clicked.connect(_on_store_clicked)
		slot.right_clicked.connect(_on_store_right_clicked)
		_store_grid.add_child(slot)
		_store_slots.append(slot)
	while _store_slots.size() > wh.storage.size():
		var slot: ItemSlot = _store_slots.pop_back()
		_store_grid.remove_child(slot)
		slot.queue_free()
	for i in _store_slots.size():
		_store_slots[i].set_slot(wh.storage.get_slot(i))

	# 가방 칸: 받을 수 없는 물건은 흐리게 (고르는 중이면 모두 또렷하게)
	for i in _bag_slots.size():
		_bag_slots[i].set_slot(GameState.inventory.get_slot(i))
		var item := GameState.inventory.item_at(i)
		_bag_slots[i].modulate.a = 1.0 if item == null or picking or wh.accepts(item) else 0.35

	# 증축
	var next := wh.next_upgrade()
	if next.is_empty():
		_upgrade.text = "최대 크기"
		_upgrade.disabled = true
		_upgrade_cost.text = "더 보관하려면 창고를 하나 더 지어요."
	else:
		_upgrade.text = "증축 → %d칸" % next.slots
		_upgrade.disabled = wh.upgrade_problem(GameState.inventory) != ""
		_upgrade_cost.text = PlaceableDef.cost_text_of(next.price, next.materials)
	reset_size()


## 지정 아이템 필터의 아이콘 칸 (누르면 뺀다, 올리면 아이템 툴팁)
func _chip(item: ItemDef) -> ItemSlot:
	var chip := ItemSlot.new()
	chip.set_slot({"id": item.id, "count": 1, "quality": Quality.NONE})
	chip.clicked.connect(func(_i: int) -> void: warehouse.remove_filter_item(item.id))
	return chip


func _on_filter_selected(i: int) -> void:
	warehouse.set_filter_mode(str(_filter.get_item_metadata(i)))


func _on_bag_clicked(index: int) -> void:
	var item := GameState.inventory.item_at(index)
	if item == null:
		return
	if picking:
		if not warehouse.add_filter_item(item.id) and item.id not in warehouse.filter_items:
			Events.toast.emit("지정 아이템은 %d개까지예요." % warehouse.max_filter_items())
		return
	_deposit(index, -1)


func _on_bag_right_clicked(index: int) -> void:
	if not picking:
		_deposit(index, 1)


func _deposit(index: int, count: int) -> void:
	var item := GameState.inventory.item_at(index)
	if item == null:
		return
	if not warehouse.accepts(item):
		Events.toast.emit("이 창고는 %s을(를) 받지 않아요. (받을 물건: %s)" % [item.name, warehouse.filter_text()])
	elif warehouse.deposit_slot(GameState.inventory, index, count) == 0:
		Events.toast.emit("창고에 자리가 없어요.")


func _on_store_clicked(index: int) -> void:
	_withdraw(index, -1)


func _on_store_right_clicked(index: int) -> void:
	_withdraw(index, 1)


func _withdraw(index: int, count: int) -> void:
	if warehouse.storage.get_slot(index) != null and warehouse.withdraw_slot(GameState.inventory, index, count) == 0:
		Events.toast.emit("가방에 자리가 없어서 꺼낼 수 없어요.")


func _on_deposit_all() -> void:
	if warehouse.deposit_all(GameState.inventory) == 0:
		Events.toast.emit("넣을 수 있는 물건이 없거나 창고에 자리가 없어요.")


func _on_upgrade() -> void:
	var problem := warehouse.upgrade_problem(GameState.inventory)
	if problem != "" or not warehouse.upgrade(GameState.inventory):
		Events.toast.emit(problem)
		return
	Events.toast.emit("창고 증축! 이제 %d칸이에요." % warehouse.slot_count())


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
