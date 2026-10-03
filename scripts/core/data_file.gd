class_name DataFile
extends RefCounted
## data/*.json 설정 파일을 읽는 도우미. 실패하면 오류를 남기고 빈 사전을 돌려준다.


static func load_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("데이터 파일을 열 수 없습니다: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("데이터 파일 형식이 잘못됐습니다: %s" % path)
		return {}
	return parsed


## [x, y] 배열을 Vector2i 로. 모양이 틀리면 fallback (저장 파일이 손상돼도 멈추지 않게)
static func to_vector2i(value: Variant, fallback := Vector2i.ZERO) -> Vector2i:
	if value is Array and value.size() >= 2 and _is_number(value[0]) and _is_number(value[1]):
		return Vector2i(int(value[0]), int(value[1]))
	return fallback


static func to_vector2(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	if value is Array and value.size() >= 2 and _is_number(value[0]) and _is_number(value[1]):
		return Vector2(float(value[0]), float(value[1]))
	return fallback


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
