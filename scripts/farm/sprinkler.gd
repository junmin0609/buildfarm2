class_name Sprinkler
extends Placeable
## 스프링클러 (BUILD_FARM_PLAN §14 자동 관개). 1칸짜리, 밭 사이에 놓는다.
## 사용자 결정: 놓아두기만 하면 매일 아침(DayCycle 의 wake_up 단계) 범위 안 갈아 둔 밭에 물을 준다.
##   범위는 placeables.json 의 "area" (하급 + 모양 4칸 / 중급 3x3 / 상급 5x5, FarmArea).
##   물 공급원(펌프·물탱크)은 아직 없다. 나중에 붙이면 on_day_started 에서 물이 있는지만 보면 된다.
## 비 오는 날은 이미 젖어 있어서 아무것도 바꾸지 않는다. 플레이어 이동을 막지 않는다.


func area_cells() -> Array[Vector2i]:
	return FarmArea.cells(cell, def.data.get("area"))


## 범위 안 갈아 둔 밭에 물을 준다. 새로 젖은 칸 수
func water_area(world: FarmWorld) -> int:
	var n := 0
	for c in area_cells():
		if world.farm.water(c):
			n += 1
	return n


func on_day_started(world: FarmWorld) -> void:
	water_area(world)
