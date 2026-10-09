class_name SkyStationPanel
extends PanelContainer
## 오래된 비행선 정류장 복구 창 (BUILD_FARM_PLAN §89). 필요한 돈·재료와 가진 양을 보여 주고,
## 다 모이면 [복구하기] → 하늘시장이 열리고 정류장에서 비행선을 탈 수 있다 (SkyMarket.restore).
## 상점처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

var _rows: VBoxContainer
var _restore: Button
var _status: Label


func _ready() -> void:
	custom_minimum_size = Vector2(760, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "오래된 비행선 정류장"
	title.add_theme_font_override("font", Art.pixel_font(true))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)
	var hint := Label.new()
	hint.text = "정류장을 고치면 비행선을 타고 하늘섬 시장에 갈 수 있어요.\n하늘시장은 날마다 값이 바뀌어요. 비쌀 때 팔면 이득!"
	hint.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(hint)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	box.add_child(_rows)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 12)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_status.add_theme_color_override("font_color", Color("c0503a"))
	actions.add_child(_status)
	_restore = Button.new()
	_restore.text = "복구하기"
	_restore.pressed.connect(restore)
	actions.add_child(_restore)
	box.add_child(actions)
	Events.inventory_changed.connect(refresh)
	Events.money_changed.connect(func(_m: int) -> void: refresh())


func open() -> void:
	show()
	refresh()


func refresh() -> void:
	if not is_node_ready() or not visible:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var cost := SkyMarket.station_cost()
	_rows.add_child(_line(null, "돈", GameState.money, int(cost.price)))
	for id: String in cost.materials:
		_rows.add_child(_line(ItemDB.get_item(id), ItemDB.get_item(id).name, GameState.inventory.count_of(id), int(cost.materials[id])))
	var problem := SkyMarket.restore_problem(GameState.inventory)
	_restore.disabled = problem != ""
	_status.text = problem
	reset_size()


func _line(item: ItemDef, label: String, have: int, need: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if item:
		var icon := ItemSlot.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.set_slot({"id": item.id, "count": 1, "quality": Quality.NONE})
		row.add_child(icon)
	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var amount := Label.new()
	amount.text = "%s / %s" % [SalesSummaryPanel.format_gold(have), SalesSummaryPanel.format_gold(need)] + (" G" if item == null else "")
	amount.add_theme_color_override("font_color", Color("4f8a3f") if have >= need else Color("c0503a"))
	row.add_child(amount)
	return row


func restore() -> void:
	var problem := SkyMarket.restore_problem(GameState.inventory)
	if problem != "" or not SkyMarket.restore(GameState.inventory):
		Events.toast.emit(problem)
		return
	Events.sky_station_restored.emit()
	Events.toast.emit("비행선 정류장을 고쳤어요! 이제 하늘섬 시장에 갈 수 있어요.")
	close_requested.emit()
