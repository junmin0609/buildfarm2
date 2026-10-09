class_name ObstacleGrid
extends Node
## 개간 시스템. 농장 땅의 장애물(잡초·돌·나뭇가지·그루터기·큰 바위...)을 칸 단위로 관리한다.
##   - 새 게임: 시작 농장에 장애물을 깐다 (집에서 가까운 땅은 비워 둔다)
##   - 도구로 치면 hp 가 줄고, 다 깨지면 자원을 가방에 넣는다 (가방이 차면 깨지지 않는다)
##   - 매일 아침 작은 장애물이 빈 땅에 조금씩 다시 생긴다
## 수치는 모두 data/obstacles.json 에 있다.

signal changed

const TOOL_NAMES := {"hoe": "괭이", "axe": "도끼", "pickaxe": "곡괭이"}

var world: FarmWorld
var rng := RandomNumberGenerator.new()
var _cells: Dictionary = {}   # Vector2i -> Obstacle


func _ready() -> void:
	rng.randomize()


# ---------- 조회

func obstacle_at(cell: Vector2i) -> Obstacle:
	return _cells.get(cell)


func is_blocked(cell: Vector2i) -> bool:
	return _cells.has(cell)


func count() -> int:
	return _cells.size()


func all() -> Array:
	return _cells.values()


# ---------- 시작 농장 깔기

## 농장 땅을 집(start)에서 가까운 순서로 나눠, 바로 쓸 땅 / 작은 장애물 땅 / 큰 장애물 땅에 깐다.
func generate_start(start: Vector2) -> void:
	var cfg := ObstacleDB.start_farm()
	var gen := RandomNumberGenerator.new()
	gen.seed = int(cfg.get("seed", 1))
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return world.cell_center(a).distance_squared_to(start) < world.cell_center(b).distance_squared_to(start))
	var n := cells.size()
	var clear_end := int(n * float(cfg.get("clear_ratio", 0.3)))
	var small_end := clear_end + int(n * float(cfg.get("small_ratio", 0.5)))
	for i in n:
		var cell: Vector2i = cells[i]
		if i < clear_end or MapLayout.char_at(cell) != "g":
			continue  # 바로 쓸 땅, 일궈 둔 흙밭은 비워 둔다
		var small := i < small_end
		var density := float(cfg.get("small_zone_density" if small else "large_zone_density", 0.5))
		if gen.randf() >= density:
			continue
		var type_id := ObstacleDB.pick_weighted(cfg.get("small_zone" if small else "large_zone", {}), gen)
		spawn(cell, type_id, gen.randi())


# ---------- 생성·제거

func spawn(cell: Vector2i, type_id: String, variant_seed: int = 0) -> Obstacle:
	var def := ObstacleDB.get_def(type_id)
	if def == null or _cells.has(cell):
		return null
	var ob := Obstacle.new()
	ob.setup(def, cell, absi(variant_seed))
	world.objects.add_child(ob)
	_cells[cell] = ob
	changed.emit()
	return ob


func remove(cell: Vector2i) -> void:
	var ob: Obstacle = _cells.get(cell)
	if ob == null:
		return
	_cells.erase(cell)
	ob.queue_free()
	changed.emit()


# ---------- 도구로 치기

## 손에 든 아이템으로 cell 의 장애물을 친다. 장애물이 있으면 true (휘두름을 소비함).
func try_clear(cell: Vector2i, item: ItemDef) -> bool:
	var ob: Obstacle = _cells.get(cell)
	if ob == null:
		return false
	var tool := item.tool_type if item != null and item.kind == ItemDef.Kind.TOOL else ""
	if tool not in ob.def.tools:
		Events.toast.emit("%s은(는) %s(으)로 치울 수 있어요." % [ob.def.name, _tool_list(ob.def.tools)])
		return true
	if item.tier < ob.def.tier:
		Events.toast.emit("%s은(는) 더 좋은 %s이(가) 필요해요." % [ob.def.name, _tool_list(ob.def.tools)])
		ob.shake()
		return true
	ob.hp -= item.power  # 강화 도구는 한 번에 더 많이 깎는다
	ob.shake()
	if ob.hp > 0:
		return true
	# 다 깨졌다: 자원을 넣을 자리가 없으면 깨지지 않고 남는다 (아이템 안전 §105)
	var drops := _roll_drops(ob.def)
	for item_id: String in drops:
		if not GameState.inventory.can_add(item_id, drops[item_id]):
			ob.hp = 1
			Events.toast.emit("가방이 가득 차서 %s을(를) 치울 수 없어요." % ob.def.name)
			return true
	var got: Array[String] = []
	for item_id: String in drops:
		GameState.inventory.add(item_id, drops[item_id])
		got.append("%s +%d" % [ItemDB.get_item(item_id).name, drops[item_id]])
	remove(cell)
	if not got.is_empty():
		Events.toast.emit(" · ".join(got))
	return true


func _roll_drops(def: ObstacleDef) -> Dictionary:
	var result := {}
	for d: Dictionary in def.drops:
		var amount := rng.randi_range(int(d.get("min", 1)), int(d.get("max", 1)))
		if amount > 0:
			result[d["item"]] = result.get(d["item"], 0) + amount
	return result


func _tool_list(tools: Array[String]) -> String:
	return "·".join(tools.map(func(t: String) -> String: return TOOL_NAMES.get(t, t)))


# ---------- 다시 자라기 (§103)

## 하루 마감 때 (DayCycle 의 farm_daily 단계)
func process_day() -> void:
	regrow()


## 작은 장애물이 빈 농장 땅에 조금씩 다시 생긴다. 밭·시설·장애물·플레이어 자리는 피한다.
func regrow() -> int:
	var cfg := ObstacleDB.regrow()
	var cells: Array = world.farm.farmable_cells.keys()
	if cells.is_empty():
		return 0
	var spawned := 0
	for i in int(cfg.get("attempts_per_day", 0)):
		if rng.randf() >= float(cfg.get("chance", 0.0)):
			continue
		var cell: Vector2i = cells[rng.randi() % cells.size()]
		if not can_grow_at(cell):
			continue
		if spawn(cell, ObstacleDB.pick_weighted(cfg.get("types", {}), rng), rng.randi()):
			spawned += 1
	return spawned


func can_grow_at(cell: Vector2i) -> bool:
	if _cells.has(cell) or world.farm.tiles.has(cell) or world.build.is_occupied(cell) or world.build.is_reserved(cell):
		return false
	if MapLayout.char_at(cell) != "g":
		return false
	return world.world_to_cell(world.player.global_position).distance_to(cell) > 1.5


# ---------- 저장용

func to_data() -> Array:
	return _cells.values().map(func(o: Obstacle) -> Dictionary: return o.to_data())


## 저장된 장애물을 되살린다. 모양이 틀린 항목은 건너뛴다. 받은 데이터가 통째로 틀리면 false (장애물은 그대로).
func load_data(data: Variant) -> bool:
	if not data is Array:
		return false
	for cell: Vector2i in _cells.keys():
		remove(cell)
	for entry: Variant in data:
		if not entry is Dictionary:
			continue
		var cell := DataFile.to_vector2i(entry.get("cell"), Vector2i(-1, -1))
		var ob := spawn(cell, str(entry.get("id", "")), int(entry.get("variant", 0)))
		if ob:
			ob.hp = clampi(int(entry.get("hp", ob.def.hits)), 1, ob.def.hits)
	return true
