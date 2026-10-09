class_name BuildGrid
extends Node
## 농장에 설치된 시설을 칸 단위로 관리한다. 설치·이동·철거와 "여기에 놓을 수 있나" 판정을 맡는다.
## 돈 계산이나 입력은 하지 않는다 (BuildMode 가 맡음). 자동화·저장 기능도 이 함수들을 그대로 쓰면 된다.
##
## 설치 규칙 (BUILD_FARM_PLAN §52, §53)
##   - 장애물(잡초·돌·나뭇가지·그루터기 ...)이 있는 칸은 안 된다. 자동으로 치우지 않는다: 개간은 플레이어 몫.
##   - 갈아 둔 밭 위에는 지을 수 있다. 지으면 그 칸은 보통 땅으로 돌아가고, 철거하면 보통 땅으로 남는다.
##   - 작물이 자라는 밭은 안 된다 (작물이 사라지지 않게, §105).
##   - turns(회전)에 따라 차지하는 칸이 바뀐다 (§54). 옮길 때도 돌릴 수 있다.

signal changed

var world: FarmWorld
## 이 지역의 컨베이어 전체 (§56~§61). 게임 시계·야간 생산 때 시설 다음에 움직인다
var conveyors := ConveyorNet.new(self)
var _cells: Dictionary = {}          # Vector2i -> Placeable
var _objects: Array[Placeable] = []


func _ready() -> void:
	changed.connect(func() -> void: Events.power_changed.emit())
	changed.connect(conveyors.refresh)
	Events.time_advanced.connect(_on_time)


# ---------- 조회

func objects() -> Array[Placeable]:
	return _objects


func object_at(cell: Vector2i) -> Placeable:
	return _cells.get(cell)


func is_occupied(cell: Vector2i) -> bool:
	return _cells.has(cell)


## 시설 때문에 이 칸에서 농사를 못 짓는가 (온실 안쪽 밭처럼 시설이 허락하는 칸은 false)
func blocks_farming(cell: Vector2i) -> bool:
	var obj: Placeable = _cells.get(cell)
	return obj != null and not obj.allows_farming(cell)


## 시설을 지을 수 있는 땅인가 (지금은 농장 땅)
func is_buildable_ground(cell: Vector2i) -> bool:
	return MapLayout.char_at(cell) in MapLayout.BUILDABLE


## origin(왼쪽 위)에 def 를 turns 방향으로 놓을 수 있는지. ignore 는 이동 중인 자기 자신.
## 돌려주는 값: {"ok": bool, "bad": Array[Vector2i] (막힌 칸), "reason": String}
func check(def: PlaceableDef, origin: Vector2i, ignore: Placeable = null, turns := 0) -> Dictionary:
	var bad: Array[Vector2i] = []
	var reason := ""
	var player_cells := _player_cells()
	for c in Placeable.footprint_of(def, origin, turns):
		var why := _space_problem(c, ignore)
		if why == "":
			why = _cell_problem(c, player_cells)
		if why != "":
			bad.append(c)
			if reason == "":
				reason = why
	return {"ok": bad.is_empty(), "bad": bad, "reason": reason}


## 지금 이 칸에 무언가 있어서 지을 수 없는가 (시설·장애물·작물). 격자 표시용, 플레이어 위치는 보지 않는다.
func is_cell_taken(c: Vector2i) -> bool:
	return _cells.has(c) or _cell_problem(c, []) != ""


## 땅·겹침만 보는 판정 (저장 불러오기는 이것만 확인한다)
func _space_problem(c: Vector2i, ignore: Placeable) -> String:
	if not is_buildable_ground(c):
		return "농장 땅에만 지을 수 있어요."
	if _cells.has(c) and _cells[c] != ignore:
		return "이미 다른 시설이 있어요."
	return ""


## 지금 그 칸에 있는 것 때문에 못 짓는 이유 (장애물·작물·플레이어)
func _cell_problem(c: Vector2i, player_cells: Array[Vector2i]) -> String:
	if world.obstacles.is_blocked(c):
		return "먼저 장애물을 치워야 해요."
	if world.farm.get_tile(c) != null and world.farm.get_tile(c).has_crop():
		return "작물이 자라는 밭에는 지을 수 없어요."
	if c in player_cells:
		return "서 있는 자리에는 지을 수 없어요."
	return ""


func _player_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var p := world.player.global_position
	for off: Vector2 in [Vector2(-4, -6), Vector2(4, -6), Vector2(-4, 2), Vector2(4, 2)]:
		var c := world.world_to_cell(p + off)
		if c not in cells:
			cells.append(c)
	return cells


# ---------- 설치·이동·철거

func place(def: PlaceableDef, origin: Vector2i, turns := 0) -> Placeable:
	if not check(def, origin, null, turns).ok:
		return null
	return _spawn(def, origin, turns)


func _spawn(def: PlaceableDef, origin: Vector2i, turns: int) -> Placeable:
	var obj: Placeable
	if def.script_path != "":
		obj = (load(def.script_path) as GDScript).new()
	else:
		obj = Placeable.new()
	obj.setup(def, origin, turns)
	world.objects.add_child(obj)
	_register(obj)
	_clear_soil(obj)
	obj.on_placed(world)
	changed.emit()
	return obj


## 시설을 다른 자리·방향으로 옮긴다. 시설 자체(내부 상태)는 그대로다 (§63). turns 가 -1 이면 방향 유지.
func move(obj: Placeable, origin: Vector2i, turns := -1) -> bool:
	var new_turns := obj.turns if turns < 0 else turns
	if not check(obj.def, origin, obj, new_turns).ok:
		return false
	_unregister(obj)
	obj.set_placement(origin, new_turns)
	_register(obj)
	_clear_soil(obj)
	obj.on_moved(world)
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


# ---------- 지역 전기 (§75, 사용자 결정)
## 지역마다 따로인 전기 통. 지금 지역은 시작 농장 하나라 이 BuildGrid 가 곧 "농장 지역"이다 (전선·전봇대 없음).
## 발전기가 연료를 태워 만든 전기를 자기 통에 채우고, 지역 전기 통 = 그 지역 발전기 통들의 합이다.
## 전기 기계는 실제로 일하는 동안에만 지역 전기 통에서 꺼내 쓰고, 통이 비면 멈췄다가 다시 차면 이어서 일한다.

## {"stored": 남은 전기, "capacity": 통 크기 합, "output": 지금 만드는 전기/시간, "demand": 지금 쓰는 전기/시간}
func power_status() -> Dictionary:
	var stored := 0.0
	var capacity := 0.0
	var output := 0
	var demand := 0
	for obj in _objects:
		stored += obj.energy_stored()
		capacity += obj.energy_capacity()
		output += obj.power_output()
		demand += obj.power_demand()
	return {"stored": stored, "capacity": capacity, "output": output, "demand": demand}


## 지역 전기 통에서 amount 만큼 꺼낸다 (발전기들에서 차례로). 실제로 꺼낸 양
func draw_energy(amount: float) -> float:
	var got := 0.0
	for obj in _objects:
		if got >= amount:
			break
		if obj.energy_stored() > 0.0:
			got += obj.take_energy(amount - got)
	return got


## 발전기(전기를 담는 시설) 먼저, 나머지 다음 순서 — 같은 시간에 만든 전기를 바로 쓸 수 있게
func _ordered() -> Array[Placeable]:
	var first: Array[Placeable] = []
	var rest: Array[Placeable] = []
	for obj in _objects:
		if obj.energy_capacity() > 0.0:
			first.append(obj)
		else:
			rest.append(obj)
	return first + rest


func _on_time(minutes: float) -> void:
	for obj in _ordered():
		if is_instance_valid(obj):
			obj.on_time(minutes)
	conveyors.tick(minutes)


## 하루 마감의 night_production 단계 (§97): 야간 생산 시간을 잘게 나눠, 매번 발전기 먼저 → 기계 → 컨베이어 순서로 일한다
const NIGHT_SLICE := 10.0

func night_production(report: Dictionary, minutes: float) -> void:
	var left := minutes
	while left > 0.0:
		var step := minf(NIGHT_SLICE, left)
		for obj in _ordered():
			obj.on_night_production(world, report, step)
		conveyors.tick(step)
		left -= step


## 하루 마감의 farm_daily 단계: 시설의 일 단위 처리 (퇴비통 등)
func end_day(report: Dictionary) -> void:
	for obj in _objects:
		obj.on_day_end(world, report)


## 새 날 아침 (DayCycle 의 wake_up 단계): 시설의 아침 동작 (스프링클러 등)
func start_day() -> void:
	for obj in _objects:
		obj.on_day_started(world)


# ---------- 저장용

func to_data() -> Array:
	return _objects.map(func(o: Placeable) -> Dictionary: return o.to_data())


## 저장된 시설을 다시 놓는다. 저장 당시 이미 놓여 있던 것이므로 플레이어 위치·장애물·작물은 따지지 않고
## 땅과 겹침만 확인한다. 그래도 놓을 수 없는 항목은 조용히 버리지 않고 목록으로 돌려준다 (오류도 남김).
## 받은 데이터가 통째로 틀리면(배열이 아니면) 아무것도 바꾸지 않고 [null] 을 돌려준다.
func load_data(data: Variant) -> Array:
	if not data is Array:
		return [null]
	for obj in _objects.duplicate():
		remove(obj)
	var failed := []
	for entry: Variant in data:
		if not entry is Dictionary:
			failed.append(entry)
			continue
		var def := PlaceableDB.get_def(str(entry.get("id", "")))
		var origin := DataFile.to_vector2i(entry.get("cell"), Vector2i(-1, -1))
		var turns := int(entry.get("turns", 0))
		if def == null or not _fits_space(def, origin, turns):
			push_error("시설을 불러오지 못했습니다: %s" % entry)
			failed.append(entry)
			continue
		var obj := _spawn(def, origin, turns)
		if entry.get("state") is Dictionary:
			obj.load_state(entry.state)
	return failed


func _fits_space(def: PlaceableDef, origin: Vector2i, turns: int) -> bool:
	for c in Placeable.footprint_of(def, origin, turns):
		if _space_problem(c, null) != "":
			return false
	return true
