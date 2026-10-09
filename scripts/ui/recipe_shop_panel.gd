class_name RecipeShopPanel
extends PanelContainer
## 레시피 상점(셰프) 창 (BUILD_FARM_PLAN §71). 처음부터 아는 레시피를 뺀 나머지를 보여 준다.
##   재료를 모두 얻어 본 레시피: 이름·재료·시간·결과물 판매가·값 + [배우기]
##   아직 못 얻은 재료가 있는 레시피: "???" (얻은 재료만 이름을 보여 주고 나머지는 ???)
##   배운 레시피: 맨 아래에 흐리게
## 상점처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

const LIST_HEIGHT := 560

var _list: VBoxContainer
var _money: Label


func _ready() -> void:
	custom_minimum_size = Vector2(1000, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var title := Label.new()
	title.text = "레시피 상점"
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
	hint.text = "재료를 모두 한 번씩 얻어 본 요리를 가르쳐 드려요. 한 번 배우면 모든 가공기에서 계속 써요."
	hint.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	hint.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	box.add_child(scroll)
	Events.money_changed.connect(func(_m: int) -> void: refresh())
	Events.processor_changed.connect(refresh)


func open() -> void:
	show()
	refresh()


## 배울 수 있는 것 → 아직 못 여는 것 → 배운 것 순서
static func ordered() -> Array[Dictionary]:
	var groups: Array = [[], [], []]
	for r in RecipeDB.shop_recipes():
		var g := 2 if RecipeDB.is_known(r.id) else (0 if RecipeDB.is_revealed(r.id) else 1)
		groups[g].append(r)
	var out: Array[Dictionary] = []
	for g: Array in groups:
		for r: Dictionary in g:
			out.append(r)
	return out


func refresh() -> void:
	if not is_node_ready() or not visible:
		return  # 닫혀 있을 때는 돈이 바뀌어도 다시 그리지 않는다 (열 때 그림)
	_money.text = "가진 돈  %s G" % SalesSummaryPanel.format_gold(GameState.money)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for r in ordered():
		_list.add_child(_row(r))
	reset_size()


func _row(r: Dictionary) -> HBoxContainer:
	var known := RecipeDB.is_known(r.id)
	var revealed := RecipeDB.is_revealed(r.id)
	var out_item := ItemDB.get_item(r.output)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := ItemSlot.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if revealed or known:
		icon.set_slot({"id": out_item.id, "count": int(r.count), "quality": ""})
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = (out_item.name + (" ×%d" % r.count if r.count > 1 else "")) if revealed or known else "???"
	info.add_child(name_label)
	var detail := Label.new()
	detail.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	detail.add_theme_color_override("font_color", Color("9a7457"))
	if revealed or known:
		detail.text = "%s · %s · 판매가 %d G%s" % [RecipeDB.inputs_text(r), RecipeDB.time_text(r.minutes), out_item.sell_price * int(r.count), " · %d급 (%s)" % [int(r.tier), "중급 가공기" if int(r.machine_tier) == 2 else "상급 가공기"] if int(r.machine_tier) >= 2 else ""]
	else:
		detail.text = "필요한 재료: %s  (모두 얻으면 배울 수 있어요)" % _hidden_inputs(r)
	info.add_child(detail)
	row.add_child(info)
	var price := Label.new()
	price.text = "%s G" % SalesSummaryPanel.format_gold(int(r.price)) if revealed and not known else ""
	price.custom_minimum_size = Vector2(150, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(price)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(140, 0)
	btn.text = "배웠어요" if known else ("배우기" if revealed else "???")
	var problem := RecipeDB.buy_problem(r.id)
	btn.disabled = problem != ""
	btn.tooltip_text = problem
	btn.pressed.connect(_buy.bind(r.id))
	row.add_child(btn)
	if known:
		row.modulate.a = 0.55
	elif not revealed:
		row.modulate.a = 0.75
	return row


## "딸기 · ???": 얻어 본 재료는 이름, 아직이면 ???
static func _hidden_inputs(r: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id: String in r.inputs:
		parts.append(ItemDB.get_item(item_id).name if GameState.has_found(item_id) else "???")
	return " · ".join(parts)


func _buy(id: String) -> void:
	var problem := RecipeDB.buy_problem(id)
	if problem != "" or not RecipeDB.buy(id):
		Events.toast.emit(problem)
		return
	Events.toast.emit("%s 레시피를 배웠어요! 가공기에서 고를 수 있어요." % ItemDB.get_item(RecipeDB.get_recipe(id).output).name)
