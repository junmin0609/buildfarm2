class_name ItemDef
extends RefCounted
## 아이템 한 종류의 정의. data/items.json 한 항목이 하나의 ItemDef가 된다.

enum Kind { TOOL, SEED, CROP, MATERIAL, FERTILIZER }

const KIND_BY_NAME := {"tool": Kind.TOOL, "seed": Kind.SEED, "crop": Kind.CROP, "material": Kind.MATERIAL, "fertilizer": Kind.FERTILIZER}

var id := ""
var name := ""
var kind: Kind = Kind.CROP
var description := ""
var buy_price := 0
## 기준 판매가 (브론즈·출하함 기준). 품질·판매 방식 배율은 Pricing 이 곱한다.
var sell_price := 0
var max_stack := 99
## items.png 에서 몇 번째 칸이 이 아이템 아이콘인지
var icon := 0
## true 면 가방 칸마다 품질(Quality)을 가진다. 기본: 작물만
var has_quality := false

## 도구 종류 (kind == TOOL): "hoe", "watering_can", "axe", "pickaxe" ...
var tool_type := ""
## 도구 등급. 기본 1, 대장간 강화로 올라간다 (더 큰 장애물을 치울 수 있음)
var tier := 1
## 물뿌리개처럼 채워 쓰는 도구의 용량 (0 이면 해당 없음)
var capacity := 0
## 한 번 칠 때 장애물을 깎는 양 (강화하면 빨라진다 §43)
var power := 1
## 괭이: 바라보는 방향으로 한 번에 가는 칸 수
var till_length := 1
## 물뿌리개: 물 주는 범위 (나중에 넓은 범위 물주기용, 지금은 1)
var water_area := 1
## 대장간 강화 (§43): {"to": 다음 단계 아이템 id, "price": G, "materials": {아이템 id: 개수}}. 없으면 최고 단계
var upgrade := {}

## 씨앗 정보 (kind == SEED)
var grows := ""      # 다 자라면 나오는 작물 아이템 id
var grow_days := 0
## 0 이면 한 번 수확하고 사라짐, 아니면 수확 뒤 이 날짜마다 다시 열림
var regrow_days := 0
var yield_min := 1
var yield_max := 1
## 자랄 수 있는 계절 ("spring", "summer", "autumn", "winter"). 계절 시스템이 생기면 쓴다.
var seasons: Array[String] = []
var crop_row := 0    # crops.png 에서 이 작물의 줄

## 비료 정보 (kind == FERTILIZER, §25)
## quality.json 의 harvest_chances 에서 쓸 표 이름 ("basic", "advanced", "premium")
var quality_table := ""
## 비료를 준 밭에 찍히는 점 색
var soil_color := Color.TRANSPARENT


static func from_dict(item_id: String, d: Dictionary) -> ItemDef:
	var item := ItemDef.new()
	item.id = item_id
	item.name = d.get("name", item_id)
	item.kind = KIND_BY_NAME.get(d.get("kind", "crop"), Kind.CROP)
	item.description = d.get("description", "")
	item.buy_price = int(d.get("buy_price", 0))
	item.sell_price = int(d.get("sell_price", 0))
	item.max_stack = int(d.get("max_stack", 99))
	item.icon = int(d.get("icon", 0))
	item.has_quality = d.get("has_quality", item.kind == Kind.CROP)
	item.crop_row = int(d.get("crop_row", 0))
	item.tool_type = d.get("tool", "")
	item.tier = int(d.get("tier", 1))
	item.capacity = int(d.get("capacity", 0))
	item.power = maxi(1, int(d.get("power", 1)))
	item.till_length = maxi(1, int(d.get("till_length", 1)))
	item.water_area = maxi(1, int(d.get("water_area", 1)))
	item.upgrade = d.get("upgrade", {}) if d.get("upgrade", {}) is Dictionary else {}
	item.grows = d.get("grows", "")
	item.grow_days = int(d.get("grow_days", 0))
	item.regrow_days = int(d.get("regrow_days", 0))
	item.yield_min = maxi(1, int(d.get("yield_min", 1)))
	item.yield_max = maxi(item.yield_min, int(d.get("yield_max", item.yield_min)))
	for s: String in d.get("seasons", []):
		item.seasons.append(s)
	item.quality_table = d.get("quality_table", "")
	if d.has("soil_color"):
		item.soil_color = Color(d.soil_color)
	return item


func is_sellable() -> bool:
	return sell_price > 0


func regrows() -> bool:
	return regrow_days > 0


## 가방 칸이 새로 생길 때 붙는 상태 (물뿌리개는 물을 가득 채운 채로 들어온다)
func new_slot_state() -> Dictionary:
	if capacity > 0:
		return {"water": capacity}
	return {}
