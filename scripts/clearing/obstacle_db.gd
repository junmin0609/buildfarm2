class_name ObstacleDB
extends RefCounted
## data/obstacles.json 저장소: 장애물 종류, 시작 농장 분포, 다시 자라는 규칙.

const DATA_PATH := "res://data/obstacles.json"

static var _types: Dictionary = {}   # id -> ObstacleDef
static var _data: Dictionary = {}


static func _ensure_loaded() -> void:
	if not _data.is_empty():
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("장애물 데이터를 열 수 없습니다: %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("장애물 데이터 형식이 잘못됐습니다: %s" % DATA_PATH)
		return
	_data = parsed
	var types: Dictionary = _data.get("types", {})
	for def_id: String in types:
		_types[def_id] = ObstacleDef.from_dict(def_id, types[def_id])


static func get_def(def_id: String) -> ObstacleDef:
	_ensure_loaded()
	return _types.get(def_id)


## 시작 농장 분포 설정
static func start_farm() -> Dictionary:
	_ensure_loaded()
	return _data.get("start_farm", {})


## 다시 자라는 규칙
static func regrow() -> Dictionary:
	_ensure_loaded()
	return _data.get("regrow", {})


## {"weed": 5, "branch": 2} 같은 가중치 표에서 하나 뽑기
static func pick_weighted(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k: String in weights:
		roll -= float(weights[k])
		if roll < 0.0:
			return k
	return weights.keys()[0] if not weights.is_empty() else ""
