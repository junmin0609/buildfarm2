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


func _ready() -> void:
	add_to_group("interactables")
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = Vector2(0, -texture.get_height())
	add_child(sprite)
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
