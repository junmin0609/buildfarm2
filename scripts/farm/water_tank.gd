class_name WaterTank
extends Placeable
## 물탱크 (BUILD_FARM_PLAN §14). 펌프가 퍼 올린 물을 담아 둔다.
## 사용자 결정: 지역 물통 = 그 지역 물탱크들의 합 (전기 통과 같은 방식, 파이프 없음).
##   펌프가 BuildGrid.fill_water 로 채우고, 스프링클러가 아침마다 BuildGrid.draw_water 로 꺼내 쓴다.
## 크기는 placeables.json 의 "water_tank": {"capacity"}. 철거하면 담긴 물은 아이템이 아니라 함께 사라진다.

var water := 0.0


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
