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
