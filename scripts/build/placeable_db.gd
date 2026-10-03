class_name PlaceableDB
extends RefCounted
## 설치 시설 정의 저장소. data/placeables.json 을 처음 쓸 때 한 번 읽는다.

const DATA_PATH := "res://data/placeables.json"

static var _defs: Dictionary = {}  # id -> PlaceableDef
static var _order: Array[String] = []


static func _ensure_loaded() -> void:
	if not _defs.is_empty():
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("시설 데이터를 열 수 없습니다: %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("시설 데이터 형식이 잘못됐습니다: %s" % DATA_PATH)
		return
	for def_id: String in parsed:
		_defs[def_id] = PlaceableDef.from_dict(def_id, parsed[def_id])
		_order.append(def_id)


static func get_def(def_id: String) -> PlaceableDef:
	_ensure_loaded()
	return _defs.get(def_id)


## 건설 창에 보여 줄 순서대로
static func all() -> Array[PlaceableDef]:
	_ensure_loaded()
	var result: Array[PlaceableDef] = []
	for def_id in _order:
		result.append(_defs[def_id])
	return result
