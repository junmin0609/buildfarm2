class_name SalesSummaryPanel
extends PanelContainer
## 하루 종료 판매 수익 요약 (BUILD_FARM_PLAN §99): "오늘 번 돈"만 보여 준다.
##   오늘의 판매
##   농장 출하함    +2,400 G
##   광장 즉시 판매   +300 G
##   합계          +2,700 G
## 야간 생산 요약(§98, 다음 날 아침)과는 다른 창이다. 섞지 않는다.
## 열려 있는 동안 HUD 가 게임과 시간을 멈춘다.

signal close_requested

var _title: Label
var _lines: VBoxContainer
var _total: Label


func _ready() -> void:
	custom_minimum_size = Vector2(520, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_override("font", Art.pixel_font(true))
	box.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	box.add_child(_lines)
	_total = Label.new()
	_total.add_theme_color_override("font_color", Color("c98a2e"))
	_total.add_theme_font_override("font", Art.pixel_font(true))
	box.add_child(_total)
	var ok := Button.new()
	ok.text = "확인"
	ok.pressed.connect(close_requested.emit)
	box.add_child(ok)


## sales: {"by_channel": {채널: 금액}, "total": 금액}
func open(day: int, sales: Dictionary) -> void:
	_title.text = "%d일차 판매" % day
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	var by_channel: Dictionary = sales.get("by_channel", {})
	for channel: String in by_channel:
		_lines.add_child(_line(Pricing.channel_name(channel), int(by_channel[channel])))
	_total.text = "합계  +%s G" % format_gold(int(sales.get("total", 0)))
	show()
	reset_size()


func _line(label_text: String, amount: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value := Label.new()
	value.text = "+%s G" % format_gold(amount)
	value.add_theme_color_override("font_color", Color("c98a2e"))
	row.add_child(value)
	return row


## 2400 -> "2,400"
static func format_gold(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return ("-" if amount < 0 else "") + out
