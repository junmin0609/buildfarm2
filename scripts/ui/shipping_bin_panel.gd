class_name ShippingBinPanel
extends PanelContainer
## 출하함 창. 왼쪽 가방의 판매 가능한 물건을 넣고, 오른쪽 출하함에서 다시 꺼낸다.
## 가방 창처럼 시간은 계속 흐르고, 열려 있는 동안 플레이어 조작만 막는다 (HUD 가 처리).

signal close_requested

var bin: ShippingBin
var _bag_list: VBoxContainer
var _bin_list: VBoxContainer
var _pending: Label


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "출하함"
	title.add_theme_font_override("font", Art.pixel_font(true))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)

	var hint := Label.new()
	hint.text = "넣어 둔 물건은 하루가 끝날 때 기준가 그대로(%d%%) 팔려요. 그 전까지는 다시 꺼낼 수 있어요." % roundi(Pricing.channel_multiplier(ShippingBin.CHANNEL) * 100)
	hint.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(hint)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	_bag_list = _column(columns, "가방 → 넣기")
	_bin_list = _column(columns, "출하함 → 꺼내기")

	_pending = Label.new()
	_pending.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pending.add_theme_color_override("font_color", Color("c98a2e"))
	box.add_child(_pending)

	Events.inventory_changed.connect(refresh)
	Events.shipping_bin_changed.connect(refresh)


func _column(parent: Container, heading: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = heading
	label.add_theme_color_override("font_color", Color("c98a2e"))
	col.add_child(label)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	col.add_child(list)
	parent.add_child(col)
	return list


func open(target: ShippingBin) -> void:
	bin = target
	refresh()
	show()
	reset_size()


func refresh() -> void:
	if not is_node_ready() or bin == null or not is_instance_valid(bin):
		return
	_clear(_bag_list)
	for stack in GameState.inventory.stacks():
		var item := ItemDB.get_item(stack.id)
		if not ShippingBin.accepts(item):
			continue
		var have := GameState.inventory.count_of(stack.id, stack.quality)
		_bag_list.add_child(_row(item, stack.quality, have, _put))
	if _bag_list.get_child_count() == 0:
		_bag_list.add_child(_empty("넣을 수 있는 물건이 없어요."))
	_clear(_bin_list)
	for entry in bin.contents:
		_bin_list.add_child(_row(ItemDB.get_item(entry.id), entry.quality, entry.count, _take))
	if bin.is_empty():
		_bin_list.add_child(_empty("비어 있어요."))
	_pending.text = "오늘 밤 받을 돈  %s G" % SalesSummaryPanel.format_gold(bin.pending_value())
	reset_size()


## 두 열이 화면에 들어가도록 상점 줄보다 작은 글씨를 쓴다
func _row(item: ItemDef, quality: String, count: int, action: Callable) -> HBoxContainer:
	var price := Pricing.unit_price(item, quality, ShippingBin.CHANNEL)
	var row := ShopPanel.item_row(item, "%d G · %d개" % [price, count], quality)
	for child in row.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
			child.custom_minimum_size.x = 0
	for entry: Array in [["1개", 1], ["모두", count]]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
		btn.pressed.connect(action.bind(item.id, quality, entry[1]))
		row.add_child(btn)
	return row


func _put(item_id: String, quality: String, count: int) -> void:
	bin.deposit(GameState.inventory, item_id, quality, count)


func _take(item_id: String, quality: String, count: int) -> void:
	if bin.withdraw(GameState.inventory, item_id, quality, count) == 0:
		Events.toast.emit("가방에 자리가 없어서 꺼낼 수 없어요.")


func _empty(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", Color("9a7457"))
	return label


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
