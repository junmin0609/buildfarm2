class_name TitleBackground
extends Control
## 시작 화면 뒤 농장 풍경. 게임 그림(타일·작물·시설)을 3배로 키워 그린다 (그림을 새로 만들지 않음).
## 가운데는 메뉴 창이 덮으므로 양옆에 집·밭·창고·발전기·나무를 둔다. 작물은 천천히 흔들린다.

const SCALE := 3.0

var _house := preload("res://assets/art/house.png")
var _tree := preload("res://assets/art/tree.png")
var _warehouse := preload("res://assets/art/warehouse.png")
var _generator := preload("res://assets/art/generator.png")
var _processor := preload("res://assets/art/electric_processor.png")
var _scarecrow := preload("res://assets/art/scarecrow.png")
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
	var t := Art.TILE
	var cols := ceili(size.x / SCALE / t) + 1
	var rows := ceili(size.y / SCALE / t) + 1
	var path_row := rows - 4
	# 잔디 (칸마다 정해진 무늬) + 아래쪽 흙길
	for y in rows:
		for x in cols:
			var h := absi(x * 73856093 ^ y * 19349663) % 100
			var tile := Vector2i(h % 4, 0)
			if h >= 92:
				tile = Vector2i(4 + h % 2, 0)  # 꽃잔디
			if y == path_row:
				tile = Vector2i(7, 0)
			draw_texture_rect_region(Art.TILES, Rect2(x * t, y * t, t, t), Art.tile_region(tile))
	var w := cols * t
	# 왼쪽: 집 + 밭 (다 자란 작물이 흔들림)
	_sprite(_house, Vector2(t * 3, t * 5))
	for i in 4:
		for j in 2:
			var cell := Vector2(t * (2 + i), t * (7 + j))
			draw_texture_rect_region(Art.TILES, Rect2(cell, Vector2(t, t)), Art.tile_region(Vector2i(3, 1)))
			var crop_row: int = [0, 2, 1, 2][i]
			var sway := roundf(sin(_time * 1.6 + i * 0.9 + j) * 0.6)
			draw_texture_rect_region(Art.CROPS, Rect2(cell + Vector2(sway, -4), Vector2(t, t)), Rect2(4 * t, crop_row * t, t, t))
	_sprite(_scarecrow, Vector2(t * 6.5, t * 9))
	# 오른쪽: 창고 + 전기 가공기 + 발전기
	_sprite(_warehouse, Vector2(w - t * 5, t * 7))
	_sprite(_processor, Vector2(w - t * 8.5, t * 8))
	_sprite(_generator, Vector2(w - t * 11, t * 8))
	# 가장자리 나무
	for p: Vector2 in [Vector2(t * 0.5, t * 3), Vector2(t * 9, t * 2.5), Vector2(w - t * 2, t * 3), Vector2(w - t * 10, t * 3),
			Vector2(t * 1, float(path_row + 3) * t), Vector2(w - t * 3, float(path_row + 3) * t)]:
		_sprite(_tree, p)


## 발밑 가운데가 pos 가 되게 그린다
func _sprite(tex: Texture2D, pos: Vector2) -> void:
	draw_texture(tex, pos - Vector2(tex.get_width() / 2.0, tex.get_height()))
