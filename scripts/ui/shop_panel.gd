class_name ShopPanel
extends PanelContainer
## 상점 창. 잡화점 NPC 에게서 씨앗을 사거나(buy) 가방 속 작물을 팔고(sell), 기계상점 NPC 에게서 기계를 산다(machine).
## 어느 상점에서 무엇을 파는지는 items.json 의 "shop" (general / machine). 기계는 돈과 함께 재료(buy_materials)도 든다.
## 여기서 파는 건 "광장 즉시 판매": 바로 돈을 받는 대신 기준가의 일부만 받는다 (data/economy.json 의 plaza).
## 품질이 다른 작물은 줄을 나눠 보여 주고, 가격에 품질 배율이 붙는다.

const CHANNEL := Pricing.PLAZA

signal close_requested

var _money_label: Label
var _title: Label
var _mode := "all"
var _buy_list: VBoxContainer
## 사기 목록을 감싼 스크롤. 기계상점은 기계가 많아 기준 화면(720) 안에서 스크롤한다
var _buy_scroll: ScrollContainer
var _buy_col: VBoxContainer
var _special_box: VBoxContainer
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
	title.text = "씨앗상점"
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

	# 오늘의 특별 상품 (씨앗 상점에서만, §101)
	_special_box = VBoxContainer.new()
	_special_box.add_theme_constant_override("separation", 4)
	box.add_child(_special_box)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	_buy_list = _column(columns, "씨앗·비료 사기")
	_buy_col = _buy_list.get_parent() as VBoxContainer
	_buy_scroll = ScrollContainer.new()
	_buy_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_buy_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_col.remove_child(_buy_list)
	_buy_scroll.add_child(_buy_list)
	_buy_col.add_child(_buy_scroll)
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


## mode: "buy" 씨앗·비료 사기, "sell" 작물 팔기, "machine" 기계 사기, "all" 사기+팔기
func open(mode := "all") -> void:
	_mode = mode
	_title.text = {"buy": "씨앗상점 · 사기", "sell": "씨앗상점 · 팔기", "machine": "기계상점", "smith": "대장간 · 사기"}.get(mode, "씨앗상점")
	(_buy_col.get_child(0) as Label).text = {"machine": "기계 사기", "smith": "용광로 사기"}.get(mode, "씨앗·비료 사기")
	_buy_col.visible = mode != "sell"
	_sell_list.get_parent().visible = mode in ["sell", "all"]
	# 기계상점만 목록이 길어 고정 높이 + 스크롤, 나머지는 목록 높이 그대로
	_buy_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if mode == "machine" else ScrollContainer.SCROLL_MODE_DISABLED
	_buy_scroll.custom_minimum_size = Vector2(0, 470 if mode == "machine" else 0)
	custom_minimum_size = Vector2(1040 if mode == "all" else 680, 0)
	refresh()
	show()
	reset_size()


func refresh() -> void:
	if not is_node_ready():
		return
	_money_label.text = "가진 돈  %d G" % GameState.money
	_refresh_special()
	_clear(_buy_list)
	var shop: String = {"machine": "machine", "smith": "smith"}.get(_mode, "general")
	for item in ItemDB.shop_items():
		if item.shop != shop:
			continue
		if not Calendar.in_season_for_shop(item, GameState.day):
			continue  # 이번 계절에 심을 수 없는 씨앗은 팔지 않는다
		# 기술이 잠긴 기계는 값 대신 해금 조건 (새 게임만, 스토리 3단계)
		var lock := QuestManager.lock_reason_now(item.id)
		var row := item_row(item, QuestManager.lock_short_now(item.id) if lock != "" else PlaceableDef.cost_text_of(item.buy_price, item.buy_materials))
		if lock != "":
			(row.get_child(2) as Label).add_theme_color_override("font_color", Color("b8a58c"))
			row.modulate.a = 0.75
		for qty: int in [1, 5]:
			var btn := Button.new()
			btn.text = "%d개" % qty
			btn.disabled = buy_problem(item, qty) != ""
			btn.pressed.connect(_buy.bind(item.id, qty))
			row.add_child(btn)
		_compact(row)
		_buy_list.add_child(row)

	_clear(_sell_list)
	var any := false
	for stack in _sellable_stacks():
		var item := ItemDB.get_item(stack.id)
		var quality: String = stack.quality
		var have := GameState.inventory.count_of(stack.id, quality)
		var row := item_row(item, "%d G  ·  %d개" % [Pricing.unit_price(item, quality, CHANNEL), have], quality)
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


## 오늘의 특별 상품 줄: 이름·내용·가격(따로 살 때 값)·[사기]. 사는 상점(buy, all)에서만 보인다.
func _refresh_special() -> void:
	_clear(_special_box)
	var id := GameState.daily_special
	_special_box.visible = _mode in ["buy", "all"] and DailySpecial.exists(id)
	if not _special_box.visible:
		return
	var heading := Label.new()
	heading.text = "오늘의 특별 상품 (오늘만, 수량 제한 없음)"
	heading.add_theme_color_override("font_color", Color("d9604f"))
	_special_box.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var items := DailySpecial.items_of(id)
	var icon := ItemSlot.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_slot({"id": items.keys()[0], "count": 1, "quality": ""})
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = DailySpecial.name_of(id)
	info.add_child(name_label)
	var detail := Label.new()
	detail.text = DailySpecial.contents_text(id)
	detail.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	detail.add_theme_color_override("font_color", Color("9a7457"))
	info.add_child(detail)
	row.add_child(info)
	var price := Label.new()
	var regular := DailySpecial.regular_price(id)
	price.text = "%d G" % DailySpecial.price_of(id) if regular <= DailySpecial.price_of(id) else "%d G (따로 %d G)" % [DailySpecial.price_of(id), regular]
	price.add_theme_color_override("font_color", Color("c98a2e"))
	row.add_child(price)
	var btn := Button.new()
	btn.text = "사기"
	btn.disabled = GameState.money < DailySpecial.price_of(id)
	btn.pressed.connect(_buy_special)
	row.add_child(btn)
	_compact(row)
	_special_box.add_child(row)


## 사는 줄은 계절에 따라 8줄까지 늘어나므로 조금 낮게 (아이콘 칸 52px, 버튼 글씨 작게)
func _compact(row: HBoxContainer) -> void:
	for child in row.get_children():
		if child is ItemSlot:
			child.custom_minimum_size = Vector2(52, 52)
		elif child is Button:
			child.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)


func _buy_special() -> void:
	var id := GameState.daily_special
	var result := DailySpecial.buy(id, GameState.inventory)
	Events.toast.emit("%s을(를) 샀어요." % DailySpecial.name_of(id) if result.ok else str(result.reason))


## 아이콘 + 이름(품질) + 가격 한 줄. 출하함 창도 같이 쓴다.
static func item_row(item: ItemDef, price_text: String, quality := Quality.NONE) -> HBoxContainer:
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


## qty 개를 살 수 없는 이유 (돈·재료·가방 자리). 살 수 있으면 ""
static func buy_problem(item: ItemDef, qty: int) -> String:
	var lock := QuestManager.lock_reason_now(item.id)
	if lock != "":
		return lock
	if GameState.money < item.buy_price * qty:
		return "돈이 부족해요."
	for mat_id: String in item.buy_materials:
		if GameState.inventory.count_of(mat_id) < int(item.buy_materials[mat_id]) * qty:
			return "%s이(가) 부족해요." % ItemDB.get_item(mat_id).name
	if not GameState.inventory.can_add(item.id, qty):
		return "가방에 자리가 없어요."
	return ""


func _buy(item_id: String, qty: int) -> void:
	var item := ItemDB.get_item(item_id)
	var problem := buy_problem(item, qty)
	if problem != "" or not GameState.try_spend(item.buy_price * qty):
		Events.toast.emit(problem if problem != "" else "돈이 부족해요.")
		return
	for mat_id: String in item.buy_materials:
		GameState.inventory.remove(mat_id, int(item.buy_materials[mat_id]) * qty)
	GameState.inventory.add(item_id, qty)
	Events.toast.emit("%s %d개를 샀어요." % [item.name, qty])


func _sell(item_id: String, qty: int, quality := Quality.NONE) -> void:
	var item := ItemDB.get_item(item_id)
	if qty <= 0 or not GameState.inventory.remove(item_id, qty, quality):
		return
	var earned := Pricing.unit_price(item, quality, CHANNEL) * qty
	GameState.add_money(earned)
	GameState.record_sale(CHANNEL, earned)
	Events.toast.emit("%s %d개를 팔아 %d G를 벌었어요." % [item.name, qty, earned])


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
