class_name ItemSlot
extends Control
## 아이템 한 칸. 도트 테두리 + 3배 확대한 아이콘 + 개수.
## 품질이 있으면 오른쪽 위에 품질 색 보석, 물뿌리개는 아래에 남은 물 막대.
## draggable 이면 가방(GameState.inventory)의 index 칸으로 다뤄 끌어다 놓을 수 있다 (가방 창 ↔ 핫바 모두).
## 마우스를 올리면 Events.item_hover_changed 로 알려 커서 옆 툴팁(ItemTooltip)이 뜬다.

signal clicked(index: int)
signal right_clicked(index: int)

const SLOT_SIZE := 60.0
const ICON_SCALE := 3.0
const TEXT := Color("5b3a29")
const SHADOW := Color("fff6e4")

static var _box: StyleBoxTexture
static var _box_selected: StyleBoxTexture

var index := 0
var show_number := false
var item: ItemDef = null
var count := 0
var quality := Quality.NONE
## 물뿌리개처럼 채워 쓰는 도구: 남은 양 (-1 이면 표시 안 함)
var water := -1
var selected := false
var picked := false
## 가방 칸으로 끌어다 놓을 수 있는가 (가방 창·핫바 칸만 true)
var draggable := false

var _hover := false


func _init() -> void:
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree() and _hover:
			_set_hover(false))
	if _box == null:
		_box = Art.box(Art.UI_SLOT, 4, 0)
		_box_selected = Art.box(Art.UI_SLOT_SELECTED, 4, 0)


func _set_hover(value: bool) -> void:
	_hover = value
	queue_redraw()
	if mouse_filter != Control.MOUSE_FILTER_IGNORE:
		Events.item_hover_changed.emit(self if value and item != null else null)


func set_slot(slot: Variant) -> void:
	item = ItemDB.get_item(slot["id"]) if slot != null else null
	count = slot["count"] if slot != null else 0
	quality = slot.get("quality", Quality.NONE) if slot != null else Quality.NONE
	water = int(slot.get("water", -1)) if slot != null and item != null and item.capacity > 0 else -1
	queue_redraw()
	if _hover and mouse_filter != Control.MOUSE_FILTER_IGNORE:
		Events.item_hover_changed.emit(self if item != null else null)  # 내용이 바뀌면 툴팁도 새로


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


# ---------- 끌어다 놓기 (Godot 기본 드래그 앤 드롭)

## 끌기 시작할 때 넘길 데이터. 빈 칸·끌 수 없는 칸이면 null.
func drag_data() -> Variant:
	if not draggable or item == null:
		return null
	return {"from": index}


func _get_drag_data(_at: Vector2) -> Variant:
	var data: Variant = drag_data()
	if data == null:
		return null
	var preview := TextureRect.new()
	var icon := AtlasTexture.new()
	icon.atlas = Art.ITEMS
	icon.region = Art.item_region(item)
	preview.texture = icon
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = Vector2(16, 16) * ICON_SCALE
	preview.position = -preview.size / 2.0
	var holder := Control.new()
	holder.add_child(preview)
	set_drag_preview(holder)
	Events.item_hover_changed.emit(null)
	return data


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return draggable and data is Dictionary and data.has("from")


func _drop_data(_at: Vector2, data: Variant) -> void:
	GameState.inventory.move(int(data["from"]), index)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(index)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit(index)
		accept_event()


func _draw() -> void:
	draw_style_box(_box_selected if selected or picked else _box, Rect2(Vector2.ZERO, size))
	if _hover:
		draw_rect(Rect2(Vector2(9, 9), size - Vector2(18, 18)), Color(1, 1, 1, 0.25))
	var font := get_theme_default_font()
	if show_number:
		_text(font, Vector2(8, 20), str(index + 1), Art.FONT_SIZE_SMALL, HORIZONTAL_ALIGNMENT_LEFT, Color("b08a66"))
	if item == null:
		return
	var icon_size := Vector2(16, 16) * ICON_SCALE
	var icon_pos := ((size - icon_size) / 2.0).floor()
	if picked:
		icon_pos.y -= 3
	draw_texture_rect_region(Art.ITEMS, Rect2(icon_pos, icon_size), Art.item_region(item))
	if count > 1:
		_text(font, Vector2(0, size.y - 7), str(count), Art.FONT_SIZE_SMALL, HORIZONTAL_ALIGNMENT_RIGHT, TEXT, size.x - 8)
	if quality != Quality.NONE:
		_draw_quality_gem(Vector2(size.x - 14, 14), Quality.color_of(quality))
	if water >= 0:
		# 남은 물: 갈색 테두리 + 크림색 빈 칸 + 파란 물
		var bar := Rect2(9, size.y - 16, size.x - 18, 8)
		draw_rect(bar, Color("8a5a3b"))
		draw_rect(bar.grow(-2), Color("fbf0da"))
		var fill := bar.grow(-2)
		fill.size.x = roundf(fill.size.x * clampf(float(water) / maxi(1, item.capacity), 0.0, 1.0))
		draw_rect(fill, Color("5aa3cc"))


## 마름모 보석 (품질 색). 아이콘 위에 겹쳐도 보이게 진한 테두리를 두른다.
func _draw_quality_gem(center: Vector2, color: Color) -> void:
	var outer := PackedVector2Array([center + Vector2(0, -10), center + Vector2(10, 0), center + Vector2(0, 10), center + Vector2(-10, 0)])
	var inner := PackedVector2Array([center + Vector2(0, -6), center + Vector2(6, 0), center + Vector2(0, 6), center + Vector2(-6, 0)])
	draw_colored_polygon(outer, Color("5b3a29"))
	draw_colored_polygon(inner, color)
	draw_rect(Rect2(center + Vector2(-3, -3), Vector2(3, 3)), Color(1, 1, 1, 0.75))


func _text(font: Font, pos: Vector2, text: String, font_size: int, align: HorizontalAlignment, color: Color, width := -1.0) -> void:
	for off: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		draw_string(font, pos + off, text, align, width, font_size, SHADOW)
	draw_string(font, pos, text, align, width, font_size, color)
