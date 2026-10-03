class_name Calendar
extends RefCounted
## 날짜 → 계절 계산 (BUILD_FARM_PLAN §30). 수치는 data/calendar.json.
## 날짜(GameState.day)는 1일부터 계속 늘어나는 숫자 하나이고, 계절·계절 안의 날·연차는 여기서 계산한다.
##   1~28일 봄, 29~56일 여름, 57~84일 가을, 85~112일 겨울, 113일 = 2년차 봄 1일

const DATA_PATH := "res://data/calendar.json"

static var _data: Dictionary = {}


static func _cfg() -> Dictionary:
	if _data.is_empty():
		_data = DataFile.load_dict(DATA_PATH)
	return _data


static func days_per_season() -> int:
	return maxi(1, int(_cfg().get("days_per_season", 28)))


static func seasons() -> Array:
	return _cfg().get("seasons", ["spring", "summer", "autumn", "winter"])


static func season_of(day: int) -> String:
	var list := seasons()
	return list[int((maxi(day, 1) - 1) / days_per_season()) % list.size()]


## 계절 안에서 몇째 날인지 (1 ~ days_per_season)
static func day_in_season(day: int) -> int:
	return (maxi(day, 1) - 1) % days_per_season() + 1


static func year_of(day: int) -> int:
	return int((maxi(day, 1) - 1) / (days_per_season() * seasons().size())) + 1


static func season_name(season: String) -> String:
	return _cfg().get("names", {}).get(season, season)


## 바깥 밭에 씨앗을 심을 수 있는 계절인가 (겨울은 온실에서만 §35)
static func outdoor_planting_allowed(season: String) -> bool:
	return season not in _cfg().get("no_outdoor_planting", [])


static func soil_revert_chance() -> float:
	return clampf(float(_cfg().get("soil_revert_chance", 0.35)), 0.0, 1.0)


## 작물이 그 계절에 살 수 있는가. 씨앗에 seasons 가 없으면 모든 계절.
static func crop_allowed(seed_def: ItemDef, season: String) -> bool:
	return seed_def == null or seed_def.seasons.is_empty() or season in seed_def.seasons


## "봄 3일", 2년차부터 "2년차 봄 3일"
static func date_text(day: int) -> String:
	var text := "%s %d일" % [season_name(season_of(day)), day_in_season(day)]
	var year := year_of(day)
	return text if year == 1 else "%d년차 %s" % [year, text]
