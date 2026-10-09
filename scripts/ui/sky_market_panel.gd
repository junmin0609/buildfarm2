class_name SkyMarketPanel
extends PanelContainer
## 하늘시장 가판대 창 (BUILD_FARM_PLAN §84~§88). 하늘섬에서만 연다.
##   위: 오늘 날짜 시세 · 이벤트 · 분류별 흐름 (채소 ▲ 12% ...)
##   아래: 가방에 든 하늘시장 품목(작물·가공품)마다 오늘 개당 값 + 기준가 대비 + [1개] [모두] 팔기
## 판 돈은 판매 요약에 "하늘시장" 으로 들어간다. 상점처럼 열려 있는 동안 게임과 시간이 멈춘다 (HUD 가 처리).

signal close_requested

const LIST_HEIGHT := 360

var _money: Label
var _event: Label
var _trends: Label
var _list: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(1000, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var title := Label.new()
	title.text = "하늘시장"
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
	_event = _small("", Color("c0503a"))
	box.add_child(_event)
	_trends = _small("", Color("9a7457"))
	_trends.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_trends)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	box.add_child(scroll)
	box.add_child(_small("시세는 하루 한 번 바뀌고, 내일 시세는 알 수 없어요.", Color("9a7457")))
	Events.inventory_changed.connect(refresh)
	Events.money_changed.connect(func(_m: int) -> void: refresh())


func _small(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", color)
	return label


func open() -> void:
	show()
	refresh()


func refresh() -> void:
	if not is_node_ready() or not visible:
		return
	var today := SkyMarket.today()
	_money.text = "%s 시세 · 가진 돈 %s G" % [Calendar.date_text(GameState.day), SalesSummaryPanel.format_gold(GameState.money)]
	var ev := SkyMarket.event_info()
	_event.visible = not ev.is_empty()
	_event.text = "오늘의 소식: %s — %s" % [ev.get("name", ""), ev.get("text", "")] if not ev.is_empty() else ""
	var parts: Array[String] = []
	for cat: String in SkyMarket.categories():
		var m := float(today.categories.get(cat, 1.0))
		if cat == "special" and SkyMarket.categories()[cat].get("items", []).is_empty():
			continue
		parts.append("%s %s" % [SkyMarket.category_name(cat), SkyMarket.change_text(m)])
	_trends.text = "오늘 흐름:  " + "   ".join(parts)
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var any := false
	for st in GameState.inventory.stacks():
		var item := ItemDB.get_item(st.id)
		if SkyMarket.category_of(item) == "":
			continue
		any = true
		_list.add_child(_row(item, str(st.quality)))
	if not any:
		_list.add_child(_small("가방에 하늘시장에서 파는 물건(작물·가공품)이 없어요.", Color("9a7457")))
	reset_size()


func _row(item: ItemDef, quality: String) -> HBoxContainer:
	var inv := GameState.inventory
	var count := inv.count_of(item.id, quality)
	var price := SkyMarket.unit_price(item, quality)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := ItemSlot.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_slot({"id": item.id, "count": count, "quality": quality})
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = item.name + ((" (%s)" % Quality.name_of(quality)) if quality != Quality.NONE else "")
	info.add_child(name_label)
	var m := SkyMarket.multiplier(item)
	var detail := _small("오늘 %d G · 기준가 대비 %s · %s" % [price, SkyMarket.change_text(m), SkyMarket.category_name(SkyMarket.category_of(item))],
			Color("4f8a3f") if m > 1.0 else (Color("c0503a") if m < 1.0 else Color("9a7457")))
	info.add_child(detail)
	row.add_child(info)
	for entry: Array in [["1개 팔기", 1], ["모두 팔기", count]]:
		var btn := Button.new()
		btn.text = entry[0]
		btn.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
		btn.pressed.connect(sell.bind(item.id, quality, int(entry[1])))
		row.add_child(btn)
	return row


## 가방에서 count 개를 오늘 값으로 판다. 번 돈 (팔지 못하면 0)
static func sell(item_id: String, quality: String, count: int) -> int:
	var item := ItemDB.get_item(item_id)
	var price := SkyMarket.unit_price(item, quality)
	var inv := GameState.inventory
	if price <= 0 or count <= 0 or not inv.remove(item_id, count, quality):
		return 0
	var total := price * count
	GameState.add_money(total)
	GameState.record_sale(SkyMarket.CHANNEL, total)
	Events.toast.emit("%s %d개 판매 +%s G" % [item.name, count, SalesSummaryPanel.format_gold(total)])
	return total
