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
## 배운 레시피는 GameState.unlocks["recipe:<id>"] 에 저장된다 (레시피 상점이 생기면 learn 을 부르면 된다).

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
		}
		_order.append(id)


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


## "밀 2 + 설탕 1"
static func inputs_text(recipe: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id: String in recipe.inputs:
		parts.append("%s %d" % [ItemDB.get_item(item_id).name, recipe.inputs[item_id]])
	return " + ".join(parts)


## "1시간 30분" (게임 시계 기준)
static func time_text(game_minutes: float) -> String:
	var m := ceili(game_minutes)
	if m < 60:
		return "%d분" % m
	return "%d시간" % (m / 60) if m % 60 == 0 else "%d시간 %d분" % [m / 60, m % 60]
