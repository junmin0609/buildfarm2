class_name Inventory
extends RefCounted
## 칸(slot) 단위 인벤토리. 앞의 HOTBAR_SIZE 칸이 핫바다.
## 각 칸은 비어 있으면 null, 아니면 {"id": String, "count": int, "quality": String}.
##   quality: 품질이 있는 아이템(작물)은 "bronze"/"silver"/"gold", 나머지는 Quality.NONE("")
##   같은 id 라도 quality 가 다르면 다른 스택이다 (potato+bronze, potato+silver 는 따로 쌓임).
##   도구 칸에는 상태가 더 붙을 수 있다. 예) 물뿌리개 {"water": 남은 물}
## 창고·출하함 같은 다른 보관함도 같은 칸 형식을 쓰면 그대로 옮겨 담을 수 있다.

signal changed

const SIZE := 27
const HOTBAR_SIZE := 9

var slots: Array = []


func _init(slot_count: int = SIZE) -> void:
	slots.resize(slot_count)


func size() -> int:
	return slots.size()


func get_slot(index: int) -> Variant:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func item_at(index: int) -> ItemDef:
	var slot: Variant = get_slot(index)
	return ItemDB.get_item(slot["id"]) if slot != null else null


func quality_at(index: int) -> String:
	var slot: Variant = get_slot(index)
	return slot.get("quality", Quality.NONE) if slot != null else Quality.NONE


## 칸에 붙은 상태 값 (물뿌리개의 "water" 등)
func slot_value(index: int, key: String, default: Variant = null) -> Variant:
	var slot: Variant = get_slot(index)
	return slot.get(key, default) if slot != null else default


func set_slot_value(index: int, key: String, value: Variant) -> void:
	var slot: Variant = get_slot(index)
	if slot == null:
		return
	slot[key] = value
	changed.emit()


## 아이템을 넣는다. 넣지 못하고 남은 개수를 돌려준다 (0이면 전부 들어감).
## quality 를 비우면 품질 있는 아이템은 기본 품질(브론즈)로 들어간다.
func add(item_id: String, count: int = 1, quality: String = Quality.NONE) -> int:
	var item := ItemDB.get_item(item_id)
	if item == null or count <= 0:
		return count
	var q := Quality.normalize(item, quality)
	var remaining := count
	# 1) 같은 아이템·같은 품질 칸에 먼저 채운다
	for i in slots.size():
		if remaining == 0:
			break
		var slot: Variant = slots[i]
		if _same_stack(slot, item_id, q) and slot["count"] < item.max_stack:
			var moved := mini(remaining, item.max_stack - slot["count"])
			slot["count"] += moved
			remaining -= moved
	# 2) 남으면 빈 칸에 넣는다
	for i in slots.size():
		if remaining == 0:
			break
		if slots[i] == null:
			var moved := mini(remaining, item.max_stack)
			var slot := {"id": item_id, "count": moved, "quality": q}
			slot.merge(item.new_slot_state())
			slots[i] = slot
			remaining -= moved
	if remaining != count:
		changed.emit()
	return remaining


## 전부 들어갈 자리가 있는지 미리 확인한다.
func can_add(item_id: String, count: int = 1, quality: String = Quality.NONE) -> bool:
	var item := ItemDB.get_item(item_id)
	if item == null:
		return false
	var q := Quality.normalize(item, quality)
	var room := 0
	for slot: Variant in slots:
		if slot == null:
			room += item.max_stack
		elif _same_stack(slot, item_id, q):
			room += item.max_stack - slot["count"]
		if room >= count:
			return true
	return false


## 칸 형식 묶음({"id", "count", "quality"} 배열)이 품질까지 그대로 한꺼번에 다 들어가는지
func can_add_stacks(incoming: Array) -> bool:
	var trial := Inventory.new(slots.size())
	trial.slots = slots.duplicate(true)
	for st: Dictionary in incoming:
		if trial.add(str(st.get("id", "")), int(st.get("count", 0)), str(st.get("quality", Quality.NONE))) > 0:
			return false
	return true


## 여러 아이템이 한꺼번에 다 들어가는지 ({아이템 id: 개수}). 복사본에 넣어 보고 판단한다.
func can_add_all(items: Dictionary) -> bool:
	var trial := Inventory.new(slots.size())
	trial.slots = slots.duplicate(true)
	for item_id: String in items:
		if trial.add(item_id, int(items[item_id])) > 0:
			return false
	return true


## 칸 하나를 상태(물뿌리개의 남은 물 등)까지 그대로 넣는다. 넣지 못하고 남은 개수를 돌려준다.
## 상태가 붙는 아이템은 빈 칸에 통째로 들어가고, 나머지는 add 와 같다 (같은 스택에 먼저 채움).
func put_slot(slot: Dictionary) -> int:
	var item := ItemDB.get_item(str(slot.get("id", "")))
	var count := int(slot.get("count", 0))
	if item == null or count <= 0:
		return count
	if item.new_slot_state().is_empty():
		return add(item.id, count, str(slot.get("quality", Quality.NONE)))
	var i := slots.find(null)
	if i < 0:
		return count
	slots[i] = slot.duplicate(true)
	changed.emit()
	return 0


## 칸 수를 늘린다 (창고 증축). 줄이지는 않는다 (안의 물건이 사라지지 않게).
func grow(new_size: int) -> void:
	if new_size > slots.size():
		slots.resize(new_size)
		changed.emit()


## 빈 칸 수
func free_slots() -> int:
	return slots.count(null)


func remove_at(index: int, count: int = 1) -> void:
	var slot: Variant = get_slot(index)
	if slot == null:
		return
	slot["count"] -= count
	if slot["count"] <= 0:
		slots[index] = null
	changed.emit()


## 여러 칸에 걸쳐 id 아이템을 count개 뺀다. 모자라면 아무것도 빼지 않고 false.
## quality 가 null 이면 품질을 가리지 않고, 값이 있으면 그 품질 스택에서만 뺀다.
func remove(item_id: String, count: int = 1, quality: Variant = null) -> bool:
	if count_of(item_id, quality) < count:
		return false
	var q: Variant = _wanted_quality(item_id, quality)
	var remaining := count
	for i in range(slots.size() - 1, -1, -1):
		var slot: Variant = slots[i]
		if remaining > 0 and _matches(slot, item_id, q):
			var taken := mini(remaining, slot["count"])
			slot["count"] -= taken
			remaining -= taken
			if slot["count"] <= 0:
				slots[i] = null
	changed.emit()
	return true


## quality 가 null 이면 모든 품질을 합친 개수
func count_of(item_id: String, quality: Variant = null) -> int:
	var q: Variant = _wanted_quality(item_id, quality)
	var total := 0
	for slot: Variant in slots:
		if _matches(slot, item_id, q):
			total += slot["count"]
	return total


## 가방에 든 (id, quality) 조합들. 가방 순서대로, 겹치지 않게. 판매 목록 등에 쓴다.
func stacks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen := {}
	for slot: Variant in slots:
		if slot == null:
			continue
		var key := "%s|%s" % [slot["id"], slot.get("quality", Quality.NONE)]
		if seen.has(key):
			continue
		seen[key] = true
		result.append({"id": slot["id"], "quality": slot.get("quality", Quality.NONE)})
	return result


## 칸 from 의 물건을 칸 to 로 옮긴다 (끌어다 놓기).
##   같은 아이템·같은 품질이면 to 에 합친다 (넘치는 만큼은 from 에 남음). 그 밖에는 두 칸을 바꾼다.
##   품질이 다르면 합치지 않는다 (다른 스택).
func move(from: int, to: int) -> void:
	if from == to or get_slot(from) == null or to < 0 or to >= slots.size():
		return
	var a: Dictionary = slots[from]
	var b: Variant = slots[to]
	var item := ItemDB.get_item(a["id"])
	if b != null and _same_stack(b, a["id"], a.get("quality", Quality.NONE)) and b["count"] < item.max_stack:
		var moved := mini(a["count"], item.max_stack - b["count"])
		b["count"] += moved
		a["count"] -= moved
		if a["count"] <= 0:
			slots[from] = null
		changed.emit()
		return
	swap(from, to)


func swap(a: int, b: int) -> void:
	if a == b:
		return
	var tmp: Variant = slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	changed.emit()


func _same_stack(slot: Variant, item_id: String, quality: String) -> bool:
	return slot != null and slot["id"] == item_id and slot.get("quality", Quality.NONE) == quality


func _matches(slot: Variant, item_id: String, quality: Variant) -> bool:
	if slot == null or slot["id"] != item_id:
		return false
	return quality == null or slot.get("quality", Quality.NONE) == quality


func _wanted_quality(item_id: String, quality: Variant) -> Variant:
	if quality == null:
		return null
	return Quality.normalize(ItemDB.get_item(item_id), quality)


## 저장용
func to_data() -> Array:
	return slots.duplicate(true)


## 칸 수는 지금 크기 그대로 둔다 (가방은 SIZE, 창고는 단계별 칸 수). 넘치는 저장 칸은 건너뛴다.
func load_data(data: Array) -> void:
	slots.fill(null)
	for i in mini(data.size(), slots.size()):
		var slot: Variant = data[i]
		if not (slot is Dictionary) or not ItemDB.has_item(str(slot.get("id", ""))):
			continue
		var item := ItemDB.get_item(str(slot["id"]))
		var count := int(slot.get("count", 1)) if typeof(slot.get("count", 1)) in [TYPE_INT, TYPE_FLOAT] else 1
		if count <= 0:
			continue
		var loaded: Dictionary = slot.duplicate(true)
		loaded["id"] = item.id
		loaded["count"] = mini(count, item.max_stack)
		loaded["quality"] = Quality.normalize(item, str(slot.get("quality", "")))
		for key: String in item.new_slot_state():
			if not loaded.has(key):
				loaded[key] = item.new_slot_state()[key]
			else:
				loaded[key] = int(loaded[key])  # JSON 숫자는 float 로 읽힌다
		slots[i] = loaded
	changed.emit()
