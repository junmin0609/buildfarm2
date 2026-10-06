class_name Quality
extends RefCounted
## 작물 품질 (브론즈·실버·골드). 수치는 data/quality.json.
## 품질은 아이템 종류를 나누지 않는다: potato 하나에 가방 칸마다 quality 값을 붙인다.
## 품질이 없는 아이템(도구·씨앗·재료)의 quality 는 NONE("").

const DATA_PATH := "res://data/quality.json"
const NONE := ""

static var _data: Dictionary = {}


static func _cfg() -> Dictionary:
	if _data.is_empty():
		_data = DataFile.load_dict(DATA_PATH)
	return _data


static func default_id() -> String:
	return _cfg().get("default", "bronze")


## 낮은 품질부터
static func ids() -> Array[String]:
	var result: Array[String] = []
	for q: String in _cfg().get("order", []):
		result.append(q)
	return result


static func is_valid(quality: String) -> bool:
	return _cfg().get("types", {}).has(quality)


static func _type(quality: String) -> Dictionary:
	return _cfg().get("types", {}).get(quality, {})


static func name_of(quality: String) -> String:
	return _type(quality).get("name", "")


static func multiplier(quality: String) -> float:
	return float(_type(quality).get("multiplier", 1.0))


static func color_of(quality: String) -> Color:
	return Color(_type(quality).get("color", "ffffff"))


## 아이템에 맞는 품질 값으로 맞춘다. 품질이 없는 아이템은 항상 NONE, 품질이 있는 아이템은 비어 있거나 잘못된 값이면 기본 품질.
static func normalize(item: ItemDef, quality: String) -> String:
	if item == null or not item.has_quality:
		return NONE
	return quality if is_valid(quality) else default_id()


## 수확 품질 뽑기. table 은 quality.json 의 harvest_chances 키 (비료 없음 = "none")
static func roll(rng: RandomNumberGenerator, table := "none") -> String:
	var chances: Dictionary = _cfg().get("harvest_chances", {}).get(table, {})
	var total := 0.0
	for q: String in chances:
		if is_valid(q):
			total += float(chances[q])
	var pick := rng.randf() * total
	for q: String in chances:
		if is_valid(q):
			pick -= float(chances[q])
			if pick < 0.0:
				return q
	return default_id()


## 재료 품질의 평균 (가공품 품질 §74). counts = {품질: 개수}. 품질 순서(브론즈 0, 실버 1, 골드 2)의 평균을 반올림한다.
## 품질 없는 재료(NONE)는 세지 않는다. 셀 것이 없으면 기본 품질.
static func average(counts: Dictionary) -> String:
	var order := ids()
	var total := 0
	var sum := 0
	for q: String in counts:
		var i := order.find(q)
		if i >= 0:
			total += int(counts[q])
			sum += i * int(counts[q])
	if total <= 0:
		return default_id()
	return order[clampi(roundi(float(sum) / total), 0, order.size() - 1)]
