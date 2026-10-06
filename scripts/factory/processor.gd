class_name Processor
extends Placeable
## 가공기 (BUILD_FARM_PLAN §70~§74). 건설 모드로 짓는 시설. 레시피대로 재료를 가공품으로 바꾼다.
## 수치는 placeables.json 의 "processor" (등급·자동 여부·한 번에 정할 수 있는 횟수·결과물 보관 한도·전력).
##
## 두 종류 (사용자 결정)
##   수동 가공기 (automatic = false, 전기 없음) — 지금 있는 것
##     플레이어가 레시피와 횟수를 정해 [가공 시작] → 정한 횟수만 만들고 멈춘다. 다시 돌리려면 또 시작해야 한다.
##   전기 가공기 (automatic = true, 전력 사용) — 발전기·전력 시스템과 함께 만들 예정
##     같은 흐름에 "재료가 들어오면 계속 돌리기"와 입출력 포트가 붙는다.
##
## 흐름
##   1. 시작할 때 정한 횟수만큼의 재료를 가방에서 한꺼번에 가져와 회차별로 넣어 둔다 (queue)
##      회차마다 쓸 재료 품질을 정하고(낮은 품질부터 / 높은 품질부터), 결과물 품질 = 그 회차 재료 품질의 평균 (§74)
##   2. 게임 시계가 흐르는 동안(Events.time_advanced) 진행. 시계가 멈추면(상점·창·건설) 같이 멈춘다
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
## 이번에 시작할 때 정한 횟수 / 그중 끝난 횟수 (표시용)
var runs_total := 0
var runs_done := 0

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


func max_runs() -> int:
	return maxi(1, int(config().get("max_runs", 99)))


func max_output() -> int:
	return maxi(1, int(config().get("max_output", 30)))


func recipe() -> Dictionary:
	return RecipeDB.get_recipe(recipe_id)


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
	return queue.is_empty() and output.is_empty()


func _has_room(n: int) -> bool:
	return output_count() + n <= max_output()


## 가방 재료로 이 레시피를 몇 번 돌릴 수 있는지 (max_runs 까지)
static func runs_possible(inv: Inventory, r: Dictionary, limit: int) -> int:
	if r.is_empty():
		return 0
	var n := limit
	for item_id: String in r.inputs:
		n = mini(n, inv.count_of(item_id) / int(r.inputs[item_id]))
	return maxi(0, n)


# ---------- 시작 / 취소 / 꺼내기 (UI·테스트가 쓴다)

## 레시피 id 를 runs 번 돌리기 시작한다. 재료가 모자라면 가능한 만큼만. 실제로 정한 횟수를 돌려준다 (못 하면 0).
## high_first: true 면 높은 품질 재료부터 쓴다 (기본은 낮은 품질부터 — 좋은 재료는 따로 팔 수 있게)
func start(inv: Inventory, id: String, runs: int, high_first := false) -> int:
	if is_working() or recipe_problem(id) != "":
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
			for q in _quality_order(ItemDB.get_item(item_id), high_first):
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


static func _quality_order(item: ItemDef, high_first: bool) -> Array[String]:
	if item == null or not item.has_quality:
		return [Quality.NONE]
	var order := Quality.ids().duplicate()
	if high_first:
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
	runs_done += 1


## 하루 마감 (farm_daily 단계): 진행 중인 1회분은 밤사이 마저 완성한다 (결과물 칸에 자리가 있을 때).
## report.processed = 오늘 밤 완성된 결과물 수 (여러 가공기 합계)
func on_day_end(_world: FarmWorld, report: Dictionary) -> void:
	var r := recipe()
	if queue.is_empty() or r.is_empty() or not _has_room(int(r.count)):
		return
	_finish_one(r)
	progress = 0.0
	report["processed"] = int(report.get("processed", 0)) + int(r.count)
	_changed()


# ---------- 철거·저장

func _queued_inputs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for run in queue:
		for st: Dictionary in run.inputs:
			_add(out, st.id, st.quality, int(st.count))
	return out


func contents() -> Array:
	var out: Array = []
	for st in _queued_inputs() + output:
		out.append(st.duplicate())
	return out


func take_contents() -> void:
	queue.clear()
	output.clear()
	progress = 0.0
	_changed()


func save_state() -> Dictionary:
	return {"recipe": recipe_id, "queue": queue.duplicate(true), "progress": progress, "output": output.duplicate(true),
			"runs_total": runs_total, "runs_done": runs_done}


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
	progress = maxf(0.0, float(data.get("progress", 0.0))) if typeof(data.get("progress")) in [TYPE_INT, TYPE_FLOAT] and not queue.is_empty() else 0.0
	runs_total = maxi(0, int(data.get("runs_total", 0))) if typeof(data.get("runs_total")) in [TYPE_INT, TYPE_FLOAT] else 0
	runs_done = clampi(int(data.get("runs_done", 0)), 0, runs_total) if typeof(data.get("runs_done")) in [TYPE_INT, TYPE_FLOAT] else 0
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

func _ready() -> void:
	super._ready()
	add_to_group("interactables")
	Events.time_advanced.connect(advance)
	_icon = Sprite2D.new()
	_icon.texture = Art.ITEMS
	_icon.region_enabled = true
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
