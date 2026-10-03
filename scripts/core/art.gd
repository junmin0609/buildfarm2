class_name Art
extends RefCounted
## 게임에서 쓰는 픽셀 아트 모음. 그림은 tools/make_art.py 로 만든다.

const TILE := 16

const TILES := preload("res://assets/art/tiles.png")
const EDGES := preload("res://assets/art/edges.png")
const DETAILS := preload("res://assets/art/details.png")
const CROPS := preload("res://assets/art/crops.png")
const ITEMS := preload("res://assets/art/items.png")

## Neo둥근모 (SIL OFL 1.1): 획 끝이 둥근 16px 한글 도트 폰트. 16의 배수 크기에서 선명하다.
const FONT := preload("res://assets/fonts/neodgm.ttf")
const FONT_SIZE := 32
const FONT_SIZE_SMALL := 16

const UI_PANEL := preload("res://assets/art/ui_panel.png")
const UI_SLOT := preload("res://assets/art/ui_slot.png")
const UI_SLOT_SELECTED := preload("res://assets/art/ui_slot_selected.png")
const UI_BUTTON := preload("res://assets/art/ui_button.png")
const UI_BUTTON_HOVER := preload("res://assets/art/ui_button_hover.png")
const UI_BUTTON_PRESSED := preload("res://assets/art/ui_button_pressed.png")
const UI_BUTTON_DISABLED := preload("res://assets/art/ui_button_disabled.png")
const UI_KEY := preload("res://assets/art/ui_key.png")
## 0 해, 1 달, 2 동전, 3 말풍선
const UI_ICONS := preload("res://assets/art/ui_icons.png")

## UI 그림은 3배로 키워 저장돼 있다. 픽셀 1칸 = 3px
const UI_SCALE := 3


static func item_region(item: ItemDef) -> Rect2:
	return Rect2(item.icon * TILE, 0, TILE, TILE)


static func tile_region(coords: Vector2i) -> Rect2:
	return Rect2(Vector2(coords * TILE), Vector2(TILE, TILE))


## 9칸 늘이기 테두리. margin_px 는 원본 그림 기준 픽셀 수
static func box(texture: Texture2D, margin_px: int, content_margin: float) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = texture
	var m := margin_px * UI_SCALE
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.set_content_margin_all(content_margin)
	return sb


static var _font: FontFile
static var _font_bold: FontVariation


## 도트 폰트를 흐리지 않게 (안티앨리어싱 끔). bold 는 획을 살짝 두껍게.
static func pixel_font(bold := false) -> Font:
	if _font == null:
		_font = FONT.duplicate()
		_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_font.hinting = TextServer.HINTING_NONE
		_font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_font_bold = FontVariation.new()
		_font_bold.base_font = _font
		_font_bold.variation_embolden = 0.5
	return _font_bold if bold else _font
