class_name RouterPanel
extends PanelContainer
## 필터 분배기 창 (§62). 왼쪽(하늘색)·오른쪽(분홍) 출구마다 보낼 물건을 고른다. 안 맞는 물건은 앞으로.
##   종류(작물만 / 가공품만 ...) 또는 "지정 아이템": [가방에서 고르기] 를 누른 뒤 가방 칸을 클릭해 추가, 아이콘을 누르면 뺀다.
## 상점처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

const SIDES := {"left": ["왼쪽 출구", Color("4f9fc8")], "right": ["오른쪽 출구", Color("d0607e")]}

var router: Router
## 고르는 중인 쪽 ("" 이면 고르지 않음)
var picking := ""

var _options := {}   # side -> OptionButton
var _chips := {}     # side -> HBoxContainer
var _picks := {}     # side -> Button
var _bag_slots: Array[ItemSlot] = []


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "필터 분배기"
	title.add_theme_font_override("font", Art.pixel_font(true))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)
	box.add_child(_small("정한 물건은 그쪽 출구로, 아무 데도 안 맞는 물건은 앞으로 보내요. 정한 쪽이 막히면 기다려요.", Color("9a7457")))

	for side: String in SIDES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var label := _small(SIDES[side][0], SIDES[side][1])
		label.custom_minimum_size = Vector2(120, 0)
		row.add_child(label)
		var opt := OptionButton.new()
		opt.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
		for mode: String in Router.FILTERS:
			opt.add_item(Router.FILTERS[mode])
			opt.set_item_metadata(opt.item_count - 1, mode)
		opt.item_selected.connect(func(i: int) -> void: router.set_filter_mode(side, str(opt.get_item_metadata(i))))
		row.add_child(opt)
		var chips := HBoxContainer.new()
		chips.add_theme_constant_override("separation", 4)
		row.add_child(chips)
		var pick := Button.new()
		pick.toggle_mode = true
		pick.text = "가방에서 고르기"
		pick.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
		pick.toggled.connect(func(on: bool) -> void:
			picking = side if on else ("" if picking == side else picking)
			refresh())
		row.add_child(pick)
		box.add_child(row)
		_options[side] = opt
		_chips[side] = chips
		_picks[side] = pick
	box.add_child(_small("앞 출구: 나머지 모든 물건", Color("9a7457")))

	box.add_child(_small("가방 — 고르기를 누른 뒤 칸 클릭", Color("c98a2e")))
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for i in GameState.inventory.size():
		var slot := ItemSlot.new()
		slot.index = i
		slot.clicked.connect(_on_bag_clicked)
		grid.add_child(slot)
		_bag_slots.append(slot)
	Events.router_changed.connect(refresh)
	Events.inventory_changed.connect(refresh)


func _small(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", color)
	return label


func open(target: Router) -> void:
	router = target
	picking = ""
	show()
	refresh()


func refresh() -> void:
	if not is_node_ready() or router == null or not is_instance_valid(router) or not visible:
		return
	for side: String in SIDES:
		var f: Dictionary = router.filters[side]
		var opt: OptionButton = _options[side]
		for i in opt.item_count:
			if opt.get_item_metadata(i) == f.mode:
				opt.select(i)
		var items_mode: bool = f.mode == "items"
		if not items_mode and picking == side:
			picking = ""
		var pick: Button = _picks[side]
		pick.visible = items_mode
		pick.set_pressed_no_signal(picking == side)
		var chips: HBoxContainer = _chips[side]
		for child in chips.get_children():
			chips.remove_child(child)
			child.queue_free()
		if items_mode:
			for id: String in f.items:
				var chip := ItemSlot.new()
				chip.set_slot({"id": id, "count": 1, "quality": Quality.NONE})
				chip.clicked.connect(func(_i: int) -> void: router.remove_filter_item(side, id))
				chips.add_child(chip)
			if f.items.is_empty():
				chips.add_child(_small("(아직 없음)", Color("9a7457")))
	for i in _bag_slots.size():
		_bag_slots[i].set_slot(GameState.inventory.get_slot(i))
		_bag_slots[i].modulate.a = 1.0 if picking != "" else 0.6
	reset_size()


func _on_bag_clicked(index: int) -> void:
	var item := GameState.inventory.item_at(index)
	if item == null or picking == "":
		return
	if not router.add_filter_item(picking, item.id) and item.id not in router.filters[picking].items:
		Events.toast.emit("지정 아이템은 %d개까지예요." % Router.MAX_FILTER_ITEMS)
