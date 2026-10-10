class_name ToolUpgrade
extends RefCounted
## 대장간 도구 강화 (BUILD_FARM_PLAN §43). 강화 경로·가격·재료는 items.json 도구의 "upgrade".
##   "upgrade": {"to": "hoe_2", "price": 400, "materials": {"stone": 15, "wood": 10}}
## 강화는 즉시 끝난다. 가방 칸의 도구가 다음 단계 아이템으로 바뀌고, 칸 자리와 물뿌리개의 물은 그대로다
## (물은 새 용량을 넘지 않게). 돈과 재료는 모두 확인한 뒤에만 쓴다.


## 다음 단계 아이템 (없으면 null = 최고 단계)
static func next_of(item: ItemDef) -> ItemDef:
	if item == null or item.upgrade.is_empty():
		return null
	return ItemDB.get_item(str(item.upgrade.get("to", "")))


static func price_of(item: ItemDef) -> int:
	return int(item.upgrade.get("price", 0))


static func materials_of(item: ItemDef) -> Dictionary:
	var m: Variant = item.upgrade.get("materials", {})
	return m if m is Dictionary else {}


## 강화할 수 있는지. {"ok": bool, "reason": 안 되는 이유}
static func check(inv: Inventory, index: int) -> Dictionary:
	var item := inv.item_at(index)
	var next := next_of(item)
	if next == null:
		return {"ok": false, "reason": "더 강화할 수 없어요."}
	var lock := QuestManager.tech_lock_reason_now("tool_upgrade")
	if lock != "":
		return {"ok": false, "reason": "도구 강화는 " + lock}
	if GameState.money < price_of(item):
		return {"ok": false, "reason": "돈이 부족해요. (%d G 필요)" % price_of(item)}
	var mats := materials_of(item)
	for mat_id: String in mats:
		if inv.count_of(mat_id) < int(mats[mat_id]):
			var mat := ItemDB.get_item(mat_id)
			return {"ok": false, "reason": "%s이(가) 부족해요. (%d개 필요)" % [mat.name if mat else mat_id, int(mats[mat_id])]}
	return {"ok": true, "reason": ""}


## 강화한다. 성공하면 true.
static func apply(inv: Inventory, index: int) -> bool:
	if not check(inv, index).ok:
		return false
	var item := inv.item_at(index)
	var next := next_of(item)
	var mats := materials_of(item)
	if not GameState.try_spend(price_of(item)):
		return false
	for mat_id: String in mats:
		inv.remove(mat_id, int(mats[mat_id]))
	var slot: Dictionary = inv.get_slot(index)
	slot["id"] = next.id
	slot["quality"] = Quality.normalize(next, "")
	if next.capacity > 0:
		slot["water"] = mini(int(slot.get("water", next.capacity)), next.capacity)
	else:
		slot.erase("water")
	inv.changed.emit()
	return true


## 가방에서 강화할 수 있는(또는 최고 단계인) 도구 칸 목록. 같은 도구는 한 번만.
static func tool_slots(inv: Inventory) -> Array[int]:
	var result: Array[int] = []
	var seen := {}
	for i in inv.size():
		var item := inv.item_at(i)
		if item != null and item.kind == ItemDef.Kind.TOOL and not seen.has(item.id):
			seen[item.id] = true
			result.append(i)
	return result
