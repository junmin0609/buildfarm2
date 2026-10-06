class_name Placeable
extends Node2D
## 농장에 설치된 시설 하나. 모든 시설의 공통 부모.
## 노드 위치는 차지하는 칸들의 아래쪽 가운데 (Objects 의 Y 정렬 기준이 발밑이 되도록).
##
## 회전 (BUILD_FARM_PLAN §54): turns = 시계 방향 90° 회전 횟수 (0~3).
##   홀수 번 돌리면 차지하는 칸의 가로·세로가 바뀐다 (3x4 → 4x3).
##   facing() 은 시설이 바라보는 방향: 0 아래, 1 왼쪽, 2 위, 3 오른쪽.
##   입출력 포트(§55)는 이 방향을 기준으로 돌려서 쓰면 된다 (rotate_dir).
##
## 특별한 동작이 있는 시설은 이 스크립트를 상속해 아래 훅을 덮어쓰면 된다.
##   on_placed / on_removed   설치·철거될 때
##   on_moved                 옮기거나 돌렸을 때 (상태는 그대로 유지된다 §63)
##   on_day_started           매일 아침, 플레이어가 깨어날 때 (자동 물주기 등). DayCycle 의 wake_up 단계에서 불린다.
##   removal_problem          옮기거나 철거하면 안 되는 이유 (안에 작물이 있는 온실 등 §105). 괜찮으면 ""
##   allows_farming           차지한 칸이라도 괭이질·심기를 허락하는 칸인가 (온실 안쪽 밭)
##   on_day_end               하루 마감의 farm_daily 단계 (퇴비 익히기 같은 일 단위 처리). report 에 결과를 적을 수 있다
##   contents                 안에 든 아이템 (칸 형식 배열). 철거하면 가방으로 돌려주고, 자리가 없으면 철거를 막는다 (§106)
##   take_contents            철거 직전: 안의 아이템을 비운다 (가방에 넣는 건 BuildMode 가 한다)
##   extra_cost               설치 뒤 더 들인 돈·재료 (창고 증축 등). 철거하면 건설비와 함께 돌려준다 (§64)
##   save_state / load_state  내부 상태 저장 (to_data 의 "state"). 옮겨도 노드 그대로라 상태가 유지된다 (§63)
## [E] 로 쓰는 시설은 "interactables" 그룹에 넣고 prompt / interact_point / can_interact / interact 를 만든다
## (Interactable 건물과 같은 이름이라 Player 가 같이 찾는다).

const TILE := Art.TILE
const DIRS: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]

var def: PlaceableDef
## 차지하는 칸들의 왼쪽 위 칸
var cell := Vector2i.ZERO
## 시계 방향 90° 회전 횟수 (0~3)
var turns := 0

var _sprite: Sprite2D
var _shape: RectangleShape2D
var _shape_node: CollisionShape2D


func setup(placeable_def: PlaceableDef, origin: Vector2i, new_turns := 0) -> void:
	def = placeable_def
	turns = posmod(new_turns, 4)
	name = "%s_%d_%d" % [def.id, origin.x, origin.y]
	set_cell(origin)


func set_cell(origin: Vector2i) -> void:
	cell = origin
	var s := size()
	position = Vector2(origin.x * TILE + s.x * TILE / 2.0, (origin.y + s.y) * TILE)


## 자리와 방향을 함께 바꾼다 (BuildGrid.move 가 쓴다)
func set_placement(origin: Vector2i, new_turns: int) -> void:
	turns = posmod(new_turns, 4)
	set_cell(origin)
	_update_visual()


## 지금 방향에서 차지하는 칸 수
func size() -> Vector2i:
	return def.size_for(turns)


func facing() -> Vector2i:
	return DIRS[turns]


func footprint() -> Array[Vector2i]:
	return footprint_of(def, cell, turns)


static func footprint_of(placeable_def: PlaceableDef, origin: Vector2i, rot := 0) -> Array[Vector2i]:
	var s := placeable_def.size_for(rot)
	var cells: Array[Vector2i] = []
	for y in s.y:
		for x in s.x:
			cells.append(origin + Vector2i(x, y))
	return cells


## 회전 0 기준 방향 dir 을 rot 만큼 시계 방향으로 돌린다 (포트 방향 계산용)
static func rotate_dir(dir: Vector2i, rot: int) -> Vector2i:
	var d := dir
	for i in posmod(rot, 4):
		d = Vector2i(-d.y, d.x)
	return d


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.centered = false
	add_child(_sprite)
	if def.solid:
		var body := StaticBody2D.new()
		_shape_node = CollisionShape2D.new()
		_shape = RectangleShape2D.new()
		_shape_node.shape = _shape
		body.add_child(_shape_node)
		add_child(body)
	_update_visual()


## 방향에 맞게 그림과 충돌 모양을 맞춘다
func _update_visual() -> void:
	if _sprite == null:
		return
	var tex := def.texture_for(turns)
	_sprite.texture = tex
	if tex:
		_sprite.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height())
	var s := size()
	if _shape:
		_shape.size = Vector2(s * TILE) - Vector2(2, 2)
		_shape_node.position = Vector2(0, -s.y * TILE / 2.0)
	queue_redraw()


## 그림이 없는 시설은 자리만 보이게 상자를 그린다 (JSON 에 texture 를 빼먹어도 멈추지 않게)
func _draw() -> void:
	if def.texture_for(turns) != null:
		return
	var s := Vector2(size() * TILE)
	var r := Rect2(Vector2(-s.x / 2.0, -s.y), s).grow(-1)
	draw_rect(r, Color("c98f5e"))
	draw_rect(r, Color("5b3a29"), false, 1.0)


# ---------- 확장 훅 (상속한 시설이 덮어쓴다)

func on_placed(_world: FarmWorld) -> void:
	pass


func on_removed(_world: FarmWorld) -> void:
	pass


func on_moved(_world: FarmWorld) -> void:
	pass


func on_day_started(_world: FarmWorld) -> void:
	pass


func removal_problem(_world: FarmWorld) -> String:
	return ""


func allows_farming(_cell: Vector2i) -> bool:
	return false


func on_day_end(_world: FarmWorld, _report: Dictionary) -> void:
	pass


func contents() -> Array:
	return []


func take_contents() -> void:
	pass


## {"price": G, "materials": {아이템 id: 개수}}
func extra_cost() -> Dictionary:
	return {"price": 0, "materials": {}}


func save_state() -> Dictionary:
	return {}


## 모양이 틀린 값은 건너뛰고 멈추지 않아야 한다
func load_state(_data: Dictionary) -> void:
	pass


# ---------- 저장용

func to_data() -> Dictionary:
	var out := {"id": def.id, "cell": [cell.x, cell.y], "turns": turns}
	var state := save_state()
	if not state.is_empty():
		out["state"] = state
	return out
