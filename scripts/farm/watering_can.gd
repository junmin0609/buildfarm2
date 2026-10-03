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
static func use(world: FarmWorld, cell: Vector2i, inv: Inventory, index: int) -> bool:
	var source := water_source_at(world, cell)
	if source != null:
		var added := refill(inv, index, source)
		if added > 0:
			Events.toast.emit("물을 가득 채웠어요. (%d/%d)" % [water_left(inv, index), capacity_of(inv, index)])
		else:
			Events.toast.emit("물뿌리개가 이미 가득 찼어요.")
		return added > 0
	var tile := world.farm.get_tile(cell)
	if tile == null:
		if MapLayout.char_at(cell) == "~":
			Events.toast.emit("물뿌리개는 우물에서 채워요.")
		return false
	if tile.watered:
		return false
	if water_left(inv, index) <= 0:
		Events.toast.emit("물이 없어요. 우물에서 물뿌리개를 채워 주세요.")
		return false
	if not world.farm.water(cell):
		return false
	inv.set_slot_value(index, "water", water_left(inv, index) - 1)
	return true


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
	if cans == 0:
		Events.toast.emit("물뿌리개가 없어요.")
	elif added == 0:
		Events.toast.emit("물뿌리개가 이미 가득 찼어요.")
	else:
		Events.toast.emit("%s에서 물을 길어 물뿌리개를 가득 채웠어요." % source.water_source_name())
	return {"cans": cans, "added": added}


## cell 에 있는 물 공급원 (없으면 null)
static func water_source_at(world: FarmWorld, cell: Vector2i) -> Node:
	for node in world.get_tree().get_nodes_in_group(WATER_SOURCES):
		if node.covers_cell(cell):
			return node
	return null
