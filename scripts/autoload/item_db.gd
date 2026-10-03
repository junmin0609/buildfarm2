extends Node
## 모든 아이템 정의를 data/items.json 에서 읽어 들고 있는 저장소.
## 새 작물·도구는 JSON에 항목만 추가하면 된다.

const DATA_PATH := "res://data/items.json"

var _items: Dictionary = {}  # id -> ItemDef


func _init() -> void:
	_load_items()


func _load_items() -> void:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("아이템 데이터를 열 수 없습니다: %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("아이템 데이터 형식이 잘못됐습니다: %s" % DATA_PATH)
		return
	for item_id: String in parsed:
		_items[item_id] = ItemDef.from_dict(item_id, parsed[item_id])


func get_item(item_id: String) -> ItemDef:
	return _items.get(item_id)


func has_item(item_id: String) -> bool:
	return _items.has(item_id)


## 상점에서 파는 아이템 (구매가가 있는 것). 종류별(씨앗 → 비료 ...)로 묶고 그 안에서 싼 것부터
func shop_items() -> Array[ItemDef]:
	var result: Array[ItemDef] = []
	for item: ItemDef in _items.values():
		if item.buy_price > 0:
			result.append(item)
	result.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		if a.kind != b.kind:
			return _shop_order(a.kind) < _shop_order(b.kind)
		return a.buy_price < b.buy_price)
	return result


static func _shop_order(kind: ItemDef.Kind) -> int:
	return [ItemDef.Kind.SEED, ItemDef.Kind.FERTILIZER].find(kind) if kind in [ItemDef.Kind.SEED, ItemDef.Kind.FERTILIZER] else 99
