class_name CompostBinPanel
extends PanelContainer
## 퇴비통 창. 왼쪽: 가방의 퇴비 재료 넣기 / 오른쪽: 넣어 둔(아직 익히기 전) 재료 꺼내기.
## 아래: 익히는 상태와 다 된 결과물 꺼내기. 출하함처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

var bin: CompostBin
var _bag_list: VBoxContainer
var _wait_list: VBoxContainer
var _status: Label
var _output_row: HBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "퇴비통"
	title.add_theme_font_override("font", Art.pixel_font(true))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)

	var hint := Label.new()
	hint.name = "Hint"
	hint.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(hint)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	_bag_list = _column(columns, "가방 → 넣기")
	_wait_list = _column(columns, "넣어 둔 재료 → 꺼내기")

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("6b8a3a"))
	box.add_child(_status)

	_output_row = HBoxContainer.new()
	_output_row.add_theme_constant_override("separation", 12)
	box.add_child(_output_row)

	Events.inventory_changed.connect(refresh)
	Events.compost_bin_changed.connect(refresh)


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


func open(target: CompostBin) -> void:
	bin = target
	refresh()
	show()
	reset_size()


func refresh() -> void:
	if not is_node_ready() or bin == null or not is_instance_valid(bin):
		return
	var out_item := bin.output_item()
	var out_name := out_item.name if out_item else "?"
	(get_child(0).get_node("Hint") as Label).text = "재료 %d점이 모이면 %d일 동안 익어서 %s %d개가 돼요. 익기 전 재료는 다시 꺼낼 수 있어요." \
			% [bin.batch_points_needed(), bin.days_needed(), out_name, bin.output_per_batch()]
	_clear(_bag_list)
	for stack in GameState.inventory.stacks():
		var item := ItemDB.get_item(stack.id)
		if not bin.accepts(item):
			continue
		var have := GameState.inventory.count_of(stack.id, stack.quality)
		_bag_list.add_child(_row(item, stack.quality, have, _put))
	if _bag_list.get_child_count() == 0:
		_bag_list.add_child(_empty("넣을 재료가 없어요. (식물 섬유·값싼 작물)"))
	_clear(_wait_list)
	for st in bin.waiting:
		_wait_list.add_child(_row(ItemDB.get_item(st.id), st.quality, st.count, _take))
	if bin.waiting.is_empty():
		_wait_list.add_child(_empty("비어 있어요."))
	_status.text = status_text(bin)
	_clear(_output_row)
	if out_item:
		var row := ShopPanel.item_row(out_item, "다 된 %s %d개" % [out_item.name, bin.output])
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_output_row.add_child(row)
		var btn := Button.new()
		btn.text = "꺼내기"
		btn.disabled = bin.output <= 0
		btn.pressed.connect(_take_output)
		_output_row.add_child(btn)
	reset_size()


## "익히는 중 2/3일 · 대기 재료 4/10점" 같은 상태 글
static func status_text(target: CompostBin) -> String:
	var parts: Array[String] = []
	if target.is_done():
		parts.append("다 익었어요! 결과물 칸이 가득 차서 기다리는 중 (꺼내면 바로 채워져요)")
	elif target.is_working():
		parts.append("익히는 중 %d/%d일" % [target.batch_days, target.days_needed()])
	else:
		parts.append("쉬는 중")
	parts.append("넣어 둔 재료 %d/%d점 (최대 %d점)" % [target.waiting_points(), target.batch_points_needed(), target.max_waiting_points()])
	return " · ".join(parts)


func _row(item: ItemDef, quality: String, count: int, action: Callable) -> HBoxContainer:
	var row := ShopPanel.item_row(item, "%d점 · %d개" % [bin.points_of(item.id), count], quality)
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
	if bin.deposit(GameState.inventory, item_id, quality, count) == 0:
		Events.toast.emit("퇴비통이 가득 찼어요. (재료 최대 %d점)" % bin.max_waiting_points())


func _take(item_id: String, quality: String, count: int) -> void:
	if bin.withdraw(GameState.inventory, item_id, quality, count) == 0:
		Events.toast.emit("가방에 자리가 없어서 꺼낼 수 없어요.")


func _take_output() -> void:
	var n := bin.take_output(GameState.inventory)
	if n == 0:
		Events.toast.emit("가방에 자리가 없어서 꺼낼 수 없어요.")
	elif bin.output > 0:
		Events.toast.emit("가방에 들어가는 %d개만 꺼냈어요. 나머지는 퇴비통에 있어요." % n)


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
