class_name Pump
extends Placeable
## 펌프 (BUILD_FARM_PLAN §14 우물 → 펌프 → 물탱크 → 자동 관개).
## 사용자 결정: 개울·연못에 맞닿은 칸에만 짓는다 (placeables.json "needs_water", BuildGrid.check)
##   퍼 올리는 동안에만 지역 전기 통에서 전기를 쓴다 (전기 가공기·자동 수확기와 같은 규칙).
##   퍼 올린 물은 지역 물통(물탱크들의 합)으로 간다. 물통이 가득 차거나 물탱크가 없으면 쉬고 전기도 안 쓴다.
##   전기가 모자라면 꺼낸 만큼만 퍼 올리고, 다시 차면 이어서. 밤에도 야간 생산 시간만큼 일한다 (§97).
## 수치는 placeables.json 의 "pump": {"water_per_hour", "power"}.

var _world: FarmWorld
## 전기가 모자라 덜 퍼 올린 상태 (표시용)
var starved := false


func config() -> Dictionary:
	var c: Variant = def.data.get("pump", {}) if def else {}
	return c if c is Dictionary else {}


func water_per_hour() -> float:
	return maxf(0.0, float(config().get("water_per_hour", 60)))


func power_use() -> int:
	return maxi(0, int(config().get("power", 20)))


func on_placed(world: FarmWorld) -> void:
	_world = world


## 물통에 자리가 있어서 퍼 올리는 중인가
func is_working() -> bool:
	if _world == null:
		return false
	var st := _world.build.water_status()
	return st.capacity > 0.0 and st.stored < st.capacity - 0.001


func power_demand() -> int:
	return power_use() if is_working() else 0


## 게임 시계 minutes 분만큼 퍼 올린다. 실제로 퍼 올린 물
func pump(minutes: float) -> float:
	if _world == null or minutes <= 0.0:
		return 0.0
	var st := _world.build.water_status()
	var room := float(st.capacity) - float(st.stored)
	var rate := water_per_hour() / 60.0
	if room <= 0.001 or rate <= 0.0:
		starved = false
		return 0.0
	var work := minf(minutes, room / rate)          # 물통이 차기까지 일하는 분
	var want := power_use() / 60.0 * work
	var got := _world.build.draw_energy(want) if want > 0.0 else 0.0
	var frac := 1.0 if want <= 0.0 else got / want
	starved = frac < 0.999
	return _world.build.fill_water(rate * work * frac)


func on_time(minutes: float) -> void:
	pump(minutes)


## 밤에 퍼 올린 물은 아침 야간 생산 요약에 나온다 (report.night_production.water)
func on_night_production(_w: FarmWorld, report: Dictionary, minutes: float) -> void:
	var got := pump(minutes)
	if got > 0.0:
		var night: Dictionary = report.get("night_production", {})
		night["water"] = float(night.get("water", 0.0)) + got
		report["night_production"] = night
