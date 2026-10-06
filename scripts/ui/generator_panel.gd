class_name GeneratorPanel
extends PanelContainer
## 발전기 창. 왼쪽: 가방의 연료 넣기 / 오른쪽: 넣어 둔(아직 안 탄) 연료 꺼내기.
## 아래: 타는 상태, 이 발전기의 전기 통, 지역 전기 통 합계. 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

var generator: Generator
var _hint: Label
var _bag_list: VBoxContainer
var _fuel_list: VBoxContainer
var _status: Label
var _bar: ProgressBar
var _energy: Label


func _ready() -> void:
	custom_minimum_size = Vector2(900, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "발전기"
	title.add_theme_font_override("font", Art.pixel_font(true))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "닫기 (Esc)"
	close.pressed.connect(close_requested.emit)
	header.add_child(close)
	box.add_child(header)

	_hint = _small("", Color("9a7457"))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_hint)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	_bag_list = _column(columns, "가방 → 연료 넣기")
	_fuel_list = _column(columns, "넣어 둔 연료 → 꺼내기")

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("6b8a3a"))
	box.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.show_percentage = false
	box.add_child(_bar)
	_energy = _small("", Color("5b3a29"))
	box.add_child(_energy)

	Events.inventory_changed.connect(refresh)
	Events.generator_changed.connect(refresh)


func _small(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", color)
	return label


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


func open(target: Generator) -> void:
	generator = target
	refresh()
	show()
	reset_size()


func refresh() -> void:
	if not is_node_ready() or generator == null or not is_instance_valid(generator):
		return
	var g := generator
	var parts: Array[String] = []
	var fuels: Variant = g.config().get("fuels", {})
	if fuels is Dictionary:
		for id: String in fuels:
			parts.append("%s 1개 = %s" % [ItemDB.get_item(id).name, RecipeDB.time_text(g.burn_minutes(id))])
	_hint.text = "연료가 타는 동안 시간당 전기 %d를 만들어 이 발전기의 전기 통(%d)에 채워요. 발전기들이 만든 전기는 지역 전기 통에 모여 전기 기계들이 일할 때 나눠 써요. (%s)" \
			% [roundi(g.output_per_hour()), roundi(g.storage()), ", ".join(parts)]
	_clear(_bag_list)
	for stack in GameState.inventory.stacks():
		var item := ItemDB.get_item(stack.id)
		if g.accepts(item):
			_bag_list.add_child(_row(item, GameState.inventory.count_of(item.id), _put))
	if _bag_list.get_child_count() == 0:
		_bag_list.add_child(_small("넣을 연료가 없어요. (식물 섬유·나무)", Color("9a7457")))
	_clear(_fuel_list)
	for st in g.fuel:
		_fuel_list.add_child(_row(ItemDB.get_item(st.id), int(st.count), _take))
	if g.fuel.is_empty():
		_fuel_list.add_child(_small("비어 있어요. (최대 %d개)" % g.max_fuel(), Color("9a7457")))
	_status.text = g.status_text()
	_bar.max_value = g.storage()
	_bar.value = g.energy
	var region: Dictionary = g._world_power()
	_energy.text = "이 발전기 전기 %d / %d · 지역 전기 통 %d / %d · 남은 연료로 약 %s 더 발전" \
			% [floori(g.energy), roundi(g.storage()), floori(region.stored), roundi(region.capacity), RecipeDB.time_text(g.fuel_minutes_left())]
	reset_size()


func _row(item: ItemDef, count: int, action: Callable) -> HBoxContainer:
	var row := ShopPanel.item_row(item, "%s · %d개" % [RecipeDB.time_text(generator.burn_minutes(item.id)), count])
	for child in row.get_children():
		if child is Label:
			child.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
			child.custom_minimum_size.x = 0
	for entry: Array in [["1개", 1], ["모두", count]]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
		btn.pressed.connect(action.bind(item.id, entry[1]))
		row.add_child(btn)
	return row


func _put(item_id: String, count: int) -> void:
	if generator.deposit(GameState.inventory, item_id, count) == 0:
		Events.toast.emit("연료 칸이 가득 찼어요. (최대 %d개)" % generator.max_fuel())


func _take(item_id: String, count: int) -> void:
	if generator.withdraw(GameState.inventory, item_id, count) == 0:
		Events.toast.emit("가방에 자리가 없어서 꺼낼 수 없어요.")


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
