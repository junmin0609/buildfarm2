class_name Prop
extends Node2D
## 나무·바위처럼 맵에 놓이는 물체. 노드 위치가 물체의 발밑이고, 밑동만 충돌한다.
## (Objects 노드가 Y 정렬이라 플레이어가 나무 뒤로 지나가면 가려진다)

@export var texture: Texture2D
## 그림에서 발밑(바닥 가운데)의 위치. 이 점이 노드 위치에 오도록 그린다.
@export var foot := Vector2(8, 15)
## 충돌 사각형 (노드 위치 기준)
@export var collision := Rect2(-5, -5, 10, 5)
## false 면 지나갈 수 있다 (갈대·꽃 같은 것)
@export var solid := true


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.offset = -foot
	add_child(sprite)
	if not solid:
		return

	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = collision.size
	shape.shape = rect
	shape.position = collision.get_center()
	body.add_child(shape)
	add_child(body)
