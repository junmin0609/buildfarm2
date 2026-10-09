class_name CompostBin
extends Placeable
## 퇴비통 (BUILD_FARM_PLAN §28). 건설 모드로 짓는 시설. 유기물을 넣어 두면 며칠 뒤 기본 비료가 된다.
## 수치는 placeables.json 의 "compost" (재료별 점수·한 번에 필요한 점수·걸리는 날·결과물·보관 한도).
##
## 흐름 (공장처럼 초 단위가 아니라 하루 단위)
##   1. [E] → 가방의 재료를 넣는다 → "대기 중" (아직 익히기 전이라 다시 꺼낼 수 있다)
##   2. 대기 중 점수가 batch_points 이상이면 바로 한 번 분량을 떼어 "익히는 중"이 된다 (이건 꺼낼 수 없다)
##   3. 하루 마감(farm_daily 단계)마다 하루씩 익고, batch_days 가 차면 결과물이 퇴비통 안에 쌓인다
##   4. 플레이어가 [E] 로 직접 꺼낸다. 가방에 들어가는 만큼만 꺼내고 나머지는 그대로 남는다
## 결과물이 max_output 까지 차 있으면 다 익은 퇴비는 기다린다 (아이템을 버리지 않음 §97, §105). 꺼내면 바로 채워진다.
## 철거하면 대기 중 재료·익히는 중 재료·결과물을 모두 가방으로 돌려준다. 자리가 없으면 철거를 막는다 (§106).
##
## 확장: 다른 유기물 처리 시설(바이오 연료 등)은 "compost" 같은 설정 묶음과 이 흐름(대기 → 익힘 → 결과)을 그대로 쓰면 된다.
## 컨베이어 (§55): 입구로 재료 1개씩 받고(대기 칸 한도까지), 출구로 결과물(기본 비료)을 1개씩 내보낸다.

const REACH := 14.0

var prompt := "[E] 퇴비통"
## 넣어 두고 아직 익히기 전인 재료 (칸 형식 {"id", "count", "quality"})
var waiting: Array[Dictionary] = []
## 지금 익히는 중인 한 번 분량의 재료
var batch: Array[Dictionary] = []
## 익히는 중인 분량이 지난 하루 마감 횟수
var batch_days := 0
## 다 만들어져 꺼내기를 기다리는 결과물 개수
var output := 0

var _icon: Sprite2D
var _bob := 0.0


# ---------- 설정

func config() -> Dictionary:
	var c: Variant = def.data.get("compost", {}) if def else {}
	return c if c is Dictionary else {}


## 재료 하나의 점수 (넣을 수 없는 아이템은 0)
func points_of(item_id: String) -> int:
	var inputs: Variant = config().get("inputs", {})
	return int(inputs.get(item_id, 0)) if inputs is Dictionary else 0


func accepts(item: ItemDef) -> bool:
	return item != null and points_of(item.id) > 0


func batch_points_needed() -> int:
	return maxi(1, int(config().get("batch_points", 10)))


func days_needed() -> int:
	return maxi(1, int(config().get("batch_days", 3)))


func output_item() -> ItemDef:
	return ItemDB.get_item(str(config().get("output", "basic_fertilizer")))


func output_per_batch() -> int:
	return maxi(1, int(config().get("output_count", 1)))


func max_output() -> int:
	return maxi(output_per_batch(), int(config().get("max_output", 30)))


func max_waiting_points() -> int:
	return maxi(batch_points_needed(), int(config().get("max_waiting_points", 50)))


# ---------- 상태

func waiting_points() -> int:
	return _points(waiting)


func is_working() -> bool:
	return not batch.is_empty()


## 다 익었지만 결과물 칸이 가득 차서 기다리는 중
func is_done() -> bool:
	return is_working() and batch_days >= days_needed()


func is_empty() -> bool:
	return waiting.is_empty() and batch.is_empty() and output == 0


func _points(stacks: Array[Dictionary]) -> int:
	var total := 0
	for st in stacks:
		total += points_of(st.id) * int(st.count)
	return total


# ---------- 넣기 / 꺼내기 (UI·테스트·나중의 자동 투입이 쓴다)

## 가방에서 재료 count 개를 넣는다. 대기 칸 한도를 넘지 않게 줄여 넣고, 실제로 넣은 개수를 돌려준다.
func deposit(inv: Inventory, item_id: String, quality: String, count: int) -> int:
	var item := ItemDB.get_item(item_id)
	if not accepts(item):
		return 0
	var q := Quality.normalize(item, quality)
	var room := (max_waiting_points() - waiting_points()) / points_of(item_id)
	var n := mini(mini(count, room), inv.count_of(item_id, q))
	if n <= 0 or not inv.remove(item_id, n, q):
		return 0
	_add(waiting, item_id, q, n)
	_try_start()
	_changed()
	return n


## 컨베이어 입구: 재료 1개를 받는다 (대기 칸 한도까지)
func accept_item(item_id: String, quality: String) -> bool:
	var item := ItemDB.get_item(item_id)
	if not accepts(item) or waiting_points() + points_of(item_id) > max_waiting_points():
		return false
	_add(waiting, item_id, Quality.normalize(item, quality), 1)
	_try_start()
	_changed()
	return true


## 컨베이어 출구: 결과물 1개를 꺼낸다
func provide_item() -> Dictionary:
	var item := output_item()
	if item == null or output <= 0:
		return {}
	output -= 1
	_try_finish()
	_try_start()
	_changed()
	return {"id": item.id, "quality": Quality.NONE}


## 넣어 둔(아직 익히기 전) 재료를 가방으로 꺼낸다. 가방에 다 안 들어가면 꺼내지 않고 0.
func withdraw(inv: Inventory, item_id: String, quality: String, count: int) -> int:
	var item := ItemDB.get_item(item_id)
	var q := Quality.normalize(item, quality)
	var n := mini(count, _count(waiting, item_id, q))
	if n <= 0 or not inv.can_add(item_id, n, q):
		return 0
	inv.add(item_id, n, q)
	_take(waiting, item_id, q, n)
	_changed()
	return n


## 결과물을 가방에 들어가는 만큼 꺼낸다. 꺼낸 개수를 돌려준다 (못 꺼낸 것은 퇴비통에 그대로).
func take_output(inv: Inventory) -> int:
	var item := output_item()
	if item == null or output <= 0:
		return 0
	var n := output
	while n > 0 and not inv.can_add(item.id, n):
		n -= 1
	if n <= 0:
		return 0
	inv.add(item.id, n)
	output -= n
	# 결과물 칸이 가득 차서 기다리던 퇴비가 있으면 바로 채운다
	_try_finish()
	_try_start()
	_changed()
	return n


## 대기 중 점수가 충분하고 익히는 중인 게 없으면, 앞에서부터 한 번 분량을 떼어 익히기 시작한다.
## 마지막 재료 점수가 남으면(9점 + 2점) 넘친 1점은 이번 분량에 함께 들어간다.
func _try_start() -> void:
	if is_working() or waiting_points() < batch_points_needed():
		return
	var need := batch_points_needed()
	var got := 0
	while got < need and not waiting.is_empty():
		var st: Dictionary = waiting[0]
		_add(batch, st.id, st.quality, 1)
		got += points_of(st.id)
		_take(waiting, st.id, st.quality, 1)
	batch_days = 0


## 다 익은 분량을 결과물로 바꾼다 (결과물 칸에 자리가 있을 때만). 만든 개수를 돌려준다.
func _try_finish() -> int:
	if not is_done() or output + output_per_batch() > max_output():
		return 0
	output += output_per_batch()
	batch.clear()
	batch_days = 0
	return output_per_batch()


## 하루 마감: 하루 익히고, 다 익으면 결과물로, 다음 분량이 있으면 이어서 시작한다.
## report.compost = 오늘 밤 만들어진 결과물 수 (여러 퇴비통 합계)
func on_day_end(_world: FarmWorld, report: Dictionary) -> void:
	if is_working() and not is_done():
		batch_days += 1
	var made := _try_finish()
	_try_start()
	if made > 0:
		report["compost"] = int(report.get("compost", 0)) + made
		if output_item():
			DayCycle.add_night_item(report, output_item().id, made)
	_changed()


# ---------- 철거·저장

func contents() -> Array:
	var out: Array = []
	for st in waiting + batch:
		out.append(st.duplicate())
	if output > 0 and output_item() != null:
		out.append({"id": output_item().id, "count": output, "quality": Quality.NONE})
	return out


func take_contents() -> void:
	waiting.clear()
	batch.clear()
	batch_days = 0
	output = 0
	_changed()


func save_state() -> Dictionary:
	return {"waiting": waiting.duplicate(true), "batch": batch.duplicate(true), "batch_days": batch_days, "output": output}


func load_state(data: Dictionary) -> void:
	waiting = _load_stacks(data.get("waiting"))
	batch = _load_stacks(data.get("batch"))
	batch_days = maxi(0, int(data.get("batch_days", 0))) if typeof(data.get("batch_days")) in [TYPE_INT, TYPE_FLOAT] else 0
	output = maxi(0, int(data.get("output", 0))) if typeof(data.get("output")) in [TYPE_INT, TYPE_FLOAT] else 0
	if batch.is_empty():
		batch_days = 0
	_changed()


## 저장된 재료 목록. 모양이 틀리거나 이제 넣을 수 없는 아이템은 건너뛴다.
func _load_stacks(data: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not data is Array:
		return out
	for entry: Variant in data:
		if not entry is Dictionary or typeof(entry.get("count")) not in [TYPE_INT, TYPE_FLOAT]:
			continue
		var item := ItemDB.get_item(str(entry.get("id", "")))
		if accepts(item) and int(entry.count) > 0:
			_add(out, item.id, Quality.normalize(item, str(entry.get("quality", ""))), int(entry.count))
	return out


# ---------- 칸 형식 목록 도우미

func _count(stacks: Array[Dictionary], item_id: String, quality: String) -> int:
	for st in stacks:
		if st.id == item_id and st.quality == quality:
			return int(st.count)
	return 0


func _add(stacks: Array[Dictionary], item_id: String, quality: String, n: int) -> void:
	for st in stacks:
		if st.id == item_id and st.quality == quality:
			st.count += n
			return
	stacks.append({"id": item_id, "count": n, "quality": quality})


func _take(stacks: Array[Dictionary], item_id: String, quality: String, n: int) -> void:
	for i in stacks.size():
		if stacks[i].id == item_id and stacks[i].quality == quality:
			stacks[i].count -= n
			if stacks[i].count <= 0:
				stacks.remove_at(i)
			return


func _changed() -> void:
	_update_icon()
	Events.compost_bin_changed.emit()


# ---------- [E] 상호작용 (Interactable 건물과 같은 이름)

func _ready() -> void:
	super._ready()
	add_to_group("interactables")
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
	Events.compost_bin_requested.emit(self)


## 결과물이 있으면 퇴비통 오른쪽 위에 비료 아이콘이 통통 튄다
func _update_icon() -> void:
	if _icon == null:
		return
	var item := output_item()
	_icon.visible = output > 0 and item != null
	if item:
		_icon.region_rect = Art.item_region(item)
	var tex := def.texture_for(turns)
	# 앞에 선 플레이어의 말풍선과 겹치지 않게 오른쪽 위에 띄운다
	_icon.position = Vector2(size().x * TILE / 2.0 - 6, -(tex.get_height() if tex else 16) - 4)


func _process(delta: float) -> void:
	if _icon and _icon.visible:
		_bob += delta
		_icon.offset.y = roundf(sin(_bob * 4.0) * 1.5)
