class_name DailySpecial
extends RefCounted
## 일일 특별 상품 (BUILD_FARM_PLAN §101). 후보는 data/shop_specials.json.
##   - 매일 아침(하루 마감의 shop_refresh 단계) 그날 계절에 맞는 후보 중 1개를 고른다. 가능하면 어제와 다른 것.
##   - 수량 제한 없음, 그날만. 오늘 상품은 GameState.daily_special 에 저장된다.
##   - 일반 씨앗·비료·시설의 무한 재고 판매는 그대로이고, 이건 상점에 따로 한 줄 더 붙는다.

const DATA_PATH := "res://data/shop_specials.json"

static var _data: Dictionary = {}


static func _candidates() -> Dictionary:
	if _data.is_empty():
		_data = DataFile.load_dict(DATA_PATH)
	return _data.get("candidates", {})


static func get_entry(id: String) -> Dictionary:
	var entry: Variant = _candidates().get(id, {})
	return entry if entry is Dictionary else {}


static func exists(id: String) -> bool:
	return not get_entry(id).is_empty()


static func name_of(id: String) -> String:
	return get_entry(id).get("name", id)


static func price_of(id: String) -> int:
	return int(get_entry(id).get("price", 0))


## {아이템 id: 개수} (데이터에 없는 아이템은 뺀다)
static func items_of(id: String) -> Dictionary:
	var out := {}
	var items: Variant = get_entry(id).get("items", {})
	if items is Dictionary:
		for item_id: String in items:
			if ItemDB.has_item(item_id) and int(items[item_id]) > 0:
				out[item_id] = int(items[item_id])
	return out


## 그날(계절) 고를 수 있는 후보 id 들
static func available_on(day: int) -> Array[String]:
	var season := Calendar.season_of(day)
	var result: Array[String] = []
	for id: String in _candidates():
		var seasons: Array = get_entry(id).get("seasons", [])
		if (seasons.is_empty() or season in seasons) and not items_of(id).is_empty():
			result.append(id)
	return result


## 그날 상품을 고른다. 어제(previous)와 다른 것을 우선한다. 후보가 없으면 "".
static func pick(day: int, rng: RandomNumberGenerator, previous := "") -> String:
	var pool := available_on(day)
	if pool.size() > 1 and previous in pool:
		pool.erase(previous)
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()]


## 따로 살 때 값 (상점에서 파는 아이템만 셈, 하나라도 상점 가격이 없으면 0 = 비교 안 함)
static func regular_price(id: String) -> int:
	var total := 0
	var items := items_of(id)
	for item_id: String in items:
		var item := ItemDB.get_item(item_id)
		if item.buy_price <= 0:
			return 0
		total += item.buy_price * int(items[item_id])
	return total


## "기본 비료 ×5 · 나무 ×20"
static func contents_text(id: String) -> String:
	var parts: Array[String] = []
	var items := items_of(id)
	for item_id: String in items:
		parts.append("%s ×%d" % [ItemDB.get_item(item_id).name, items[item_id]])
	return " · ".join(parts)


## 산다. 돈이 모자라거나 가방에 다 들어가지 않으면 아무것도 바꾸지 않는다. {"ok": bool, "reason": 이유}
static func buy(id: String, inv: Inventory) -> Dictionary:
	if not exists(id):
		return {"ok": false, "reason": "오늘은 특별 상품이 없어요."}
	var items := items_of(id)
	if not inv.can_add_all(items):
		return {"ok": false, "reason": "가방에 자리가 없어요."}
	if not GameState.try_spend(price_of(id)):
		return {"ok": false, "reason": "돈이 부족해요."}
	for item_id: String in items:
		inv.add(item_id, int(items[item_id]))
	return {"ok": true, "reason": ""}
