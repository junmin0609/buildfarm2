class_name ShopPanel
extends PanelContainer
## 상점 창. 왼쪽에서 씨앗을 사고, 오른쪽에서 가방 속 작물을 판다.
## 여기서 파는 건 "광장 즉시 판매": 바로 돈을 받는 대신 기준가의 일부만 받는다 (data/economy.json 의 plaza).
## 품질이 다른 작물은 줄을 나눠 보여 주고, 가격에 품질 배율이 붙는다.

const CHANNEL := Pricing.PLAZA

signal close_requested

var _money_label: Label
var _title: Label
var _mode := "all"
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(1040, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var title := Label.new()
	_title = title
	title.text = "잡화점"
	title.add_theme_font_size_override("font_size", Art.FONT_SIZE)
	title.add_theme_font_override("font", Art.pixel_font(true))
	header.add_child(title)
	_money_label = Label.new()
	_money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_money_label)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	_buy_list = _column(columns, "씨앗 사기")
	_sell_list = _column(columns, "작물 팔기")
	var note := Label.new()
	note.text = "바로 팔면 기준가의 %d%%만 받아요." % roundi(Pricing.channel_multiplier(CHANNEL) * 100)
	note.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	note.add_theme_color_override("font_color", Color("9a7457"))
	_sell_list.get_parent().add_child(note)
	_sell_list.get_parent().move_child(note, 1)

	Events.money_changed.connect(func(_m: int) -> void: refresh())
	Events.inventory_changed.connect(refresh)


func _column(parent: Container, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", Art.FONT_SIZE)
	label.add_theme_color_override("font_color", Color("c98a2e"))
	col.add_child(label)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	col.add_child(list)
	parent.add_child(col)
	return list


## mode: "buy" 씨앗만, "sell" 작물 팔기만, "all" 둘 다
func open(mode := "all") -> void:
	_mode = mode
	_title.text = {"buy": "씨앗 상점", "sell": "작물 판매처"}.get(mode, "잡화점")
	_buy_list.get_parent().visible = mode != "sell"
	_sell_list.get_parent().visible = mode != "buy"
	custom_minimum_size = Vector2(1040 if mode == "all" else 680, 0)
	refresh()
	show()
	reset_size()


func refresh() -> void:
	if not is_node_ready():
		return
	_money_label.text = "가진 돈  %d G" % GameState.money
	_clear(_buy_list)
	for item in ItemDB.shop_items():
		var row := _item_row(item, "%d G" % item.buy_price)
		for qty: int in [1, 5]:
			var btn := Button.new()
			btn.text = "%d개" % qty
			btn.disabled = GameState.money < item.buy_price * qty
			btn.pressed.connect(_buy.bind(item.id, qty))
			row.add_child(btn)
		_buy_list.add_child(row)

	_clear(_sell_list)
	var any := false
	for stack in _sellable_stacks():
		var item := ItemDB.get_item(stack.id)
		var quality: String = stack.quality
		var have := GameState.inventory.count_of(stack.id, quality)
		var row := _item_row(item, "%d G  ·  %d개" % [Pricing.unit_price(item, quality, CHANNEL), have], quality)
		var one := Button.new()
		one.text = "1개"
		one.pressed.connect(_sell.bind(stack.id, 1, quality))
		row.add_child(one)
		var all := Button.new()
		all.text = "모두"
		all.pressed.connect(_sell.bind(stack.id, have, quality))
		row.add_child(all)
		_sell_list.add_child(row)
		any = true
	if not any:
		var empty := Label.new()
		empty.text = "팔 수 있는 작물이 없어요.\n작물을 키워 수확해 오세요."
		empty.add_theme_color_override("font_color", Color("9a7457"))
		_sell_list.add_child(empty)


func _item_row(item: ItemDef, price_text: String, quality := Quality.NONE) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := ItemSlot.new()
	icon.custom_minimum_size = Vector2(60, 60)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_slot({"id": item.id, "count": 1, "quality": quality})
	row.add_child(icon)
	var name_label := Label.new()
	name_label.text = item.name if quality == Quality.NONE else "%s (%s)" % [item.name, Quality.name_of(quality)]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.custom_minimum_size = Vector2(100, 0)
	row.add_child(name_label)
	var price := Label.new()
	price.text = price_text
	price.add_theme_color_override("font_color", Color("c98a2e"))
	row.add_child(price)
	return row


## 팔 수 있는 (id, quality) 묶음. 가방에 처음 나온 순서, 같은 작물끼리는 품질 낮은 것부터
func _sellable_stacks() -> Array[Dictionary]:
	var groups := {}  # id -> Array[Dictionary]
	var ids: Array[String] = []
	for stack in GameState.inventory.stacks():
		if not ItemDB.get_item(stack.id).is_sellable():
			continue
		if not groups.has(stack.id):
			groups[stack.id] = []
			ids.append(stack.id)
		groups[stack.id].append(stack)
	var order := Quality.ids()
	var result: Array[Dictionary] = []
	for item_id in ids:
		var group: Array = groups[item_id]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order.find(a.quality) < order.find(b.quality))
		for stack: Dictionary in group:
			result.append(stack)
	return result


func _buy(item_id: String, qty: int) -> void:
	var item := ItemDB.get_item(item_id)
	if not GameState.inventory.can_add(item_id, qty):
		Events.toast.emit("가방에 자리가 없어요.")
		return
	if not GameState.try_spend(item.buy_price * qty):
		Events.toast.emit("돈이 부족해요.")
		return
	GameState.inventory.add(item_id, qty)
	Events.toast.emit("%s %d개를 샀어요." % [item.name, qty])


func _sell(item_id: String, qty: int, quality := Quality.NONE) -> void:
	var item := ItemDB.get_item(item_id)
	if qty <= 0 or not GameState.inventory.remove(item_id, qty, quality):
		return
	var earned := Pricing.unit_price(item, quality, CHANNEL) * qty
	GameState.add_money(earned)
	Events.toast.emit("%s %d개를 팔아 %d G를 벌었어요." % [item.name, qty, earned])


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
