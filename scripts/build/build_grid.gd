class_name BuildGrid
extends Node
## 농장에 설치된 시설을 칸 단위로 관리한다. 설치·이동·철거와 "여기에 놓을 수 있나" 판정을 맡는다.
## 돈 계산이나 입력은 하지 않는다 (BuildMode 가 맡음). 자동화·저장 기능도 이 함수들을 그대로 쓰면 된다.
##
## 설치 규칙 (BUILD_FARM_PLAN §52, §53)
##   - 장애물(잡초·돌·나뭇가지·그루터기 ...)이 있는 칸은 안 된다. 자동으로 치우지 않는다: 개간은 플레이어 몫.
##   - 갈아 둔 밭 위에는 지을 수 있다. 지으면 그 칸은 보통 땅으로 돌아가고, 철거하면 보통 땅으로 남는다.
##   - 작물이 자라는 밭은 안 된다 (작물이 사라지지 않게, §105).

signal changed

var world: FarmWorld
var _cells: Dictionary = {}          # Vector2i -> Placeable
var _objects: Array[Placeable] = []


func _ready() -> void:
	Events.day_started.connect(_on_day_started)


# ---------- 조회

func objects() -> Array[Placeable]:
	return _objects


func object_at(cell: Vector2i) -> Placeable:
	return _cells.get(cell)


func is_occupied(cell: Vector2i) -> bool:
	return _cells.has(cell)


## 시설을 지을 수 있는 땅인가 (지금은 농장 땅)
func is_buildable_ground(cell: Vector2i) -> bool:
	return MapLayout.char_at(cell) in MapLayout.BUILDABLE


## origin(왼쪽 위)에 def 를 놓을 수 있는지. ignore 는 이동 중인 자기 자신.
## 돌려주는 값: {"ok": bool, "bad": Array[Vector2i] (막힌 칸), "reason": String}
func check(def: PlaceableDef, origin: Vector2i, ignore: Placeable = null) -> Dictionary:
	var bad: Array[Vector2i] = []
	var reason := ""
	var player_cells := _player_cells()
	for c in Placeable.footprint_of(def, origin):
		var why := ""
		if not is_buildable_ground(c):
			why = "농장 땅에만 지을 수 있어요."
		elif _cells.has(c) and _cells[c] != ignore:
			why = "이미 다른 시설이 있어요."
		elif world.obstacles.is_blocked(c):
			why = "먼저 장애물을 치워야 해요."
		elif world.farm.get_tile(c) != null and world.farm.get_tile(c).has_crop():
			why = "작물이 자라는 밭에는 지을 수 없어요."
		elif c in player_cells:
			why = "서 있는 자리에는 지을 수 없어요."
		if why != "":
			bad.append(c)
			if reason == "":
				reason = why
	return {"ok": bad.is_empty(), "bad": bad, "reason": reason}


func _player_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var p := world.player.global_position
	for off: Vector2 in [Vector2(-4, -6), Vector2(4, -6), Vector2(-4, 2), Vector2(4, 2)]:
		var c := world.world_to_cell(p + off)
		if c not in cells:
			cells.append(c)
	return cells


# ---------- 설치·이동·철거

func place(def: PlaceableDef, origin: Vector2i) -> Placeable:
	if not check(def, origin).ok:
		return null
	var obj: Placeable
	if def.script_path != "":
		obj = (load(def.script_path) as GDScript).new()
	else:
		obj = Placeable.new()
	obj.setup(def, origin)
	world.objects.add_child(obj)
	_register(obj)
	_clear_soil(obj)
	obj.on_placed(world)
	changed.emit()
	return obj


func move(obj: Placeable, origin: Vector2i) -> bool:
	if not check(obj.def, origin, obj).ok:
		return false
	_unregister(obj)
	obj.set_cell(origin)
	_register(obj)
	_clear_soil(obj)
	changed.emit()
	return true


func remove(obj: Placeable) -> void:
	if obj not in _objects:
		return
	_unregister(obj)
	_objects.erase(obj)
	obj.on_removed(world)
	obj.queue_free()
	changed.emit()


func _register(obj: Placeable) -> void:
	if obj not in _objects:
		_objects.append(obj)
	for c in obj.footprint():
		_cells[c] = obj


## 시설 밑의 갈아 둔 밭은 보통 땅이 된다 (§53)
func _clear_soil(obj: Placeable) -> void:
	for c in obj.footprint():
		world.farm.untill(c)


func _unregister(obj: Placeable) -> void:
	for c in obj.footprint():
		if _cells.get(c) == obj:
			_cells.erase(c)


func _on_day_started(_day: int) -> void:
	for obj in _objects:
		obj.on_day_started(world)


# ---------- 저장용

func to_data() -> Array:
	return _objects.map(func(o: Placeable) -> Dictionary: return o.to_data())


func load_data(data: Array) -> void:
	for obj in _objects.duplicate():
		remove(obj)
	for entry: Dictionary in data:
		var def := PlaceableDB.get_def(entry.get("id", ""))
		var c: Array = entry.get("cell", [0, 0])
		if def:
			place(def, Vector2i(int(c[0]), int(c[1])))
