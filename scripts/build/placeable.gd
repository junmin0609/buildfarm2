class_name Placeable
extends Node2D
## 농장에 설치된 시설 하나. 모든 시설의 공통 부모.
## 노드 위치는 차지하는 칸들의 아래쪽 가운데 (Objects 의 Y 정렬 기준이 발밑이 되도록).
##
## 특별한 동작이 있는 시설은 이 스크립트를 상속해 아래 훅을 덮어쓰면 된다.
##   on_placed / on_removed   설치·철거될 때
##   on_day_started           매일 아침 (자동 물주기, 자동 수확 등)

const TILE := Art.TILE

var def: PlaceableDef
## 차지하는 칸들의 왼쪽 위 칸
var cell := Vector2i.ZERO


func setup(placeable_def: PlaceableDef, origin: Vector2i) -> void:
	def = placeable_def
	name = "%s_%d_%d" % [def.id, origin.x, origin.y]
	set_cell(origin)


func set_cell(origin: Vector2i) -> void:
	cell = origin
	position = Vector2(origin.x * TILE + def.size.x * TILE / 2.0, (origin.y + def.size.y) * TILE)


func footprint() -> Array[Vector2i]:
	return footprint_of(def, cell)


static func footprint_of(placeable_def: PlaceableDef, origin: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in placeable_def.size.y:
		for x in placeable_def.size.x:
			cells.append(origin + Vector2i(x, y))
	return cells


func _ready() -> void:
	var sprite := Sprite2D.new()
	sprite.texture = def.texture
	sprite.centered = false
	sprite.offset = Vector2(-def.texture.get_width() / 2.0, -def.texture.get_height())
	add_child(sprite)
	if def.solid:
		var body := StaticBody2D.new()
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(def.size * TILE) - Vector2(2, 2)
		shape.shape = rect
		shape.position = Vector2(0, -def.size.y * TILE / 2.0)
		body.add_child(shape)
		add_child(body)


# ---------- 확장 훅 (상속한 시설이 덮어쓴다)

func on_placed(_world: FarmWorld) -> void:
	pass


func on_removed(_world: FarmWorld) -> void:
	pass


func on_day_started(_world: FarmWorld) -> void:
	pass


# ---------- 저장용

func to_data() -> Dictionary:
	return {"id": def.id, "cell": [cell.x, cell.y]}
