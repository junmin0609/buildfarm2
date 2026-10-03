class_name Obstacle
extends Node2D
## 농장에 놓인 장애물 하나. 노드 위치는 칸의 아래쪽 가운데 (Y 정렬 기준).

const TILE := Art.TILE

var def: ObstacleDef
var cell := Vector2i.ZERO
## 남은 타격 수
var hp := 1
## 그림 고르기용 (같은 종류도 모양이 조금씩 다르게)
var variant := 0

var _sprite: Sprite2D
var _shake_tween: Tween


func setup(obstacle_def: ObstacleDef, at_cell: Vector2i, variant_seed: int) -> void:
	def = obstacle_def
	cell = at_cell
	hp = def.hits
	variant = variant_seed
	name = "%s_%d_%d" % [def.id, cell.x, cell.y]
	position = Vector2(cell.x * TILE + TILE / 2.0, (cell.y + 1) * TILE - 1)
	# 줄지어 보이지 않게 좌우로 살짝 어긋나게 (모양별로 항상 같은 값)
	position.x += float((variant / 3) % 5) - 2.0


func _ready() -> void:
	_sprite = Sprite2D.new()
	var tex: Texture2D = def.textures[variant % def.textures.size()]
	_sprite.texture = tex
	_sprite.centered = false
	_sprite.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height() + 1)
	_sprite.flip_h = (variant / 7) % 2 == 1
	add_child(_sprite)
	if def.solid:
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(12, 7)
		shape.shape = rect
		shape.position = Vector2(0, -4)
		body.add_child(shape)
		add_child(body)


## 맞았을 때 살짝 흔들림
func shake() -> void:
	if _sprite == null:
		return
	if _shake_tween:
		_shake_tween.kill()
	_sprite.position = Vector2.ZERO
	_shake_tween = create_tween()
	for x: float in [-1.0, 1.0, -1.0, 0.0]:
		_shake_tween.tween_property(_sprite, "position:x", x, 0.04)


func to_data() -> Dictionary:
	return {"id": def.id, "cell": [cell.x, cell.y], "hp": hp, "variant": variant}
