class_name BlacksmithPanel
extends PanelContainer
## 대장간 창. 가방 속 도구마다 다음 단계·효과·비용을 보여 주고, [강화]를 누르면 바로 바뀐다.
## 상점처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

var _list: VBoxContainer
var _money: Label


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var title := Label.new()
	title.text = "대장간"
	title.add_theme_font_override("font", Art.pixel_font(true))
	header.add_child(title)
	_money = Label.new()
	_money.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_money)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)
	var hint := Label.new()
	hint.text = "돈과 재료를 내면 도구를 바로 강화해 드려요."
	hint.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(hint)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	Events.inventory_changed.connect(refresh)
	Events.money_changed.connect(func(_m: int) -> void: refresh())


func open() -> void:
	refresh()
	show()
	reset_size()


func refresh() -> void:
	if not is_node_ready():
		return
	_money.text = "가진 돈  %s G" % SalesSummaryPanel.format_gold(GameState.money)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var inv := GameState.inventory
	var slots := ToolUpgrade.tool_slots(inv)
	for index in slots:
		_list.add_child(_row(inv, index))
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "가방에 강화할 도구가 없어요."
		empty.add_theme_color_override("font_color", Color("9a7457"))
		_list.add_child(empty)
	reset_size()


func _row(inv: Inventory, index: int) -> HBoxContainer:
	var item := inv.item_at(index)
	var next := ToolUpgrade.next_of(item)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(_icon(item))
	if next:
		var arrow := Label.new()
		arrow.text = "→"
		row.add_child(arrow)
		row.add_child(_icon(next))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = "%s → %s" % [item.name, next.name] if next else "%s (최고 단계)" % item.name
	info.add_child(name_label)
	var detail := Label.new()
	detail.text = "%s\n%s" % [next.description, _cost_text(inv, item)] if next else "더 강화할 수 없어요."
	detail.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	detail.add_theme_color_override("font_color", Color("9a7457"))
	info.add_child(detail)
	row.add_child(info)
	if next:
		var btn := Button.new()
		btn.text = "강화"
		var check := ToolUpgrade.check(inv, index)
		btn.disabled = not check.ok
		btn.tooltip_text = check.reason
		btn.pressed.connect(_upgrade.bind(index))
		row.add_child(btn)
	return row


## "400 G · 돌 3/15 · 나무 10/10"
func _cost_text(inv: Inventory, item: ItemDef) -> String:
	var parts: Array[String] = ["%s G" % SalesSummaryPanel.format_gold(ToolUpgrade.price_of(item))]
	var mats := ToolUpgrade.materials_of(item)
	for mat_id: String in mats:
		var mat := ItemDB.get_item(mat_id)
		parts.append("%s %d/%d" % [mat.name if mat else mat_id, inv.count_of(mat_id), int(mats[mat_id])])
	return " · ".join(parts)


func _icon(item: ItemDef) -> ItemSlot:
	var icon := ItemSlot.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_slot({"id": item.id, "count": 1, "quality": ""})
	return icon


func _upgrade(index: int) -> void:
	var inv := GameState.inventory
	var before := inv.item_at(index)
	var check := ToolUpgrade.check(inv, index)
	if not check.ok:
		Events.toast.emit(check.reason)
		return
	if ToolUpgrade.apply(inv, index):
		Events.toast.emit("%s이(가) %s(으)로 강화됐어요!" % [before.name, inv.item_at(index).name])
