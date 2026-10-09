class_name NightSummaryPanel
extends PanelContainer
## 아침 야간 생산 요약 (BUILD_FARM_PLAN §98): "밤새 생산된 결과"를 짧게 보여 준다.
##   밤새 생산된 결과
##   [아이콘] 밀가루      +24
##   [아이콘] 기본 비료    +2
##   발전기가 만든 전기 +300
## 판매 수익 요약(§99, 하루 종료)과는 다른 창이다. 판매 요약이 있으면 그것을 닫은 다음에 뜬다 (HUD 가 순서를 맡음).
## 밤새 만든 물건이 없으면 뜨지 않는다. 열려 있는 동안 HUD 가 게임과 시간을 멈춘다.

signal close_requested

var _title: Label
var _lines: VBoxContainer
var _energy: Label


func _ready() -> void:
	custom_minimum_size = Vector2(460, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_override("font", Art.pixel_font(true))
	box.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	box.add_child(_lines)
	_energy = Label.new()
	_energy.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_energy.add_theme_color_override("font_color", Color("9a7457"))
	box.add_child(_energy)
	var ok := Button.new()
	ok.text = "확인"
	ok.pressed.connect(close_requested.emit)
	box.add_child(ok)


## 보여 줄 것이 있는가 (밤새 만든 물건)
static func has_content(night: Dictionary) -> bool:
	var items: Variant = night.get("items", {})
	return items is Dictionary and not items.is_empty()


## night: report.night_production ({"items": {아이템 id: 개수}, "energy": 발전량 ...})
func open(day: int, night: Dictionary) -> void:
	_title.text = "%s 아침 · 밤새 생산된 결과" % Calendar.date_text(day)
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	var items: Dictionary = night.get("items", {})
	var ids := items.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(items[a]) > int(items[b]))
	for id: String in ids:
		var item := ItemDB.get_item(id)
		if item:
			var row := ShopPanel.item_row(item, "+%d" % int(items[id]))
			_lines.add_child(row)
	var energy := float(night.get("energy", 0.0))
	var water := float(night.get("water", 0.0))
	var notes: Array[String] = []
	if energy >= 1.0:
		notes.append("발전기가 만든 전기 +%d" % roundi(energy))
	if water >= 1.0:
		notes.append("펌프가 퍼 올린 물 +%d" % roundi(water))
	_energy.text = "\n".join(notes)
	_energy.visible = not notes.is_empty()
	show()
	reset_size()
