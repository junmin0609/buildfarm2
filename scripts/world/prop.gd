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
## 그림 변형 (꽃밭·화분 색 등). 비어 있지 않으면 자리마다 하나를 골라 쓴다 (늘 같은 자리엔 같은 그림)
@export var variants: Array[Texture2D] = []
## 간판 글자 (아치·팻말). sign_rect 는 그림 왼쪽 위 기준 간판 판 자리
@export var sign_text := ""
@export var sign_rect := Rect2()
## 저녁 불빛 (가로등 등, 무드 개편): 노드 기준 자리. 비어 있으면 없음
@export var night_lights: PackedVector2Array = []
@export var light_radius := 40.0


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	if not variants.is_empty():
		sprite.texture = variants[absi(hash(Vector2i(position.round()))) % variants.size()]
	sprite.centered = false
	sprite.offset = -foot
	add_child(sprite)
	if sign_text != "":
		add_child(Art.sign_label(sign_text, sign_rect, -foot))
	for p in night_lights:
		add_child(NightLight.make(p, light_radius))
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
