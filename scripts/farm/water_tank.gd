class_name WaterTank
extends Placeable
## 물탱크 (BUILD_FARM_PLAN §14). 펌프가 퍼 올린 물을 담아 둔다.
## 사용자 결정: 지역 물통 = 그 지역 물탱크들의 합 (전기 통과 같은 방식, 파이프 없음).
##   펌프가 BuildGrid.fill_water 로 채우고, 스프링클러가 아침마다 BuildGrid.draw_water 로 꺼내 쓴다.
## 크기는 placeables.json 의 "water_tank": {"capacity"}. 철거하면 담긴 물은 아이템이 아니라 함께 사라진다.
## 물뿌리개도 채울 수 있다 (사용자 요청): 앞에서 [E] 또는 물뿌리개로 클릭 → 지역 물통(물탱크들의 합)에서 꺼내 채운다.
## 우물과 같은 물 공급원 규칙 (WateringCan.WATER_SOURCES: covers_cell / provide_water / water_source_name).

const REACH := 14.0

var water := 0.0
var prompt := "[E] 물탱크 (물뿌리개 채우기)"
var _world: FarmWorld


func capacity() -> float:
	var c: Variant = def.data.get("water_tank", {}) if def else {}
	return maxf(1.0, float(c.get("capacity", 200))) if c is Dictionary else 200.0


func water_capacity() -> float:
	return capacity()


func water_stored() -> float:
	return water


func add_water(amount: float) -> float:
	var put := clampf(amount, 0.0, capacity() - water)
	water += put
	return put


func take_water(amount: float) -> float:
	var got := clampf(amount, 0.0, water)
	water -= got
	return got


func save_state() -> Dictionary:
	return {"water": snappedf(water, 0.001)}


func load_state(data: Dictionary) -> void:
	water = clampf(float(data.get("water", 0.0)), 0.0, capacity()) if typeof(data.get("water")) in [TYPE_INT, TYPE_FLOAT] else 0.0


func on_placed(world: FarmWorld) -> void:
	_world = world


func _ready() -> void:
	super()
	add_to_group("interactables")
	add_to_group(WateringCan.WATER_SOURCES)


func interact_point() -> Vector2:
	return global_position + Vector2(0, 7)


func can_interact(from: Vector2) -> bool:
	return from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	if _pool() < 1.0:
		Events.toast.emit("물탱크가 비었어요. 펌프로 물을 채워 주세요.")
		return
	WateringCan.refill_all(GameState.inventory, self)


# ---------- 물 공급원 (물뿌리개)

func covers_cell(c: Vector2i) -> bool:
	return c in footprint()


## 지역 물통에서 amount 만큼 (모자라면 있는 만큼, 한 칸 단위) 꺼내 준다
func provide_water(amount: int) -> int:
	if _world == null:
		return 0
	var take := mini(maxi(amount, 0), floori(_pool()))
	if take <= 0:
		return 0
	return roundi(_world.build.draw_water(float(take)))


func water_source_name() -> String:
	return "물탱크"


func _pool() -> float:
	return float(_world.build.water_status().stored) if _world else water
