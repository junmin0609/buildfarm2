class_name WateringCan
extends RefCounted
## 물뿌리개 (BUILD_FARM_PLAN §13). 물 한 번 = 물 1. 용량은 items.json 의 "capacity".
## 남은 물은 가방 칸에 "water" 로 저장된다 (도구마다 따로).
## 물이 떨어지면 물가(물 칸)를 향해 쓰면 가득 찬다. (우물이 생기면 우물에서도 채우게 한다 §14)


static func water_left(inv: Inventory, index: int) -> int:
	return int(inv.slot_value(index, "water", 0))


static func capacity_of(inv: Inventory, index: int) -> int:
	var item := inv.item_at(index)
	return item.capacity if item != null else 0


## index 칸의 물뿌리개를 cell 에 쓴다. 무언가 했으면 true.
static func use(world: FarmWorld, cell: Vector2i, inv: Inventory, index: int) -> bool:
	var cap := capacity_of(inv, index)
	if is_water_source(cell):
		if water_left(inv, index) >= cap:
			Events.toast.emit("물뿌리개가 이미 가득 찼어요.")
			return false
		inv.set_slot_value(index, "water", cap)
		Events.toast.emit("물을 가득 채웠어요. (%d/%d)" % [cap, cap])
		return true
	var tile := world.farm.get_tile(cell)
	if tile == null or tile.watered:
		return false
	if water_left(inv, index) <= 0:
		Events.toast.emit("물이 없어요. 물가에서 물뿌리개를 채워 주세요.")
		return false
	if not world.farm.water(cell):
		return false
	inv.set_slot_value(index, "water", water_left(inv, index) - 1)
	return true


## 물을 채울 수 있는 칸 (지금은 개울·연못)
static func is_water_source(cell: Vector2i) -> bool:
	return MapLayout.char_at(cell) == "~"
