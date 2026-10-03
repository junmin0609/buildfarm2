class_name Weather
extends RefCounted
## 날씨 (BUILD_FARM_PLAN §32, §33, §16, §100). 수치는 data/weather.json.
##   - 하루 마감의 weather 단계(다음 날 07:00 직전)에 그날 날씨를 정하고, 하루 동안 바꾸지 않는다. 예보는 없다.
##   - waters_soil 인 날씨(비)는 바깥 밭을 모두 적신다. 그날 새로 간 밭도 젖는다.
## 지금 날씨는 GameState.weather 에 저장된다.

const DATA_PATH := "res://data/weather.json"

## 점검·화면 확인용: 비워 두지 않으면 roll 이 항상 이 날씨를 돌려준다
static var forced := ""

static var _data: Dictionary = {}


static func _cfg() -> Dictionary:
	if _data.is_empty():
		_data = DataFile.load_dict(DATA_PATH)
	return _data


static func _type(weather: String) -> Dictionary:
	return _cfg().get("types", {}).get(weather, {})


static func first_day() -> String:
	return _cfg().get("first_day", "sunny")


static func name_of(weather: String) -> String:
	return _type(weather).get("name", weather)


static func morning_text(weather: String) -> String:
	return _type(weather).get("morning", "")


## 바깥 밭을 적시는 날씨인가 (비)
static func waters_soil(weather: String) -> bool:
	return _type(weather).get("waters_soil", false) == true


## 화면 색 (없으면 흰색 = 그대로)
static func tint(weather: String) -> Color:
	return Color(_type(weather).get("tint", "ffffff"))


## 그날의 날씨 확률표 {날씨: 가중치}. 계절 안의 날로 구간을 고른다.
static func weights_for(day: int) -> Dictionary:
	var day_in := Calendar.day_in_season(day)
	for span: Variant in _cfg().get("seasons", {}).get(Calendar.season_of(day), []):
		if span is Dictionary and day_in >= int(span.get("from", 1)) and day_in <= int(span.get("to", 999)):
			return span.get("weights", {})
	return {first_day(): 1}


## 그날 날씨를 뽑는다
static func roll(day: int, rng: RandomNumberGenerator) -> String:
	if forced != "":
		return forced
	var weights := weights_for(day)
	var total := 0.0
	for w: Variant in weights.values():
		total += float(w)
	var pick := rng.randf() * total
	for weather: String in weights:
		pick -= float(weights[weather])
		if pick < 0.0:
			return weather
	return first_day()
