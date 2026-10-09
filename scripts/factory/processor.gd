class_name Processor
extends Placeable
## 가공기 (BUILD_FARM_PLAN §70~§74). 건설 모드로 짓는 시설. 레시피대로 재료를 가공품으로 바꾼다.
## 수치는 placeables.json 의 "processor" (등급·자동 여부·한 번에 정할 수 있는 횟수·결과물 보관 한도·전력).
##
## 두 종류 (사용자 결정)
##   수동 가공기 (automatic = false, 전기 없음) — 지금 있는 것
##     플레이어가 레시피와 횟수를 정해 [가공 시작] → 정한 횟수만 만들고 멈춘다. 다시 돌리려면 또 시작해야 한다.
##   전기 가공기 (automatic = true, 전력 사용) — 완전 자동 (사용자 결정)
##     플레이어는 레시피만 정하고 켠다. 맞닿은 창고에서 1회분 재료를 가져와 만들고, 결과물은 맞닿은 창고에 넣는다
##     (창고 필터를 지킴). 넣을 창고가 없으면 가공기 안에 쌓고, 그것도 가득 차면 멈춘다. 재료가 다시 생기면 저절로 이어서.
##     실제로 만드는 동안에만 지역 전기 통에서 시간당 power 만큼 꺼내 쓰고, 통이 비면 멈췄다가 다시 차면 이어서 (사용자 결정).
##     밤에는 야간 생산 5시간만큼 일한다 (§97).
##     컨베이어 (§55, 사용자 결정: 맞닿은 창고 방식과 함께 씀): 입구로 들어온 재료는 가공기 안 재료 칸(input)에 모아 두고
##     (레시피 재료만, 재료마다 input_runs 회분까지), 1회분을 꺼낼 때 맞닿은 창고보다 먼저 쓴다.
##     출구로는 가공기 안에 쌓인 결과물을 1개씩 내보낸다 (맞닿은 창고가 있으면 결과물은 먼저 창고로 간다).
##
## 수동 가공기 흐름
##   1. 시작할 때 정한 횟수만큼의 재료를 가방에서 한꺼번에 가져와 회차별로 넣어 둔다 (queue)
##      회차마다 쓸 재료 품질을 정하고(낮은 품질부터 / 높은 품질부터), 결과물 품질 = 그 회차 재료 품질의 평균 (§74)
##   2. 게임 시계가 흐르는 동안(BuildGrid → on_time) 진행. 시계가 멈추면(상점·창·건설) 같이 멈춘다
##   3. 1회분이 끝나면 결과물이 가공기 안에 쌓인다. 결과물 칸이 가득 차면(max_output) 다음 완성은 기다린다
##   4. 하루가 끝나면 진행 중인 1회분은 밤사이 마저 완성된다 (나머지 회차는 다음 날 이어서)
##   5. [취소] 하면 아직 안 만든 회차의 재료를 모두 돌려준다 (가방 자리가 없으면 취소 불가)
## 아이템은 사라지지 않는다 (§105). 철거하면 남은 재료·결과물을 모두 돌려주고, 자리가 없으면 철거를 막는다 (§106).

const REACH := 14.0

var prompt := "[E] 가공기"
## 지금(또는 마지막으로) 돌린 레시피 id
var recipe_id := ""
## 남은 회차들. 맨 앞이 지금 만드는 회차. {"inputs": 칸 형식 배열, "quality": 결과물 품질}
var queue: Array[Dictionary] = []
## 지금 회차가 진행된 게임 시계 분
var progress := 0.0
## 다 만들어져 꺼내기를 기다리는 결과물 (칸 형식 배열)
var output: Array[Dictionary] = []
## 전기 가공기: 컨베이어 입구로 들어와 쓰기를 기다리는 재료 (칸 형식 배열)
var input: Array[Dictionary] = []
## 이번에 시작할 때 정한 횟수 / 그중 끝난 횟수 (표시용)
var runs_total := 0
var runs_done := 0
## 전기 가공기: 켜져 있는가 (켜져 있으면 전력을 쓴다)
var enabled := false
## 전기 가공기: 전기가 모자라 멈춘 상태
var starved := false
## 재료를 높은 품질부터 쓰는가 (전기 가공기가 창고에서 가져올 때. 수동은 시작할 때 고른다)
var high_first := false

var _world: FarmWorld

var _icon: Sprite2D
var _bob := 0.0


# ---------- 설정

func config() -> Dictionary:
	var c: Variant = def.data.get("processor", {}) if def else {}
	return c if c is Dictionary else {}


func tier() -> int:
	return maxi(1, int(config().get("tier", 1)))


func is_automatic() -> bool:
	return bool(config().get("automatic", false))


## 빠르기 (§70 중급: 2배). 레시피 시간을 이 값으로 나눈다
func speed() -> float:
	return maxf(0.1, float(config().get("speed", 1.0)))


func max_runs() -> int:
	return maxi(1, int(config().get("max_runs", 99)))


func max_output() -> int:
	return maxi(1, int(config().get("max_output", 30)))


## 컨베이어로 받아 둘 수 있는 재료 양 (재료마다 이 회분까지)
func input_runs() -> int:
	return maxi(1, int(config().get("input_runs", 2)))


## 켜져 있을 때 쓰는 전력 (§75)
func power_use() -> int:
	return maxi(0, int(config().get("power", 0)))


## 지금 쓰는 전기 (시간당). 실제로 만드는 동안에만 쓴다 (사용자 결정) — 쉬거나 재료·자리를 기다리면 0
func power_demand() -> int:
	if not is_automatic() or not enabled or queue.is_empty() or recipe().is_empty():
		return 0
	return power_use() if progress < float(recipe().minutes) else 0


## 지금 레시피 (이 가공기 빠르기로 걸리는 시간을 맞춘 사본)
func recipe() -> Dictionary:
	return recipe_for(recipe_id)


func recipe_for(id: String) -> Dictionary:
	var r := RecipeDB.get_recipe(id)
	if r.is_empty() or is_equal_approx(speed(), 1.0):
		return r
	r = r.duplicate()
	r.minutes = float(r.minutes) / speed()
	return r


## 이 가공기에서 쓸 수 있는 레시피인가 (배웠고, 등급이 맞음). 못 쓰면 이유, 쓸 수 있으면 ""
func recipe_problem(id: String) -> String:
	var r := RecipeDB.get_recipe(id)
	if r.is_empty():
		return "없는 레시피예요."
	if not RecipeDB.is_known(id):
		return "아직 배우지 않은 레시피예요."
	if int(r.tier) > tier():
		return "더 좋은 가공기가 필요해요."
	return ""


# ---------- 상태

func is_working() -> bool:
	return not queue.is_empty()


## 다 됐지만 결과물 칸이 가득 차서 기다리는 중
func is_waiting() -> bool:
	return is_working() and not recipe().is_empty() and progress >= float(recipe().minutes) and not _has_room(int(recipe().count))


func minutes_left() -> float:
	return maxf(0.0, float(recipe().minutes) - progress) if is_working() and not recipe().is_empty() else 0.0


func output_count() -> int:
	var n := 0
	for st in output:
		n += int(st.count)
	return n


func is_empty() -> bool:
	return queue.is_empty() and output.is_empty() and input.is_empty()


func _has_room(n: int) -> bool:
	return output_count() + n <= max_output()


## 가방 재료로 이 레시피를 몇 번 돌릴 수 있는지 (max_runs 까지)
static func runs_possible(inv: Inventory, r: Dictionary, limit: int) -> int:
	if r.is_empty():
		return 0
	var n := limit
	for item_id: String in r.inputs:
		n = mini(n, int(inv.count_of(item_id, RecipeDB.need_quality(r, item_id)) / float(int(r.inputs[item_id]))))
	return maxi(0, n)


# ---------- 시작 / 취소 / 꺼내기 (UI·테스트가 쓴다)

## 레시피 id 를 runs 번 돌리기 시작한다. 재료가 모자라면 가능한 만큼만. 실제로 정한 횟수를 돌려준다 (못 하면 0).
## high_first: true 면 높은 품질 재료부터 쓴다 (기본은 낮은 품질부터 — 좋은 재료는 따로 팔 수 있게)
func start(inv: Inventory, id: String, runs: int, use_high_first := false) -> int:
	if is_automatic() or is_working() or recipe_problem(id) != "":
		return 0
	var r := RecipeDB.get_recipe(id)
	var n := mini(runs, runs_possible(inv, r, max_runs()))
	if n <= 0:
		return 0
	var out_item := ItemDB.get_item(r.output)
	# 재료를 빼는 동안 창이 새로 그려지므로, 회차 목록은 다 만든 뒤에 한 번에 넣는다
	var runs_list: Array[Dictionary] = []
	for i in n:
		var stacks: Array[Dictionary] = []
		var counts := {}
		for item_id: String in r.inputs:
			var need := int(r.inputs[item_id])
			for q in _quality_order(ItemDB.get_item(item_id), use_high_first, RecipeDB.need_quality(r, item_id)):
				var take := mini(need, inv.count_of(item_id, q))
				if take <= 0:
					continue
				inv.remove(item_id, take, q)
				_add(stacks, item_id, q, take)
				counts[q] = int(counts.get(q, 0)) + take
				need -= take
				if need == 0:
					break
		runs_list.append({"inputs": stacks, "quality": Quality.normalize(out_item, Quality.average(counts))})
	queue = runs_list
	recipe_id = id
	progress = 0.0
	runs_total = n
	runs_done = 0
	_changed()
	return n


## 재료를 꺼낼 품질 순서. only 가 있으면 그 품질만 (§73-9 고급잼: 골드 과일만)
static func _quality_order(item: ItemDef, high_quality_first: bool, only: Variant = null) -> Array[String]:
	if item == null or not item.has_quality:
		return [Quality.NONE]
	if only != null:
		return [str(only)]
	var order := Quality.ids().duplicate()
	if high_quality_first:
		order.reverse()
	return order


## 남은 회차를 모두 취소하고 그 재료를 가방에 돌려준다. 가방에 다 안 들어가면 취소하지 않고 false.
func cancel(inv: Inventory) -> bool:
	if not is_working():
		return false
	var back := _queued_inputs()
	if not inv.can_add_stacks(back):
		return false
	for st in back:
		inv.add(st.id, int(st.count), st.quality)
	queue.clear()
	progress = 0.0
	runs_total = runs_done
	_changed()
	return true


## 결과물을 가방에 들어가는 만큼 꺼낸다. 꺼낸 개수 (못 꺼낸 것은 가공기에 그대로)
func take_output(inv: Inventory) -> int:
	var taken := 0
	var kept: Array[Dictionary] = []
	for st in output:
		var left := inv.add(st.id, int(st.count), st.quality)
		taken += int(st.count) - left
		st.count = left
		if left > 0:
			kept.append(st)
	output = kept
	if taken > 0:
		advance(0.0)  # 결과물 칸이 가득 차서 기다리던 회차가 있으면 바로 채운다
		_changed()
	return taken


# ---------- 진행

## 게임 시계 minutes 분만큼 진행한다 (Events.time_advanced). 이번에 끝난 회차 수를 돌려준다.
func advance(minutes: float) -> int:
	if is_automatic():
		return _advance_auto(minutes)
	var r := recipe()
	if queue.is_empty() or r.is_empty():
		return 0
	progress += minutes
	var made := 0
	while not queue.is_empty() and progress >= float(r.minutes):
		if not _has_room(int(r.count)):
			progress = float(r.minutes)  # 꺼낼 때까지 기다린다
			break
		_finish_one(r)
		progress -= float(r.minutes)
		made += 1
	if queue.is_empty():
		progress = 0.0
	if made > 0:
		_changed()
	return made


func _finish_one(r: Dictionary) -> void:
	var run: Dictionary = queue.pop_front()
	_add(output, r.output, run.quality, int(r.count))
	GameState.discover(r.output)  # 처음 만든 가공품도 "얻은 것" (다음 레시피 재료가 될 수 있음 §71)
	if not is_automatic():
		runs_done += 1  # 정한 횟수 중 몇 번째인지는 수동 가공기에만 의미가 있다


## 하루 마감 (farm_daily 단계): 수동 가공기는 진행 중인 1회분을 밤사이 마저 완성한다 (결과물 칸에 자리가 있을 때).
## report.processed = 오늘 밤 완성된 결과물 수 (여러 가공기 합계). 전기 가공기는 night_production 단계에서 일한다.
func on_day_end(_w: FarmWorld, report: Dictionary) -> void:
	var r := recipe()
	if is_automatic() or queue.is_empty() or r.is_empty() or not _has_room(int(r.count)):
		return
	_finish_one(r)
	progress = 0.0
	report["processed"] = int(report.get("processed", 0)) + int(r.count)
	DayCycle.add_night_item(report, r.output, int(r.count))
	_changed()


# ---------- 전기 가공기 (완전 자동)

## 전기 가공기가 지금 일할 수 없는 이유 ("" 이면 일할 수 있음): 꺼짐 / 레시피 없음 / 전력 부족
func auto_problem() -> String:
	if not is_automatic():
		return ""
	if recipe_id == "" or recipe_problem(recipe_id) != "":
		return "레시피를 정해 주세요."
	if not enabled:
		return "꺼져 있어요."
	return ""


## 레시피를 정한다. 만들던 회차가 있으면 그 재료를 맞닿은 창고(없으면 가공기 안 결과물 칸)로 돌려놓고 바꾼다.
## 돌려놓을 자리가 없으면 바꾸지 않고 false.
func set_recipe(id: String) -> bool:
	if not is_automatic() or recipe_problem(id) != "":
		return false
	if id == recipe_id:
		return true
	if not queue.is_empty() or not input.is_empty():
		var back := _queued_inputs()
		for st in input:
			_add(back, st.id, st.quality, int(st.count))
		var room := max_output() - output_count()
		var total := 0
		for st in back:
			total += int(st.count)
		if total > room + _warehouse_room(back):
			return false
		for st in back:
			var left := _store(st.id, int(st.count), st.quality)
			if left > 0:
				_add(output, st.id, st.quality, left)
		queue.clear()
		input.clear()
	recipe_id = id
	progress = 0.0
	if enabled and auto_problem() == "":
		_advance_auto(0.0)
	_changed()
	return true


func set_enabled(on: bool) -> bool:
	if not is_automatic() or (on and (recipe_id == "" or recipe_problem(recipe_id) != "")):
		return false
	enabled = on
	Events.power_changed.emit()
	_changed()
	if on:
		_advance_auto(0.0)
	return true


func set_high_first(on: bool) -> void:
	high_first = on
	_changed()


## 맞닿은 창고들 (재료를 가져오고 결과물을 넣는 곳)
func warehouses() -> Array[Warehouse]:
	var out: Array[Warehouse] = []
	if _world == null:
		return out
	for obj in neighbors(_world.build):
		if obj is Warehouse:
			out.append(obj)
	return out


## 이 가공기가 있는 지역의 전력 상태 {"supply", "demand", "ok"}
func region_power() -> Dictionary:
	return _world.build.power_status() if _world else {"stored": 0.0, "capacity": 0.0, "output": 0, "demand": 0}


func available_in_warehouses(item_id: String, quality: Variant = null) -> int:
	return _available(item_id, quality)


## 맞닿은 창고들 + 컨베이어로 받아 둔 재료 칸에 있는 아이템 개수 (quality null = 모든 품질)
func _available(item_id: String, quality: Variant = null) -> int:
	var n := _input_count(item_id, quality)
	for wh in warehouses():
		n += wh.storage.count_of(item_id, quality)
	return n


func _input_count(item_id: String, quality: Variant = null) -> int:
	var n := 0
	for st in input:
		if st.id == item_id and (quality == null or st.quality == quality):
			n += int(st.count)
	return n


## 컨베이어로 받아 둔 재료 칸에서 꺼낸다. 꺼낸 개수
func _take_input(item_id: String, quality: String, n: int) -> int:
	for i in input.size():
		if input[i].id == item_id and input[i].quality == quality:
			var take := mini(n, int(input[i].count))
			input[i].count -= take
			if input[i].count <= 0:
				input.remove_at(i)
			return take
	return 0


## 컨베이어 입구 (§55): 지금 레시피의 재료만, 재료마다 input_runs 회분까지 받는다
func accept_item(item_id: String, quality: String) -> bool:
	if not is_automatic() or recipe_id == "" or recipe_problem(recipe_id) != "":
		return false
	var r := recipe()
	if not r.inputs.has(item_id):
		return false
	var q := Quality.normalize(ItemDB.get_item(item_id), quality)
	var need_q: Variant = RecipeDB.need_quality(r, item_id)
	if need_q != null and q != need_q:
		return false  # 품질이 정해진 재료 (골드만)
	if _input_count(item_id, need_q) >= int(r.inputs[item_id]) * input_runs():
		return false
	_add(input, item_id, q, 1)
	_changed()
	return true


## 컨베이어 출구: 가공기 안에 쌓인 결과물을 1개 내보낸다
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


## 받아 둔 재료 칸 → 맞닿은 창고 순서로 1회분 재료를 가져와 회차를 시작한다. 하나라도 모자라면 아무것도 가져오지 않고 false.
func _pull_run(r: Dictionary) -> bool:
	for item_id: String in r.inputs:
		if _available(item_id, RecipeDB.need_quality(r, item_id)) < int(r.inputs[item_id]):
			return false
	var stacks: Array[Dictionary] = []
	var counts := {}
	for item_id: String in r.inputs:
		var need := int(r.inputs[item_id])
		for q in _quality_order(ItemDB.get_item(item_id), high_first, RecipeDB.need_quality(r, item_id)):
			var from_input := _take_input(item_id, q, need)
			if from_input > 0:
				_add(stacks, item_id, q, from_input)
				counts[q] = int(counts.get(q, 0)) + from_input
				need -= from_input
				if need == 0:
					break
			for wh in warehouses():
				var take := mini(need, wh.storage.count_of(item_id, q))
				if take <= 0:
					continue
				wh.storage.remove(item_id, take, q)
				_add(stacks, item_id, q, take)
				counts[q] = int(counts.get(q, 0)) + take
				need -= take
				if need == 0:
					break
			if need == 0:
				break
	queue = [{"inputs": stacks, "quality": Quality.normalize(ItemDB.get_item(r.output), Quality.average(counts))}] as Array[Dictionary]
	progress = 0.0
	return true


## 맞닿은 창고들에 넣는다 (필터 지킴). 못 넣은 개수
func _store(item_id: String, count: int, quality: String) -> int:
	var left := count
	for wh in warehouses():
		if left <= 0:
			break
		left = wh.insert(item_id, left, quality)
	return left


## 맞닿은 창고들에 이 묶음이 몇 개 더 들어갈 수 있는지 (대략: 넣어 보고 되돌리지 않고 복사본으로 센다)
func _warehouse_room(stacks: Array) -> int:
	var room := 0
	for wh in warehouses():
		var trial := Inventory.new(wh.storage.size())
		trial.slots = wh.storage.slots.duplicate(true)
		for st: Dictionary in stacks:
			if wh.accepts(ItemDB.get_item(st.id)):
				room += int(st.count) - trial.add(st.id, int(st.count), st.quality)
	return room


## 가공기 안에 쌓인 결과물을 맞닿은 창고로 옮긴다
func _flush_output() -> void:
	if output.is_empty():
		return
	var kept: Array[Dictionary] = []
	var moved := false
	for st in output:
		var left := _store(st.id, int(st.count), st.quality)
		moved = moved or left < int(st.count)
		if left > 0:
			st.count = left
			kept.append(st)
	output = kept
	if moved:
		_changed()


func _advance_auto(minutes: float) -> int:
	if auto_problem() != "":
		return 0
	var r := recipe()
	_flush_output()
	var made := 0
	var left := minutes
	while true:
		if queue.is_empty() and not _pull_run(r):
			break
		var need := float(r.minutes) - progress
		if need > 0.0001:
			var step := minf(left, need)
			if step <= 0.0:
				break
			# 일하는 동안에만 지역 전기 통에서 꺼내 쓴다. 모자라면 꺼낸 만큼만 진행하고 멈춘다
			var want := power_use() / 60.0 * step
			var got := _world.build.draw_energy(want) if want > 0.0 and _world else want
			var frac := 1.0 if want <= 0.0 else got / want
			progress += step * frac
			left -= step
			if frac < 0.999:
				if not starved:
					starved = true
					_changed()
				break
			starved = false
			if progress < float(r.minutes) - 0.0001:
				break
		progress = float(r.minutes)
		if not _has_room(int(r.count)):
			break  # 결과물을 넣을 곳이 없어 기다린다
		_finish_one(r)
		progress = 0.0
		made += 1
		_flush_output()
	if made > 0:
		_changed()
	return made


## 야간 생산 (§97): 야간 시간만큼 자동으로 일한다. report.night_production.processed = 만든 결과물 수
func on_night_production(_w: FarmWorld, report: Dictionary, minutes: float) -> void:
	if not is_automatic():
		return
	var made := _advance_auto(minutes)
	if made > 0:
		var night: Dictionary = report.get("night_production", {})
		night["processed"] = int(night.get("processed", 0)) + made * int(recipe().count)
		report["night_production"] = night
		DayCycle.add_night_item(report, recipe().output, made * int(recipe().count))


## 입구 칸 앞에 이 가공기를 가리키는 컨베이어가 있는가
func _has_input_belt() -> bool:
	if _world == null:
		return false
	for p in ports():
		var belt := _world.build.object_at(p.outside) as Conveyor
		if p.type == "in" and belt != null and belt.facing() == -p.dir:
			return true
	return false


## 전기 가공기 상태 글 (창·테스트용)
func auto_status() -> String:
	var problem := auto_problem()
	if problem != "":
		return problem
	var r := recipe()
	var out_name := ItemDB.get_item(r.output).name
	if warehouses().is_empty() and queue.is_empty() and input.is_empty() and not _has_input_belt():
		return "재료가 들어올 곳이 없어요. 창고 옆에 짓거나 입구에 컨베이어를 이어 주세요."
	if queue.is_empty():
		return "재료를 기다리는 중 (%s)" % RecipeDB.inputs_text(r)
	if progress >= float(r.minutes) and not _has_room(int(r.count)):
		return "%s 완성! 결과물을 넣을 곳이 없어 기다리는 중" % out_name
	if starved:
		return "전기가 없어서 멈췄어요. 발전기에 연료를 넣어 주세요."
	return "%s 만드는 중 · 남은 시간 %s" % [out_name, RecipeDB.time_text(minutes_left())]


# ---------- 철거·저장

func _queued_inputs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for run in queue:
		for st: Dictionary in run.inputs:
			_add(out, st.id, st.quality, int(st.count))
	return out


func contents() -> Array:
	var out: Array = []
	for st in _queued_inputs() + output + input:
		out.append(st.duplicate())
	return out


func take_contents() -> void:
	queue.clear()
	output.clear()
	input.clear()
	progress = 0.0
	_changed()


func save_state() -> Dictionary:
	return {"recipe": recipe_id, "queue": queue.duplicate(true), "progress": snappedf(progress, 0.001), "output": output.duplicate(true),
			"input": input.duplicate(true), "runs_total": runs_total, "runs_done": runs_done, "enabled": enabled, "high_first": high_first}


func load_state(data: Dictionary) -> void:
	recipe_id = str(data.get("recipe", "")) if RecipeDB.has(str(data.get("recipe", ""))) else ""
	queue.clear()
	var raw_queue: Variant = data.get("queue")
	if raw_queue is Array and recipe_id != "":
		var out_item := ItemDB.get_item(recipe().output)
		for run: Variant in raw_queue:
			if run is Dictionary:
				var stacks := _load_stacks(run.get("inputs"))
				if not stacks.is_empty():
					queue.append({"inputs": stacks, "quality": Quality.normalize(out_item, str(run.get("quality", "")))})
	output = _load_stacks(data.get("output"))
	input = _load_stacks(data.get("input")) if is_automatic() else ([] as Array[Dictionary])
	progress = maxf(0.0, float(data.get("progress", 0.0))) if typeof(data.get("progress")) in [TYPE_INT, TYPE_FLOAT] and not queue.is_empty() else 0.0
	runs_total = maxi(0, int(data.get("runs_total", 0))) if typeof(data.get("runs_total")) in [TYPE_INT, TYPE_FLOAT] else 0
	runs_done = clampi(int(data.get("runs_done", 0)), 0, runs_total) if typeof(data.get("runs_done")) in [TYPE_INT, TYPE_FLOAT] else 0
	enabled = is_automatic() and recipe_id != "" and data.get("enabled") == true
	high_first = data.get("high_first") == true
	Events.power_changed.emit()
	_changed()


## 저장된 칸 목록. 모양이 틀리거나 없어진 아이템은 건너뛴다.
func _load_stacks(data: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not data is Array:
		return out
	for entry: Variant in data:
		if not entry is Dictionary or typeof(entry.get("count")) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var item := ItemDB.get_item(str(entry.get("id", "")))
		if item != null and int(entry.count) > 0:
			_add(out, item.id, Quality.normalize(item, str(entry.get("quality", ""))), int(entry.count))
	return out


func _add(stacks: Array[Dictionary], item_id: String, quality: String, n: int) -> void:
	for st in stacks:
		if st.id == item_id and st.quality == quality:
			st.count += n
			return
	stacks.append({"id": item_id, "count": n, "quality": quality})


func _changed() -> void:
	_update_icon()
	Events.processor_changed.emit()


# ---------- [E] 상호작용 (Interactable 건물과 같은 이름)

## 게임 시계가 흐름 (BuildGrid 가 발전기 다음에 부른다)
func on_time(minutes: float) -> void:
	advance(minutes)


func on_placed(world: FarmWorld) -> void:
	_world = world


func on_removed(_w: FarmWorld) -> void:
	enabled = false
	Events.power_changed.emit()


func _ready() -> void:
	super._ready()
	add_to_group("interactables")
	_icon = Sprite2D.new()
	_icon.texture = Art.ITEMS
	_icon.region_enabled = true
	_icon.scale = Vector2.ONE * Art.TILE / Art.ICON
	_icon.z_index = 5
	add_child(_icon)
	_update_icon()


func interact_point() -> Vector2:
	return global_position + Vector2(0, 7)


func can_interact(from: Vector2) -> bool:
	return from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	Events.processor_requested.emit(self)


## 결과물이 있으면 그 아이콘이 통통 튀고, 만드는 중이면 만들 물건 아이콘이 흐리게 떠 있다
func _update_icon() -> void:
	if _icon == null:
		return
	var item: ItemDef = null
	if not output.is_empty():
		item = ItemDB.get_item(output[0].id)
	elif is_working() and not recipe().is_empty():
		item = ItemDB.get_item(recipe().output)
	_icon.visible = item != null
	_icon.modulate.a = 1.0 if not output.is_empty() else 0.55
	if item:
		_icon.region_rect = Art.item_region(item)
	var tex := def.texture_for(turns)
	# 앞에 선 플레이어의 말풍선과 겹치지 않게 오른쪽 위에 띄운다
	_icon.position = Vector2(size().x * TILE / 2.0 - 6, -(tex.get_height() if tex else 16) - 4)


func _process(delta: float) -> void:
	if _icon and _icon.visible and not output.is_empty():
		_bob += delta
		_icon.offset.y = roundf(sin(_bob * 4.0) * 1.5)
	elif _icon:
		_icon.offset.y = 0
