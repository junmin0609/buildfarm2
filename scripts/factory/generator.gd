class_name Generator
extends Placeable
## 발전기 (BUILD_FARM_PLAN §75, §77). 연료를 태워 전기를 만들고 자기 전기 통에 채운다.
## 수치는 placeables.json 의 "generator" (시간당 만드는 전기·통 크기·연료별로 타는 시간·연료 칸 한도).
##
## 사용자 결정
##   - 발전기는 연료를 넣는 방식
##   - 발전기 여러 대가 만든 전기는 지역 전기 통에 모이고(= 발전기 통들의 합), 전기 기계들이 일할 때 나눠 쓴다
## 연료 (임시 결정): 식물 섬유·나무를 바로 넣는다. 바이오 연료 가공 단계는 나중에 추가할 수 있다 (fuels 에 항목만 넣으면 됨).
##
## 흐름
##   1. [E] → 가방의 연료를 넣는다 (아직 타지 않은 연료는 다시 꺼낼 수 있다)
##   2. 게임 시계가 흐르면 연료를 하나씩 태우며 시간당 output_per_hour 만큼 통에 채운다
##   3. 통이 가득 차면 쉬어서 연료를 아낀다 (타던 연료의 남은 시간도 그대로)
##   4. 밤에는 야간 생산 시간만큼 같은 방식으로 일한다
## 철거하면 남은 연료를 가방으로 돌려준다 (타던 1개는 이미 태운 것). 통의 전기는 아이템이 아니라 함께 사라진다.

const REACH := 14.0

var prompt := "[E] 발전기"
## 아직 타지 않은 연료 (칸 형식)
var fuel: Array[Dictionary] = []
## 지금 타는 연료 id 와 남은 시간(게임 분)
var burning := ""
var burn_left := 0.0
## 통에 든 전기
var energy := 0.0

var _world: FarmWorld


func config() -> Dictionary:
	var c: Variant = def.data.get("generator", {}) if def else {}
	return c if c is Dictionary else {}


func output_per_hour() -> float:
	return maxf(0.0, float(config().get("output_per_hour", 60)))


func storage() -> float:
	return maxf(1.0, float(config().get("storage", 300)))


func max_fuel() -> int:
	return maxi(1, int(config().get("max_fuel", 99)))


## 연료 하나가 타는 시간 (게임 분). 연료가 아니면 0
func burn_minutes(item_id: String) -> float:
	var fuels: Variant = config().get("fuels", {})
	return maxf(0.0, float(fuels.get(item_id, 0))) if fuels is Dictionary else 0.0


func accepts(item: ItemDef) -> bool:
	return item != null and burn_minutes(item.id) > 0.0


func fuel_count() -> int:
	var n := 0
	for st in fuel:
		n += int(st.count)
	return n


## 연료가 다 타기까지 남은 시간 합 (타는 것 포함)
func fuel_minutes_left() -> float:
	var total := burn_left
	for st in fuel:
		total += burn_minutes(st.id) * int(st.count)
	return total


func is_burning() -> bool:
	return burning != "" and burn_left > 0.0


func is_full() -> bool:
	return energy >= storage() - 0.001


# ---------- 전기 통 (Placeable 훅)

func energy_capacity() -> float:
	return storage()


func energy_stored() -> float:
	return energy


func take_energy(amount: float) -> float:
	var got := minf(amount, energy)
	energy -= got
	return got


## 지금 전기를 만들고 있으면 시간당 출력 (통이 가득 차서 쉬거나 연료가 없으면 0)
func power_output() -> int:
	return roundi(output_per_hour()) if (is_burning() or not fuel.is_empty()) and not is_full() else 0


## 이 발전기가 있는 지역 전기 통 {"stored", "capacity", "output", "demand"}
func _world_power() -> Dictionary:
	return _world.build.power_status() if _world else {"stored": energy, "capacity": storage(), "output": power_output(), "demand": 0}


func on_placed(world: FarmWorld) -> void:
	_world = world


# ---------- 넣기 / 꺼내기

## 가방에서 연료 count 개를 넣는다 (연료 칸 한도까지). 넣은 개수
func deposit(inv: Inventory, item_id: String, count: int) -> int:
	if not accepts(ItemDB.get_item(item_id)):
		return 0
	var n := mini(mini(count, max_fuel() - fuel_count()), inv.count_of(item_id))
	if n <= 0 or not inv.remove(item_id, n):
		return 0
	_add(item_id, n)
	_changed()
	return n


## 컨베이어 입구 (§55): 연료 1개를 받는다 (연료 칸 한도까지)
func accept_item(item_id: String, _quality: String) -> bool:
	if not accepts(ItemDB.get_item(item_id)) or fuel_count() >= max_fuel():
		return false
	_add(item_id, 1)
	_changed()
	return true


## 아직 타지 않은 연료를 가방으로 꺼낸다. 가방에 다 안 들어가면 0
func withdraw(inv: Inventory, item_id: String, count: int) -> int:
	var have := 0
	for st in fuel:
		if st.id == item_id:
			have = int(st.count)
	var n := mini(count, have)
	if n <= 0 or not inv.can_add(item_id, n):
		return 0
	inv.add(item_id, n)
	_take(item_id, n)
	_changed()
	return n


# ---------- 발전

func on_time(minutes: float) -> void:
	produce(minutes)


func on_night_production(_w: FarmWorld, report: Dictionary, minutes: float) -> void:
	var made := produce(minutes)
	if made > 0.0:
		var night: Dictionary = report.get("night_production", {})
		night["energy"] = float(night.get("energy", 0.0)) + made
		report["night_production"] = night


## minutes 분 동안 발전한다. 만든 전기 양
func produce(minutes: float) -> float:
	var rate := output_per_hour() / 60.0
	if rate <= 0.0:
		return 0.0
	var left := minutes
	var made := 0.0
	var changed := false
	while left > 0.0001 and not is_full():
		if not is_burning():
			if not _light_next():
				break
			changed = true
		var step := minf(left, minf(burn_left, (storage() - energy) / rate))
		if step <= 0.0:
			break
		energy = minf(storage(), energy + step * rate)
		burn_left -= step
		left -= step
		made += step * rate
		if burn_left <= 0.0001:
			burning = ""
			burn_left = 0.0
			changed = true
	if changed:
		_changed()
	return made


## 다음 연료 하나에 불을 붙인다. 연료가 없으면 false
func _light_next() -> bool:
	if fuel.is_empty():
		return false
	var id: String = fuel[0].id
	_take(id, 1)
	burning = id
	burn_left = burn_minutes(id)
	return burn_left > 0.0


# ---------- 철거·저장

func contents() -> Array:
	return fuel.duplicate(true)


func take_contents() -> void:
	fuel.clear()
	_changed()


func save_state() -> Dictionary:
	# 소수는 0.001 단위로 저장 (JSON 을 거치며 생기는 아주 작은 오차로 불러온 값이 달라지지 않게)
	return {"fuel": fuel.duplicate(true), "burning": burning, "burn_left": snappedf(burn_left, 0.001), "energy": snappedf(energy, 0.001)}


func load_state(data: Dictionary) -> void:
	fuel.clear()
	var raw: Variant = data.get("fuel")
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary and typeof(entry.get("count")) in [TYPE_INT, TYPE_FLOAT] and accepts(ItemDB.get_item(str(entry.get("id", "")))) and int(entry.count) > 0:
				_add(str(entry.id), int(entry.count))
	burning = str(data.get("burning", "")) if burn_minutes(str(data.get("burning", ""))) > 0.0 else ""
	burn_left = clampf(float(data.get("burn_left", 0.0)), 0.0, burn_minutes(burning)) if burning != "" and typeof(data.get("burn_left")) in [TYPE_INT, TYPE_FLOAT] else 0.0
	if burn_left <= 0.0:
		burning = ""
	energy = clampf(float(data.get("energy", 0.0)), 0.0, storage()) if typeof(data.get("energy")) in [TYPE_INT, TYPE_FLOAT] else 0.0
	_changed()


func _add(item_id: String, n: int) -> void:
	for st in fuel:
		if st.id == item_id:
			st.count += n
			return
	fuel.append({"id": item_id, "count": n, "quality": Quality.NONE})


func _take(item_id: String, n: int) -> void:
	for i in fuel.size():
		if fuel[i].id == item_id:
			fuel[i].count -= n
			if fuel[i].count <= 0:
				fuel.remove_at(i)
			return


func _changed() -> void:
	Events.generator_changed.emit()
	Events.power_changed.emit()


## "나무 태우는 중 · 남은 40분" 같은 상태 글
func status_text() -> String:
	if is_full():
		return "전기 통이 가득 차서 쉬는 중 (연료를 아껴요)"
	if is_burning():
		return "%s 태우는 중 · 이 연료 남은 시간 %s" % [ItemDB.get_item(burning).name, RecipeDB.time_text(burn_left)]
	if not fuel.is_empty():
		return "곧 연료에 불을 붙여요"
	return "연료가 없어요. 식물 섬유나 나무를 넣어 주세요."


# ---------- [E] 상호작용

func _ready() -> void:
	super._ready()
	add_to_group("interactables")


func interact_point() -> Vector2:
	return global_position + Vector2(0, 7)


func can_interact(from: Vector2) -> bool:
	return from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	Events.generator_requested.emit(self)
