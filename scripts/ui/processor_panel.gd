class_name ProcessorPanel
extends PanelContainer
## 가공기 창 (§70~§73). 왼쪽: 레시피 목록 (모르는 레시피는 잠김) / 오른쪽: 고른 레시피 · 횟수 · 시작 / 진행 상태 / 결과물.
## 수동 가공기는 정한 횟수만 만들고 멈춘다. 전기 가공기는 레시피를 정하고 켜 두면 맞닿은 창고와 알아서 주고받는다
## (횟수·시작 버튼 대신 켜기/끄기와 전력·창고 정보가 보인다). 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

var processor: Processor
## 오른쪽에 보여 줄(고른) 레시피 id
var selected := ""
## 시작할 횟수
var runs := 1

var _title: Label
var _list: VBoxContainer
var _detail: VBoxContainer
var _count: Label
var _max_label: Label
var _quality: OptionButton
var _start: Button
var _status: Label
var _bar: ProgressBar
var _cancel: Button
var _output_slots: HBoxContainer
var _take: Button
var _hint: Label
var _count_row: HBoxContainer
var _toggle: Button
var _auto_info: Label
var _belt: Button


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
	_hint = _small("", Color("9a7457"))
	# 긴 설명이 창을 화면 밖까지 넓히지 않게 줄바꿈 (왼쪽 470 + 사이 20 + 오른쪽 380)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(870, 0)
	box.add_child(_hint)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	box.add_child(columns)

	# 레시피 목록
	var left := VBoxContainer.new()
	left.add_child(_small("레시피", Color("c98a2e")))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(470, 330)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_list)
	left.add_child(scroll)
	columns.add_child(left)

	# 고른 레시피
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 4)
	right.add_child(_detail)

	var count_row := HBoxContainer.new()
	_count_row = count_row
	count_row.add_theme_constant_override("separation", 6)
	count_row.add_child(_small("횟수", Color("c98a2e")))
	count_row.add_child(_button("-", func() -> void: _set_runs(runs - 1)))
	_count = Label.new()
	_count.custom_minimum_size = Vector2(44, 0)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_row.add_child(_count)
	count_row.add_child(_button("+", func() -> void: _set_runs(runs + 1)))
	count_row.add_child(_button("최대", func() -> void: _set_runs(_possible())))
	_max_label = _small("", Color("9a7457"))
	count_row.add_child(_max_label)
	right.add_child(count_row)

	_quality = OptionButton.new()
	_quality.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_quality.add_item("낮은 품질 재료부터 쓰기")
	_quality.add_item("높은 품질 재료부터 쓰기")
	_quality.tooltip_text = "결과물 품질은 그 회차에 쓴 재료 품질의 평균이에요."
	_quality.item_selected.connect(func(i: int) -> void:
		if processor and processor.is_automatic():
			processor.set_high_first(i == 1))
	right.add_child(_quality)

	_start = _button("가공 시작", _on_start)
	right.add_child(_start)
	_toggle = _button("자동 가공 켜기", _on_toggle)
	right.add_child(_toggle)
	_belt = _button("", func() -> void:
		processor.belt_out = not processor.belt_out
		Events.processor_changed.emit())
	right.add_child(_belt)
	_auto_info = _small("", Color("9a7457"))
	_auto_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_auto_info)

	right.add_child(HSeparator.new())
	_status = _small("", Color("6b8a3a"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.show_percentage = false
	right.add_child(_bar)
	_cancel = _button("취소 (남은 재료 돌려받기)", _on_cancel)
	right.add_child(_cancel)
	columns.add_child(right)

	# 결과물
	var out_row := HBoxContainer.new()
	out_row.add_theme_constant_override("separation", 8)
	out_row.add_child(_small("결과물", Color("c98a2e")))
	_output_slots = HBoxContainer.new()
	_output_slots.add_theme_constant_override("separation", 4)
	_output_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_row.add_child(_output_slots)
	_take = _button("꺼내기", _on_take)
	out_row.add_child(_take)
	box.add_child(out_row)

	Events.inventory_changed.connect(refresh)
	Events.processor_changed.connect(refresh)
	Events.power_changed.connect(refresh)
	Events.warehouse_changed.connect(refresh)


func _small(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	btn.pressed.connect(action)
	return btn


func open(target: Processor) -> void:
	processor = target
	selected = target.recipe_id if target.recipe_id != "" else _first_known()
	runs = 1
	refresh()
	show()
	reset_size()


func _first_known() -> String:
	for r in RecipeDB.all():
		if processor.recipe_problem(r.id) == "":
			return r.id
	return ""


func refresh() -> void:
	if not is_node_ready() or processor == null or not is_instance_valid(processor):
		return
	var p := processor
	var auto := p.is_automatic()
	_title.text = "%s · %d급" % [p.def.name, p.tier()]
	_hint.text = "레시피를 정하고 켜 두면 맞닿은 창고나 입구 컨베이어로 들어온 재료로 만들고, 결과물은 맞닿은 창고나 출구 컨베이어로 보내요. 만드는 동안에만 전기를 시간당 %d 써요." % p.power_use() \
			if auto else "레시피와 횟수를 정해 [가공 시작] → 정한 횟수만 만들고 멈춰요. 게임 시계가 흐르는 동안 진행돼요."
	_count_row.visible = not auto
	_start.visible = not auto
	_toggle.visible = auto
	_auto_info.visible = auto
	_belt.visible = not auto
	_belt.text = "컨베이어로 내보내기: 켬 (오른쪽 아래 출구)" if p.belt_out else "컨베이어로 내보내기: 끔"
	_fill_list()
	_fill_detail()
	_set_runs(runs, false)
	var busy := p.is_working()
	_start.disabled = busy or _possible() <= 0 or p.recipe_problem(selected) != ""
	_start.text = "가공 중이에요" if busy else "가공 시작 (%d회)" % runs

	# 진행 상태
	var r := p.recipe()
	_cancel.visible = busy and not auto
	_bar.visible = busy
	if auto:
		_quality.select(1 if p.high_first else 0)
		_toggle.text = "자동 가공 끄기" if p.enabled else "자동 가공 켜기"
		_toggle.disabled = not p.enabled and (p.recipe_id == "" or p.recipe_problem(p.recipe_id) != "")
		var power := p.region_power()
		_auto_info.text = "지역 전기 %d / %d · 만드는 동안 시간당 %d 사용 · 맞닿은 창고 %d개" % [floori(power.stored), roundi(power.capacity), p.power_use(), p.warehouses().size()]
		_status.text = p.auto_status()
		if busy:
			_bar.max_value = float(r.minutes)
			_bar.value = minf(p.progress, float(r.minutes))
	elif busy:
		var out_name := ItemDB.get_item(r.output).name
		_bar.max_value = float(r.minutes)
		_bar.value = minf(p.progress, float(r.minutes))
		if p.is_waiting():
			_status.text = "%s %d/%d회째 완성! 결과물 칸이 가득 차서 기다리는 중 (꺼내면 바로 채워져요)" % [out_name, p.runs_done + 1, p.runs_total]
		else:
			_status.text = "%s 만드는 중 %d/%d회째 · 남은 시간 %s" % [out_name, p.runs_done + 1, p.runs_total, RecipeDB.time_text(p.minutes_left())]
	elif p.runs_total > 0:
		_status.text = "정한 %d회를 다 만들었어요. 다시 돌리려면 [가공 시작]" % p.runs_total if p.runs_done >= p.runs_total else "쉬는 중"
	else:
		_status.text = "쉬는 중"

	# 결과물
	for child in _output_slots.get_children():
		_output_slots.remove_child(child)
		child.queue_free()
	for st in p.output:
		var slot := ItemSlot.new()
		slot.set_slot(st)
		_output_slots.add_child(slot)
	if p.output.is_empty():
		_output_slots.add_child(_small("비어 있어요. (최대 %d개)" % p.max_output(), Color("9a7457")))
	_take.disabled = p.output.is_empty()
	reset_size()


func _fill_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for r in RecipeDB.all():
		var item := ItemDB.get_item(r.output)
		var known := RecipeDB.is_known(r.id)
		var label := item.name + (" ×%d" % r.count if r.count > 1 else "")
		var too_high := known and int(r.machine_tier) > processor.tier()
		var info := "%s · %s" % [RecipeDB.inputs_text(r), RecipeDB.time_text(r.minutes / processor.speed())] if known else "잠김 · 광장 레시피 상점에서 배워요"
		if too_high:
			info = "%d급 레시피 · %s가 필요해요" % [int(r.tier), "중급 가공기" if int(r.machine_tier) == 2 else "상급 가공기"]
		var row := ShopPanel.item_row(item, info)
		(row.get_child(1) as Label).text = label
		for child in row.get_children():
			if child is Label:
				child.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
		(row.get_child(2) as Label).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(row.get_child(1) as Label).size_flags_horizontal = Control.SIZE_FILL
		if known and not too_high:
			var current: bool = r.id == (processor.recipe_id if processor.is_automatic() else selected)
			var pick := _button(("정해짐" if processor.is_automatic() else "선택됨") if current else "고르기", _select.bind(r.id))
			pick.disabled = current
			row.add_child(pick)
		else:
			row.modulate.a = 0.45
		_list.add_child(row)


func _fill_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var r := RecipeDB.get_recipe(selected)
	if r.is_empty():
		_detail.add_child(_small("쓸 수 있는 레시피가 없어요.", Color("9a7457")))
		return
	var item := ItemDB.get_item(r.output)
	var head := ShopPanel.item_row(item, "1회에 %d개 · %s" % [r.count, RecipeDB.time_text(r.minutes / processor.speed())])
	var head_info := head.get_child(2) as Label
	head_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_info.custom_minimum_size = Vector2(160, 0)
	head_info.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_detail.add_child(head)
	_detail.add_child(_small("재료 (1회분)", Color("c98a2e")))
	for item_id: String in r.inputs:
		var need := int(r.inputs[item_id])
		var auto := processor.is_automatic()
		var need_q: Variant = RecipeDB.need_quality(r, item_id)
		var have := processor.available_in_warehouses(item_id, need_q) if auto else GameState.inventory.count_of(item_id, need_q)
		var qname := " (%s만)" % Quality.name_of(need_q) if need_q != null else ""
		var line := _small("· %s%s %d개  (%s %d개)" % [ItemDB.get_item(item_id).name, qname, need, "창고·입구" if auto else "가방", have], Color("5b3a29") if have >= need else Color("c0503a"))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(line)


func _possible() -> int:
	return Processor.runs_possible(GameState.inventory, RecipeDB.get_recipe(selected), processor.max_runs()) if is_instance_valid(processor) else 0


func _set_runs(n: int, redraw := true) -> void:
	var most := _possible()
	runs = clampi(n, 1, maxi(1, most))
	_count.text = str(runs)
	_max_label.text = "가능 %d회" % most
	if redraw and is_instance_valid(processor):
		_start.text = "가공 중이에요" if processor.is_working() else "가공 시작 (%d회)" % runs


func _select(id: String) -> void:
	if processor.is_automatic() and not processor.set_recipe(id):
		Events.toast.emit("만들던 재료를 돌려놓을 자리가 없어서 레시피를 바꿀 수 없어요.")
		return
	selected = id
	runs = 1
	refresh()


func _on_start() -> void:
	var problem := processor.recipe_problem(selected)
	if problem == "" and processor.start(GameState.inventory, selected, runs, _quality.selected == 1) == 0:
		problem = "재료가 부족해요."
	if problem != "":
		Events.toast.emit(problem)


func _on_toggle() -> void:
	if not processor.set_enabled(not processor.enabled):
		Events.toast.emit("먼저 레시피를 정해 주세요.")


func _on_cancel() -> void:
	if not processor.cancel(GameState.inventory):
		Events.toast.emit("가방에 돌려받을 재료를 넣을 자리가 없어요.")


func _on_take() -> void:
	var n := processor.take_output(GameState.inventory)
	if n == 0:
		Events.toast.emit("가방에 자리가 없어서 꺼낼 수 없어요.")
	elif not processor.output.is_empty():
		Events.toast.emit("가방에 들어가는 %d개만 꺼냈어요. 나머지는 가공기에 있어요." % n)
