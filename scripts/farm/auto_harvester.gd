class_name AutoHarvester
extends Placeable
## 자동 수확기 (BUILD_FARM_PLAN §66). 1칸짜리, 밭 사이에 놓는다.
## 범위(placeables.json "area": 하급 + 모양 4칸 / 중급 3x3 / 상급 5x5, FarmArea) 안 다 자란 작물을 하나씩 거둔다.
##
## 규칙
##   - 거둔 작물은 수확기 안에 쌓이고 출구(컨베이어 §55)로 1개씩 나간다. 창고로 순간이동하지 않는다 (§66)
##     출구에 벨트가 없으면 [E] 로 가방에 꺼낸다
##   - 한 번 거두는 데 게임 시계 minutes 분. 거두는 동안에만 지역 전기 통에서 시간당 power 를 꺼내 쓴다
##     (사용자 결정, 전기 가공기와 같은 규칙). 모자라면 꺼낸 만큼만 진행하고 멈췄다가 다시 차면 이어서
##   - 안에 자리가 없으면 거두지 않는다 — 작물은 밭에 그대로 남는다 (§105, 아이템 삭제 없음)
##   - 밤에도 야간 생산 시간만큼 일한다 (§97). 밤사이 다 자란 작물도 거둔다
## 수치는 placeables.json 의 "harvester" (minutes·power·max_output).

const REACH := 14.0
const NO_CELL := Vector2i(-99999, -99999)

var prompt := "[E] 자동 수확기 (거둔 것 꺼내기)"
## 거둬서 내보내기를 기다리는 작물 (칸 형식 배열)
var output: Array[Dictionary] = []
## 지금 거두는 작물에 들인 게임 분
var progress := 0.0
## 전기가 모자라 멈춘 상태
var starved := false

var _world: FarmWorld
var _icon: Sprite2D
var _bob := 0.0


func config() -> Dictionary:
	var c: Variant = def.data.get("harvester", {}) if def else {}
	return c if c is Dictionary else {}


func minutes_per_harvest() -> float:
	return maxf(1.0, float(config().get("minutes", 10)))


func power_use() -> int:
	return maxi(0, int(config().get("power", 30)))


func max_output() -> int:
	return maxi(1, int(config().get("max_output", 30)))


func area_cells() -> Array[Vector2i]:
	return FarmArea.cells(cell, def.data.get("area"))


func output_count() -> int:
	var n := 0
	for st in output:
		n += int(st.count)
	return n


## 범위 안 다 자란 작물 칸 (첫 번째). 없으면 NO_CELL
func next_target() -> Vector2i:
	if _world == null:
		return NO_CELL
	for c in area_cells():
		var tile := _world.farm.get_tile(c)
		if tile != null and tile.is_mature():
			return c
	return NO_CELL


## 지금 거둘 수 있는가 (거둘 작물이 있고 안에 자리가 있음)
func is_working() -> bool:
	return next_target() != NO_CELL and output_count() < max_output()


## 지금 쓰는 전기 (시간당). 거두는 동안에만 (사용자 결정)
func power_demand() -> int:
	return power_use() if is_working() else 0


# ---------- 거두기

func on_time(minutes: float) -> void:
	advance(minutes)


## 야간 생산 (§97): 밤에 거둔 작물도 아침 야간 생산 요약에 나온다
func on_night_production(_w: FarmWorld, report: Dictionary, minutes: float) -> void:
	for got in advance(minutes):
		DayCycle.add_night_item(report, got.id, int(got.count))


## 게임 시계 minutes 분만큼 일한다. 이번에 거둔 것 [{"id", "count", "quality"}]
func advance(minutes: float) -> Array[Dictionary]:
	var got: Array[Dictionary] = []
	if _world == null:
		return got
	var left := minutes
	var was_starved := starved
	while left > 0.0001:
		var target := next_target()
		if target == NO_CELL:
			progress = 0.0
			starved = false
			break
		if output_count() >= max_output():
			break  # 안이 가득 차서 기다린다 (작물은 밭에 그대로)
		var need := minutes_per_harvest() - progress
		if need > 0.0001:
			var step := minf(left, need)
			var want := power_use() / 60.0 * step
			var drawn := _world.build.draw_energy(want) if want > 0.0 else want
			var frac := 1.0 if want <= 0.0 else drawn / want
			progress += step * frac
			left -= step
			if frac < 0.999:
				starved = true
				break
			starved = false
			if progress < minutes_per_harvest() - 0.0001:
				break
		progress = minutes_per_harvest()
		var res := _world.farm.roll_harvest(target)
		if res.is_empty():
			progress = 0.0
			continue
		if output_count() + int(res.count) > max_output():
			break  # 이번 수확이 다 들어갈 자리가 없으면 밭에 둔다
		_world.farm.finish_harvest(target)
		_add(output, str(res.id), str(res.quality), int(res.count))
		GameState.discover(str(res.id))
		got.append(res)
		progress = 0.0
	if not got.is_empty() or was_starved != starved:
		_changed()
	return got


# ---------- 내보내기·꺼내기

## 컨베이어 출구 (§55): 1개씩 내보낸다
func provide_item() -> Dictionary:
	if output.is_empty():
		return {}
	var st: Dictionary = output[0]
	var it := {"id": st.id, "quality": st.quality}
	st.count -= 1
	if st.count <= 0:
		output.remove_at(0)
	_changed()
	return it


## 가방에 들어가는 만큼 꺼낸다. 꺼낸 개수 (못 꺼낸 것은 그대로)
func take_output(inv: Inventory) -> int:
	var taken := 0
	var kept: Array[Dictionary] = []
	for st in output:
		var left := inv.add(st.id, int(st.count), st.quality)
		taken += int(st.count) - left
		if left > 0:
			st.count = left
			kept.append(st)
	output = kept
	if taken > 0:
		_changed()
	return taken


func status_text() -> String:
	if starved:
		return "전기가 없어서 멈췄어요."
	if output_count() >= max_output():
		return "안이 가득 찼어요. 꺼내거나 출구에 컨베이어를 이어 주세요."
	if next_target() != NO_CELL:
		return "거두는 중"
	return "다 자란 작물을 기다리는 중"


# ---------- Placeable 훅

func on_placed(world: FarmWorld) -> void:
	_world = world


func on_removed(_w: FarmWorld) -> void:
	Events.power_changed.emit()


func contents() -> Array:
	return output.duplicate(true)


func take_contents() -> void:
	output.clear()
	progress = 0.0
	_changed()


func save_state() -> Dictionary:
	return {"output": output.duplicate(true), "progress": snappedf(progress, 0.001)} if not output.is_empty() or progress > 0.0 else {}


func load_state(data: Dictionary) -> void:
	output.clear()
	var raw: Variant = data.get("output")
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary and typeof(entry.get("count")) in [TYPE_INT, TYPE_FLOAT] and int(entry.count) > 0:
				var item := ItemDB.get_item(str(entry.get("id", "")))
				if item != null:
					_add(output, item.id, Quality.normalize(item, str(entry.get("quality", ""))), int(entry.count))
	progress = clampf(float(data.get("progress", 0.0)), 0.0, minutes_per_harvest()) if typeof(data.get("progress")) in [TYPE_INT, TYPE_FLOAT] else 0.0
	_changed()


func _add(stacks: Array[Dictionary], item_id: String, quality: String, n: int) -> void:
	for st in stacks:
		if st.id == item_id and st.quality == quality:
			st.count += n
			return
	stacks.append({"id": item_id, "count": n, "quality": quality})


func _changed() -> void:
	_update_icon()
	Events.power_changed.emit()


# ---------- [E] 상호작용 (Interactable 건물과 같은 이름)

func _ready() -> void:
	super._ready()
	add_to_group("interactables")
	_icon = Sprite2D.new()
	_icon.texture = Art.ITEMS
	_icon.region_enabled = true
	_icon.scale = Vector2(0.75, 0.75)
	_icon.z_index = 5
	add_child(_icon)
	_update_icon()


func interact_point() -> Vector2:
	return global_position + Vector2(0, 7)


func can_interact(from: Vector2) -> bool:
	return from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	if output.is_empty():
		Events.toast.emit("자동 수확기: %s" % status_text())
		return
	var n := take_output(GameState.inventory)
	Events.toast.emit("자동 수확기에서 %d개 꺼냈어요." % n if n > 0 else "가방에 자리가 없어요.")


## 거둔 게 있으면 그 작물 아이콘이 위에 통통 뜬다
func _update_icon() -> void:
	if _icon == null:
		return
	_icon.visible = not output.is_empty()
	if not output.is_empty():
		_icon.region_rect = Art.item_region(ItemDB.get_item(output[0].id))
	var tex := def.texture_for(turns)
	_icon.position = Vector2(0, -(tex.get_height() if tex else 16) - 5)


func _process(delta: float) -> void:
	if _icon and _icon.visible:
		_bob += delta
		_icon.offset.y = roundf(sin(_bob * 4.0) * 1.5)
