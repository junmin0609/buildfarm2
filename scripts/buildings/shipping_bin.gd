class_name ShippingBin
extends Interactable
## 농장 출하함 (BUILD_FARM_PLAN §83). 안정적인 기본 판매 수단.
##   - 낮 동안 판매할 수 있는 아이템을 넣고, 하루가 끝나기 전까지 다시 꺼낼 수 있다
##   - 하루 마감의 판매 정산 단계(DayCycle.SETTLE_SALES)에서 기준가 100% × 품질 배율로 팔린다
## 아이템은 사라지지 않는다 (§105): 넣을 때는 가방에서 정확히 옮기고, 꺼낼 때 가방 자리가 없으면 꺼내지 않는다.
## 내용물 형식은 가방 칸과 같다: {"id", "count", "quality"}

const CHANNEL := Pricing.SHIPPING_BIN

var contents: Array[Dictionary] = []


func _init() -> void:
	size_tiles = Vector2i(2, 1)
	solid_height = 12.0
	door_x = 16.0
	prompt = "[E] 출하함 (하루가 끝나면 판매)"


func interact(_player: Node) -> void:
	Events.shipping_bin_requested.emit(self)


## 출하함에 넣을 수 있는 아이템 (판매가가 있는 것)
static func accepts(item: ItemDef) -> bool:
	return item != null and item.is_sellable()


func count_of(item_id: String, quality: String) -> int:
	var i := _find(item_id, quality)
	return contents[i].count if i >= 0 else 0


func is_empty() -> bool:
	return contents.is_empty()


## 가방에서 count 개를 넣는다. 실제로 넣은 개수를 돌려준다.
func deposit(inv: Inventory, item_id: String, quality: String, count: int) -> int:
	var item := ItemDB.get_item(item_id)
	if not accepts(item):
		return 0
	var q := Quality.normalize(item, quality)
	var n := mini(count, inv.count_of(item_id, q))
	if n <= 0 or not inv.remove(item_id, n, q):
		return 0
	_add(item_id, q, n)
	return n


## 출하함에서 count 개를 가방으로 꺼낸다. 가방에 다 들어갈 자리가 없으면 꺼내지 않고 0.
func withdraw(inv: Inventory, item_id: String, quality: String, count: int) -> int:
	var item := ItemDB.get_item(item_id)
	var q := Quality.normalize(item, quality)
	var n := mini(count, count_of(item_id, q))
	if n <= 0 or not inv.can_add(item_id, n, q):
		return 0
	inv.add(item_id, n, q)
	_take(item_id, q, n)
	return n


## 오늘 밤 받을 돈 (기준가 100% × 품질 배율)
func pending_value() -> int:
	var total := 0
	for entry in contents:
		total += Pricing.unit_price(ItemDB.get_item(entry.id), entry.quality, CHANNEL) * int(entry.count)
	return total


## 하루 마감 때: 전부 팔고 돈을 받는다. 돌려주는 값: {"total": G, "items": [{"id", "quality", "count", "amount"}]}
func settle() -> Dictionary:
	var items := []
	var total := 0
	for entry in contents:
		var amount := Pricing.unit_price(ItemDB.get_item(entry.id), entry.quality, CHANNEL) * int(entry.count)
		items.append({"id": entry.id, "quality": entry.quality, "count": entry.count, "amount": amount})
		total += amount
		Events.item_shipped.emit(str(entry.id), int(entry.count))
	contents.clear()
	if total > 0:
		GameState.add_money(total)
		GameState.record_sale(CHANNEL, total)
	Events.shipping_bin_changed.emit()
	return {"total": total, "items": items}


func _find(item_id: String, quality: String) -> int:
	for i in contents.size():
		if contents[i].id == item_id and contents[i].quality == quality:
			return i
	return -1


func _add(item_id: String, quality: String, n: int) -> void:
	var i := _find(item_id, quality)
	if i >= 0:
		contents[i].count += n
	else:
		contents.append({"id": item_id, "count": n, "quality": quality})
	Events.shipping_bin_changed.emit()


func _take(item_id: String, quality: String, n: int) -> void:
	var i := _find(item_id, quality)
	if i < 0:
		return
	contents[i].count -= n
	if contents[i].count <= 0:
		contents.remove_at(i)
	Events.shipping_bin_changed.emit()


# ---------- 저장용

func to_data() -> Dictionary:
	return {"contents": contents.duplicate(true)}


func load_data(data: Variant) -> bool:
	if not data is Dictionary or not data.get("contents") is Array:
		return false
	contents.clear()
	for entry: Variant in data.contents:
		if not entry is Dictionary:
			continue
		var item := ItemDB.get_item(str(entry.get("id", "")))
		var count := int(entry.get("count", 0)) if typeof(entry.get("count")) in [TYPE_INT, TYPE_FLOAT] else 0
		if accepts(item) and count > 0:
			var q := Quality.normalize(item, str(entry.get("quality", "")))
			var i := _find(item.id, q)
			if i >= 0:
				contents[i].count += count
			else:
				contents.append({"id": item.id, "count": count, "quality": q})
	Events.shipping_bin_changed.emit()
	return true
