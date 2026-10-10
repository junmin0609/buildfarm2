class_name WateringCan
extends RefCounted
## 물뿌리개 (BUILD_FARM_PLAN §13). 물 한 번 = 물 1. 용량은 items.json 의 "capacity".
## 남은 물은 가방 칸에 "water" 로 저장된다 (도구마다 따로).
##
## 채우기 (§14): 물 공급원에서만 채운다. 지금은 우물(Well) 하나.
##   - 공급원 앞에서 [E] → refill_all (가방 속 물뿌리개 모두)
##   - 물뿌리개를 들고 공급원 칸을 클릭 → 그 물뿌리개만
## 물 공급원은 WATER_SOURCES 그룹의 노드로, covers_cell / provide_water / water_source_name 를 가진다 (Well 참고).
## 펌프·물탱크·자동 관개도 이 그룹에 들어오면 그대로 쓸 수 있다.
## 개울·연못에서 채우던 임시 방식은 우물이 생기면서 없앴다.

const WATER_SOURCES := "water_sources"


static func water_left(inv: Inventory, index: int) -> int:
	return int(inv.slot_value(index, "water", 0))


static func capacity_of(inv: Inventory, index: int) -> int:
	var item := inv.item_at(index)
	return item.capacity if item != null else 0


static func is_can(inv: Inventory, index: int) -> bool:
	var item := inv.item_at(index)
	return item != null and item.tool_type == "watering_can" and item.capacity > 0


## index 칸의 물뿌리개를 cell 에 쓴다. 무언가 했으면 true.
## 구리 이상 물뿌리개는 꾹 누른 단계(level)만큼 dir 쪽 여러 칸 (ItemDef.work_cells). 물 1 = 한 칸, 물이 떨어지면 거기까지
static func use(world: FarmWorld, cell: Vector2i, inv: Inventory, index: int, dir := Vector2i.DOWN, level := 1) -> bool:
	var source := water_source_at(world, cell)
	if source != null:
		var added := refill(inv, index, source)
		if added > 0:
			var full := water_left(inv, index) >= capacity_of(inv, index)
			Events.toast.emit("%s (%d/%d)" % ["물을 가득 채웠어요." if full else "%s에 물이 모자라 조금만 채웠어요." % source.water_source_name(), water_left(inv, index), capacity_of(inv, index)])
		elif water_left(inv, index) >= capacity_of(inv, index):
			Events.toast.emit("물뿌리개가 이미 가득 찼어요.")
		else:
			Events.toast.emit("%s에 물이 없어요." % source.water_source_name())
		return added > 0
	var item := inv.item_at(index)
	var cells: Array[Vector2i] = item.work_cells(cell, dir, level) if item else [cell]
	var need := cells.filter(func(c: Vector2i) -> bool:
		var t := world.farm.get_tile(c)
		return t != null and not t.watered)
	if need.is_empty():
		if world.farm.get_tile(cell) == null and MapLayout.char_at(cell) == "~":
			Events.toast.emit("물뿌리개는 우물이나 물탱크에서 채워요.")
		return false
	if water_left(inv, index) <= 0:
		Events.toast.emit("물이 없어요. 우물이나 물탱크에서 물뿌리개를 채워 주세요.")
		return false
	var done := 0
	for c: Vector2i in need:
		if water_left(inv, index) <= 0:
			break
		if world.farm.water(c):
			inv.set_slot_value(index, "water", water_left(inv, index) - 1)
			done += 1
	return done > 0


## index 칸의 물뿌리개를 source 에서 채운다. 실제로 채운 양을 돌려준다.
static func refill(inv: Inventory, index: int, source: Node) -> int:
	if not is_can(inv, index):
		return 0
	var need := capacity_of(inv, index) - water_left(inv, index)
	if need <= 0:
		return 0
	var got: int = source.provide_water(need)
	if got > 0:
		inv.set_slot_value(index, "water", water_left(inv, index) + got)
		Events.watering_can_refilled.emit(got)
	return got


## 가방 속 물뿌리개를 모두 채운다 (우물 앞 [E]). 안내 문구도 띄운다.
## 돌려주는 값: {"cans": 물뿌리개 수, "added": 채운 물 합계}
static func refill_all(inv: Inventory, source: Node) -> Dictionary:
	var cans := 0
	var added := 0
	for i in inv.size():
		if is_can(inv, i):
			cans += 1
			added += refill(inv, i, source)
	var all_full := true
	for i in inv.size():
		if is_can(inv, i) and water_left(inv, i) < capacity_of(inv, i):
			all_full = false
	if cans == 0:
		Events.toast.emit("물뿌리개가 없어요.")
	elif added == 0 and all_full:
		Events.toast.emit("물뿌리개가 이미 가득 찼어요.")
	elif added == 0:
		Events.toast.emit("%s에 물이 없어요." % source.water_source_name())
	elif all_full:
		Events.toast.emit("%s에서 물을 길어 물뿌리개를 가득 채웠어요." % source.water_source_name())
	else:
		Events.toast.emit("%s에 물이 모자라 물뿌리개를 조금만 채웠어요." % source.water_source_name())
	return {"cans": cans, "added": added}


## cell 에 있는 물 공급원 (없으면 null)
static func water_source_at(world: FarmWorld, cell: Vector2i) -> Node:
	for node in world.get_tree().get_nodes_in_group(WATER_SOURCES):
		if node.covers_cell(cell):
			return node
	return null
