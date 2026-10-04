class_name CropInfoPopup
extends PanelContainer
## 마우스 아래 작물의 짧은 정보 (BUILD_FARM_PLAN §19). 커서 대각선 아래에 뜨고, 화면 밖으로 나가면 반대쪽으로 뒤집는다.
##   자라는 중:  당근 / 자라는 중 / 2 / 3일 / 오늘 물: 줬어요 / 수확까지 1일
##   물 안 줌:   ... / 오늘 물: 안 줬어요 / 오늘은 자라지 않아요
##   다 자람:    당근 / 수확할 수 있어요
## 정보는 Events.crop_hover_changed 로 받는다. 창이 열려 있으면 HUD 가 suppressed 로 숨긴다.

const OFFSET := Vector2(22, 22)
const TEXT_SOFT := Color("9a7457")
const ACCENT := Color("d9604f")
const GOOD := Color("5c8a3a")

var suppressed := false:
	set(value):
		suppressed = value
		_refresh_visible()

var _info := {}
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
	Events.crop_hover_changed.connect(show_info)
	hide()


func show_info(info: Dictionary) -> void:
	_info = info
	if not info.is_empty():
		_title.text = info.name
		for child in _body.get_children():
			_body.remove_child(child)
			child.queue_free()
		for line: Array in lines(info):
			var label := Label.new()
			label.text = line[0]
			label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
			label.add_theme_color_override("font_color", line[1])
			_body.add_child(label)
		reset_size()
	_refresh_visible()


## 본문 줄들: [글, 색]
static func lines(info: Dictionary) -> Array:
	var fert: Array = [["비료: %s" % info.fertilizer, TEXT_SOFT]] if str(info.get("fertilizer", "")) != "" else []
	if info.get("withered", false):
		return [["시들었어요", ACCENT], ["괭이·곡괭이로 뽑아 주세요", TEXT_SOFT]]
	if info.mature:
		return [["수확할 수 있어요", GOOD]] + fert
	var result := []
	result.append(["다시 열리는 중" if info.regrowing else "자라는 중", TEXT_SOFT])
	result.append(["%d / %d일" % [info.days, info.need], TEXT_SOFT])
	if info.watered:
		result.append(["오늘 물: 줬어요", TEXT_SOFT])
		result.append(["수확까지 %d일" % info.days_left, TEXT_SOFT])
	else:
		result.append(["오늘 물: 안 줬어요", ACCENT])
		result.append(["오늘은 자라지 않아요", ACCENT])
	return result + fert


func _refresh_visible() -> void:
	visible = not _info.is_empty() and not suppressed


func _process(_delta: float) -> void:
	if not visible:
		return
	CursorTooltip.place(self)
