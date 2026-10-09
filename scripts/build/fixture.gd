class_name Fixture
extends Placeable
## 농장 고정 건물(집·출하함·우물)이 건설 격자에서 차지하는 자리 (사용자 결정: 건설 모드에서 농장 땅 어디로든 옮길 수 있고, 철거는 안 됨).
##
## 실제 건물(잠자기·출하·물 긷기를 하는 Interactable 노드)은 FarmWorld 가 맵에서 만든 그대로 두고,
## 이 자리표를 옮기면 건물 노드를 같이 옮긴다. 그래서 출하함 내용물 저장, world.shipping_bin, 우물의 물 공급원 같은
## 기존 연결은 바뀌지 않는다. 자리표 자체는 그림·충돌이 없다 (옮기는 동안의 미리보기만 def 그림을 쓴다).
##
## 앞 한 줄(front_cells)은 늘 비워 둔다: 다른 시설을 못 놓고, 장애물도 다시 자라지 않는다.
## 집을 옮기면 아침에 깨어나는 자리(world.home_position)도 새 집 앞으로 바뀐다.

var _world: FarmWorld


## 이 자리표가 옮기는 건물 노드 (FarmWorld.fixture_buildings)
func building() -> Interactable:
	if _world == null:
		return null
	return _world.fixture_buildings.get(str(def.data.get("fixture", "")))


func on_placed(world: FarmWorld) -> void:
	_world = world
	_sync()


func on_moved(world: FarmWorld) -> void:
	_world = world
	_sync()


func demolish_problem(_w: FarmWorld) -> String:
	return "%s은(는) 철거할 수 없어요. [옮기기]로 자리만 바꿀 수 있어요." % def.name


## 비워 둬야 하는 앞 한 줄 (차지한 칸 바로 아래)
func front_cells() -> Array[Vector2i]:
	return front_cells_of(def, cell, turns)


static func front_cells_of(placeable_def: PlaceableDef, origin: Vector2i, rot := 0) -> Array[Vector2i]:
	var s := placeable_def.size_for(rot)
	var cells: Array[Vector2i] = []
	for x in s.x:
		cells.append(origin + Vector2i(x, s.y))
	return cells


## 건물 노드를 이 칸으로 옮긴다 (건물 원점은 차지한 칸들의 왼쪽 아래). 집이면 깨어나는 자리도 집 앞으로
func _sync() -> void:
	var b := building()
	if b == null:
		return
	b.position = Vector2(cell.x * TILE, (cell.y + size().y) * TILE)
	if def.data.get("fixture") == "house":
		_world.home_position = _world.cell_center(cell + Vector2i(2, size().y + 1))


## 자리표는 그리지 않는다 (건물 노드가 그림)
func _update_visual() -> void:
	super()
	if _sprite:
		_sprite.visible = false
