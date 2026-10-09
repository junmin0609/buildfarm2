class_name SkyMarket
extends RefCounted
## 하늘시장 (BUILD_FARM_PLAN §84~§89). 수치는 data/sky_market.json.
##
## 규칙
##   - 오래된 비행선 정류장(광장)을 복구해야 열린다 (사용자 결정, §89). 복구 = 돈 + 재료를 한 번에 납품
##   - 그날 가격은 하루 처음 볼 때 한 번 정해지고 그날은 고정, 다음 날 예보 없음 (§85). GameState.sky_market 에 저장
##   - 그날 가격 = 기준가 × 분류 흐름 × 아이템 흔들림 × 이벤트 → 그다음 품질 배율 (Pricing.price_from)
##     분류마다 흔들림이 다르다: 곡물·채소는 안정, 가공품은 더, 특수 작물은 크게 (§86). 분류 단위로 함께 움직인다 (§87)
##   - 가끔 이벤트 (§88): 하늘 음식 축제(과일·채소↑) / 곡물 풍년(곡물↓) / 고급 음식 유행(가공품↑)
##   - 직접 가서 가방에 든 것만 판다 (§90). 원격 시세·원격 출하·자동 판매(§91~§93)는 아직 없다
## 판매 요약에는 판매 방식 "sky_market" 으로 들어간다 (economy.json).

const DATA_PATH := "res://data/sky_market.json"
const CHANNEL := "sky_market"
const UNLOCK := "sky_station"

static var _data: Dictionary = {}
## 테스트에서 시세를 고정하려면 시드를 넣은 RNG 로 바꾼다
static var rng := RandomNumberGenerator.new()


static func data() -> Dictionary:
	if _data.is_empty():
		_data = DataFile.load_dict(DATA_PATH)
		rng.randomize()
	return _data


static func categories() -> Dictionary:
	var c: Variant = data().get("categories", {})
	return c if c is Dictionary else {}


## 아이템의 분류 id ("" 이면 하늘시장에서 팔지 않음)
static func category_of(item: ItemDef) -> String:
	if item == null or not item.is_sellable():
		return ""
	var cats := categories()
	for cat: String in cats:
		var c: Dictionary = cats[cat]
		if item.id in c.get("items", []):
			return cat
	for cat: String in cats:
		var kind_name := str(cats[cat].get("kind", ""))
		if kind_name != "" and ItemDef.KIND_BY_NAME.get(kind_name, -1) == item.kind:
			return cat
	return ""


static func category_name(cat: String) -> String:
	return str(categories().get(cat, {}).get("name", cat))


# ---------- 열림 (§89 정류장 복구)

static func is_open() -> bool:
	return GameState.unlocks.get(UNLOCK, false)


## {"price": G, "materials": {아이템 id: 개수}}
static func station_cost() -> Dictionary:
	var s: Variant = data().get("station", {})
	var mats := {}
	if s is Dictionary and s.get("materials") is Dictionary:
		for id: String in s.materials:
			mats[id] = int(s.materials[id])
	return {"price": int(s.get("price", 0)) if s is Dictionary else 0, "materials": mats}


## 복구할 수 없는 이유. 할 수 있으면 ""
static func restore_problem(inv: Inventory) -> String:
	if is_open():
		return "이미 복구했어요."
	var cost := station_cost()
	if GameState.money < int(cost.price):
		return "돈이 부족해요. (%d G 필요)" % cost.price
	for id: String in cost.materials:
		if inv.count_of(id) < int(cost.materials[id]):
			return "%s이(가) 부족해요. (%d개 필요)" % [ItemDB.get_item(id).name, cost.materials[id]]
	return ""


## 돈·재료를 내고 정류장을 복구한다 → 하늘시장이 열린다
static func restore(inv: Inventory) -> bool:
	if restore_problem(inv) != "":
		return false
	var cost := station_cost()
	if not GameState.try_spend(int(cost.price)):
		return false
	for id: String in cost.materials:
		inv.remove(id, int(cost.materials[id]))
	GameState.unlocks[UNLOCK] = true
	return true


static func travel_minutes() -> float:
	return maxf(0.0, float(data().get("travel_minutes", 60)))


# ---------- 그날 시세 (§85~§88)

## 오늘 시세 {"day", "categories": {분류: 배율}, "items": {id: 배율}, "event": id}. 오늘 것이 없으면 지금 정한다
static func today() -> Dictionary:
	var s: Dictionary = GameState.sky_market
	if int(s.get("day", -1)) != GameState.day:
		GameState.sky_market = roll(GameState.day)
	return GameState.sky_market


## day 의 시세를 새로 정한다
static func roll(day: int) -> Dictionary:
	var d := data()
	var cats := categories()
	var spread := float(d.get("item_spread", 0.5))
	var lo := float(d.get("min_multiplier", 0.5))
	var hi := float(d.get("max_multiplier", 2.0))
	var event := ""
	var events: Variant = d.get("events", {})
	if events is Dictionary and not events.is_empty() and rng.randf() < float(d.get("event_chance", 0.12)):
		var ids: Array = events.keys()
		event = str(ids[rng.randi() % ids.size()])
	var effects: Dictionary = events.get(event, {}).get("effects", {}) if event != "" else {}
	var cat_mult := {}
	for cat: String in cats:
		var v := float(cats[cat].get("volatility", 0.15))
		cat_mult[cat] = snappedf(clampf((1.0 + rng.randf_range(-v, v)) * float(effects.get(cat, 1.0)), lo, hi), 0.01)
	var items := {}
	for item_id in _market_items():
		var cat := category_of(ItemDB.get_item(item_id))
		var v := float(cats[cat].get("volatility", 0.15)) * spread
		items[item_id] = snappedf(clampf(float(cat_mult[cat]) * (1.0 + rng.randf_range(-v, v)), lo, hi), 0.01)
	return {"day": day, "categories": cat_mult, "items": items, "event": event}


static func _market_items() -> Array[String]:
	var out: Array[String] = []
	for item: ItemDef in _all_items():
		if category_of(item) != "":
			out.append(item.id)
	return out


static func _all_items() -> Array:
	var out := []
	for id: String in DataFile.load_dict(ItemDB.DATA_PATH):
		if ItemDB.has_item(id):
			out.append(ItemDB.get_item(id))
	return out


## 오늘 이 아이템의 배율 (팔지 않는 아이템은 0)
static func multiplier(item: ItemDef) -> float:
	if category_of(item) == "":
		return 0.0
	return float(today().items.get(item.id, today().categories.get(category_of(item), 1.0)))


## 오늘 개당 판매가 (품질 반영). 기준가를 먼저 오늘 배율로 반올림한 뒤 품질 배율 (광장 판매와 같은 반올림 순서)
static func unit_price(item: ItemDef, quality: String) -> int:
	var m := multiplier(item)
	if m <= 0.0:
		return 0
	return Pricing.price_from(roundi(item.sell_price * m), item, quality)


static func event_info() -> Dictionary:
	var id := str(today().get("event", ""))
	return data().get("events", {}).get(id, {}) if id != "" else {}


## "▲ 12%" / "▼ 8%" / "-" (기준가 대비)
static func change_text(mult: float) -> String:
	var pct := roundi((mult - 1.0) * 100.0)
	if pct > 0:
		return "▲ %d%%" % pct
	if pct < 0:
		return "▼ %d%%" % -pct
	return "-"
