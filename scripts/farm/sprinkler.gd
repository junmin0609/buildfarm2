class_name Sprinkler
extends Placeable
## 스프링클러 (BUILD_FARM_PLAN §14 자동 관개). 1칸짜리, 밭 사이에 놓는다.
## 매일 아침(DayCycle 의 wake_up 단계) 범위 안 마른 밭을 적신다. 범위는 placeables.json 의 "area"
## (하급 + 모양 4칸 / 중급 3x3 / 상급 5x5, FarmArea).
## 사용자 결정 (펌프·물탱크와 함께): 적신 칸마다 지역 물통(물탱크들의 합)에서 물 water_per_tile 을 쓴다.
##   물이 모자라면 적실 수 있는 만큼만 적시고, 못 적신 칸 수는 아침 알림으로 모아 보여 준다 (BuildGrid.start_day).
##   물탱크가 없으면 아무 칸도 적시지 못한다.
## 비 오는 날은 이미 젖어 있어서 물을 쓰지 않는다. 플레이어 이동을 막지 않는다.


func area_cells() -> Array[Vector2i]:
	return FarmArea.cells(cell, def.data.get("area"))


func water_per_tile() -> float:
	return maxf(0.0, float(def.data.get("water_per_tile", 1)))


## 범위 안 마른 밭에 물을 준다. {"watered": 적신 칸 수, "missed": 물이 모자라 못 적신 칸 수}
func water_area(world: FarmWorld) -> Dictionary:
	var watered := 0
	var missed := 0
	var need := water_per_tile()
	for c in area_cells():
		var tile := world.farm.get_tile(c)
		if tile == null or tile.watered:
			continue
		if need > 0.0:
			var got := world.build.draw_water(need)
			if got < need - 0.001:
				world.build.fill_water(got)  # 한 칸 몫이 안 되면 꺼낸 물은 돌려놓는다
				missed += 1
				continue
		if world.farm.water(c):
			watered += 1
	return {"watered": watered, "missed": missed}


func on_day_started(world: FarmWorld) -> void:
	var r := water_area(world)
	world.build.sprinkler_missed += int(r.missed)
