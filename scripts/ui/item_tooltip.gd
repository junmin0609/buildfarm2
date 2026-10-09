class_name ItemTooltip
extends PanelContainer
## 아이템 툴팁 (BUILD_FARM_PLAN §45). 가방·핫바 칸에 마우스를 올리면 커서 옆에 작게 뜬다.
## 드래그 중에는 숨는다. 고정된 아래쪽 설명 칸은 쓰지 않는다.
## 칸이 Events.item_hover_changed(칸 또는 null) 로 알려 준다.

const TEXT_SOFT := Color("9a7457")
const GOLD := Color("c98a2e")

var _slot: ItemSlot
var _title: Label
var _body: VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_override("font", Art.pixel_font(true))
	_title.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	box.add_child(_title)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	box.add_child(_body)
	Events.item_hover_changed.connect(show_for)
	hide()


func show_for(slot: Node) -> void:
	_slot = slot as ItemSlot
	if _slot == null or _slot.item == null:
		hide()
		return
	_title.text = _slot.item.name if _slot.quality == Quality.NONE else "%s (%s)" % [_slot.item.name, Quality.name_of(_slot.quality)]
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for line: Array in lines(_slot.item, _slot.quality, _slot.water):
		var label := Label.new()
		label.text = line[0]
		label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
		label.add_theme_color_override("font_color", line[1])
		_body.add_child(label)
	reset_size()
	show()
	CursorTooltip.place(self)


func _process(_delta: float) -> void:
	if not visible:
		return
	# 칸이 사라졌거나(창 닫힘) 드래그 중이면 숨긴다
	if _slot == null or not is_instance_valid(_slot) or not _slot.is_visible_in_tree() or get_viewport().gui_is_dragging():
		hide()
		return
	CursorTooltip.place(self)


## 툴팁 본문 줄들: [글, 색]
static func lines(item: ItemDef, quality := Quality.NONE, water := -1) -> Array:
	var out := []
	if item.description != "":
		out.append([item.description, TEXT_SOFT])
	match item.kind:
		ItemDef.Kind.SEED:
			var crop := ItemDB.get_item(item.grows)
			out.append(["성장 %d일" % item.grow_days, TEXT_SOFT])
			out.append(["다시 열림: %d일마다" % item.regrow_days if item.regrows() else "다시 열림: 없음 (한 번 수확)", TEXT_SOFT])
			if item.yield_max > 1:
				out.append(["수확량 %d~%d개" % [item.yield_min, item.yield_max], TEXT_SOFT])
			out.append(["계절: %s%s" % [Calendar.seasons_text(item), " (온실 전용)" if Calendar.greenhouse_only(item) else ""], TEXT_SOFT])
			out.append(["씨앗 가격 %d G" % item.buy_price, GOLD])
			if crop:
				out.append(["%s 기본 판매가 %d G" % [crop.name, crop.sell_price], GOLD])
		ItemDef.Kind.CROP, ItemDef.Kind.MATERIAL, ItemDef.Kind.PROCESSED:
			if item.is_sellable():
				out.append(["기준가 %d G" % Pricing.quality_price(item, quality), GOLD])
				out.append(["출하함 %d G · 광장 %d G" % [Pricing.unit_price(item, quality, Pricing.SHIPPING_BIN), Pricing.unit_price(item, quality, Pricing.PLAZA)], TEXT_SOFT])
		ItemDef.Kind.FERTILIZER:
			var chances: Dictionary = DataFile.load_dict(Quality.DATA_PATH).get("harvest_chances", {}).get(item.quality_table, {})
			var parts: Array[String] = []
			for q: String in Quality.ids():
				parts.append("%s %d%%" % [Quality.name_of(q), int(chances.get(q, 0))])
			out.append(["수확 품질: " + " · ".join(parts), TEXT_SOFT])
			out.append(["씨앗을 심기 전에 뿌려요", TEXT_SOFT])
			if item.buy_price > 0:
				out.append(["가격 %d G" % item.buy_price, GOLD])
		ItemDef.Kind.TOOL:
			out.append(["등급 %d" % item.tier, TEXT_SOFT])
			if item.capacity > 0:
				out.append(["물 %d / %d" % [maxi(water, 0), item.capacity], TEXT_SOFT])
			if item.max_charge > 1:
				var steps := ["3칸", "3x3", "5x5"].slice(0, item.max_charge - 1)
				out.append(["꾹 누르기: " + " → ".join(steps) + " (1초마다)", TEXT_SOFT])
			if item.power > 1:
				out.append(["작업 속도 ×%d" % item.power, TEXT_SOFT])
			if not item.upgrade.is_empty():
				out.append(["대장간에서 강화할 수 있어요", GOLD])
	return out
