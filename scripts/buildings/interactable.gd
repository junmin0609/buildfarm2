class_name Interactable
extends Node2D
## 플레이어가 다가가서 [E]로 쓰는 건물의 공통 부모.
## 노드 위치는 건물이 차지하는 칸들의 왼쪽 아래 모서리다 (Y 정렬 기준).
## 아래쪽 solid_height 픽셀만 막혀서, 플레이어가 지붕 뒤로 지나가면 건물에 가려진다.

const TILE := Art.TILE
const REACH := 14.0

@export var texture: Texture2D
@export var size_tiles := Vector2i(1, 1)
@export var solid_height := 16.0
@export var prompt := "상호작용"
## 상호작용 지점 (건물 아래쪽, 왼쪽에서 얼마나 떨어졌는지)
@export var door_x := 8.0
## 그림에 바닥 그림자가 없는 건물만 켠다: 밑변에 픽셀 계단 모양의 옅은 접지 그림자 (빛은 다른 그림처럼 왼쪽 위)
@export var ground_shadow := false
## 간판 글자 (무드 개편): 그림의 간판 판 자리(sign_rect, 그림 왼쪽 위 기준)에 도트 폰트로 얹는다. 비어 있으면 없음
@export var sign_text := ""
@export var sign_rect := Rect2()

## 그림자 줄: [위로부터 y, 왼쪽에서 들여쓰기, 오른쪽에서 들여쓰기, 진하기]
const SHADOW_ROWS := [[-1, 2, -1, 0.16], [0, 1, -2, 0.24], [1, 3, 0, 0.16], [2, 6, 3, 0.08]]
const SHADOW_COLOR := Color("5b3a29")


func _ready() -> void:
	add_to_group("interactables")
	if ground_shadow:
		var shadow := Node2D.new()
		var w := texture.get_width()
		shadow.draw.connect(func() -> void:
			for row: Array in SHADOW_ROWS:
				var x0: int = row[1]
				var x1: int = w - int(row[2])
				shadow.draw_rect(Rect2(x0, row[0], x1 - x0, 1), Color(SHADOW_COLOR, row[3])))
		add_child(shadow)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = Vector2(0, -texture.get_height())
	add_child(sprite)
	if sign_text != "":
		add_child(Art.sign_label(sign_text, sign_rect, sprite.offset))
	_add_collision()


func _add_collision() -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size_tiles.x * TILE, solid_height)
	shape.shape = rect
	shape.position = Vector2(rect.size.x / 2.0, -rect.size.y / 2.0)
	body.add_child(shape)
	add_child(body)


## 플레이어가 서서 상호작용하는 지점 (문 앞)
func interact_point() -> Vector2:
	return global_position + Vector2(door_x, 7)


func can_interact(from: Vector2) -> bool:
	return from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	pass
