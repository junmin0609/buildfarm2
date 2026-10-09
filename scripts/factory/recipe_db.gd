class_name RecipeDB
extends RefCounted
## 가공 레시피 저장소 (BUILD_FARM_PLAN §71~§73). data/recipes.json 을 처음 쓸 때 한 번 읽는다.
##
## 레시피 한 개 (사전):
##   id       레시피 id (같은 결과물을 다른 재료로 만드는 변형은 id 가 다르다. 예: fruit_syrup_strawberry)
##   inputs   1회분 재료 {아이템 id: 개수}
##   output   결과물 아이템 id, count = 1회분 결과물 개수
##   minutes  1회분에 걸리는 게임 시계 분
##   tier     필요한 가공기 등급 (§70: 1 하급 / 2 중급 / 3 상급)
##   unlocked 처음부터 아는 레시피인가. 나머지는 배워야 쓴다 (§71, 한 번 배우면 영구)
##   price    레시피 상점(셰프, §71)에서 배우는 값 (처음부터 아는 레시피는 0)
##   quality  품질이 정해진 재료 {아이템 id: "gold"} (§73-9 고급잼: 골드 과일만). 없으면 아무 품질이나
## 배운 레시피는 GameState.unlocks["recipe:<id>"] 에 저장된다.
##
## 레시피 상점 (사용자 결정: 주재료를 처음 얻으면 진열)
##   재료를 모두 한 번씩 얻어 본(GameState.has_found) 레시피만 살 수 있다. 한 번 진열되면 그 뒤로 계속 진열.
##   아직 못 얻은 재료가 있으면 "???" 로 보이고 얻은 재료만 알려 준다.

const DATA_PATH := "res://data/recipes.json"

static var _recipes: Dictionary = {}  # id -> 사전
static var _order: Array[String] = []


static func _ensure_loaded() -> void:
	if not _recipes.is_empty():
		return
	var data := DataFile.load_dict(DATA_PATH)
	for id: String in data:
		var raw: Variant = data[id]
		if id.begins_with("_") or not raw is Dictionary:
			continue
		var inputs := {}
		var raw_inputs: Variant = raw.get("inputs", {})
		if raw_inputs is Dictionary:
			for item_id: String in raw_inputs:
				if ItemDB.has_item(item_id) and int(raw_inputs[item_id]) > 0:
					inputs[item_id] = int(raw_inputs[item_id])
		var output := str(raw.get("output", ""))
		if inputs.is_empty() or not ItemDB.has_item(output):
			push_error("레시피를 읽지 못했습니다: %s" % id)
			continue
		_recipes[id] = {
			"id": id,
			"inputs": inputs,
			"output": output,
			"count": maxi(1, int(raw.get("count", 1))),
			"minutes": maxf(1.0, float(raw.get("minutes", 60))),
			"tier": maxi(1, int(raw.get("tier", 1))),
			"unlocked": bool(raw.get("unlocked", false)),
			"price": maxi(0, int(raw.get("price", 0))),
			"input_quality": _parse_quality(raw.get("quality", {}), inputs),
		}
		_order.append(id)


static func _parse_quality(raw: Variant, inputs: Dictionary) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for item_id: String in raw:
			if inputs.has(item_id) and str(raw[item_id]) in Quality.ids():
				out[item_id] = str(raw[item_id])
	return out


## 이 재료에 정해진 품질 (없으면 null = 아무 품질이나)
static func need_quality(recipe: Dictionary, item_id: String) -> Variant:
	return recipe.get("input_quality", {}).get(item_id, null)


static func get_recipe(id: String) -> Dictionary:
	_ensure_loaded()
	return _recipes.get(id, {})


static func has(id: String) -> bool:
	_ensure_loaded()
	return _recipes.has(id)


## 데이터 순서대로 전부
static func all() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for id in _order:
		out.append(_recipes[id])
	return out


static func is_known(id: String) -> bool:
	var r := get_recipe(id)
	return not r.is_empty() and (r.unlocked or GameState.unlocks.get("recipe:" + id, false))


## 레시피를 배운다 (영구). 이미 알거나 없는 레시피면 false
static func learn(id: String) -> bool:
	if not has(id) or is_known(id):
		return false
	GameState.unlocks["recipe:" + id] = true
	Events.processor_changed.emit()
	return true


# ---------- 레시피 상점 (§71)

## 상점에서 파는 레시피 (처음부터 아는 것 빼고, 데이터 순서)
static func shop_recipes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in all():
		if not r.unlocked:
			out.append(r)
	return out


## 재료를 모두 한 번씩 얻어 봐서 상점에 진열되는가
static func is_revealed(id: String) -> bool:
	var r := get_recipe(id)
	if r.is_empty():
		return false
	for item_id: String in r.inputs:
		if not GameState.has_found(item_id):
			return false
	return true


## 배울 수 없는 이유. 배울 수 있으면 ""
static func buy_problem(id: String) -> String:
	var r := get_recipe(id)
	if r.is_empty():
		return "없는 레시피예요."
	if is_known(id):
		return "이미 배운 레시피예요."
	if not is_revealed(id):
		return "재료를 먼저 모두 얻어 보세요."
	if GameState.money < int(r.price):
		return "돈이 부족해요. (%d G 필요)" % r.price
	return ""


## 돈을 내고 배운다. 배웠으면 true
static func buy(id: String) -> bool:
	if buy_problem(id) != "" or not GameState.try_spend(int(get_recipe(id).price)):
		return false
	return learn(id)


## "밀 2 + 설탕 1"
static func inputs_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id: String in recipe.inputs:
		var q: Variant = need_quality(recipe, item_id)
		parts.append("%s%s %d" % [ItemDB.get_item(item_id).name, " (%s만)" % Quality.name_of(q) if q != null else "", recipe.inputs[item_id]])
	return " + ".join(parts)


## "1시간 30분" (게임 시계 기준)
static func time_text(game_minutes: float) -> String:
	var m := ceili(game_minutes)
	if m < 60:
		return "%d분" % m
	var hours := int(m / 60.0)
	return "%d시간" % hours if m % 60 == 0 else "%d시간 %d분" % [hours, m % 60]
