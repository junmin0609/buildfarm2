class_name Pricing
extends RefCounted
## 판매 가격 계산. 판매가 = 기준가(items.json sell_price) × 품질 배율 × 판매 방식 배율.
## 판매 방식(channel)과 배율은 data/economy.json 의 sell_channels:
##   "plaza"         광장 즉시 판매 (기준가의 80%)
##   "shipping_bin"  농장 출하함, 하루가 끝날 때 정산 (100%)
## 하늘시장처럼 날마다 바뀌는 가격은 그 시스템이 기준가 대신 그날 가격을 넘겨 쓰면 된다 (price_from).

const DATA_PATH := "res://data/economy.json"
const PLAZA := "plaza"
const SHIPPING_BIN := "shipping_bin"

static var _data: Dictionary = {}


static func _channels() -> Dictionary:
	if _data.is_empty():
		_data = DataFile.load_dict(DATA_PATH)
	return _data.get("sell_channels", {})


static func channel_multiplier(channel: String) -> float:
	return float(_channels().get(channel, {}).get("multiplier", 1.0))


static func channel_name(channel: String) -> String:
	return _channels().get(channel, {}).get("name", channel)


## 품질만 반영한 값 (기획서 §36 의 브론즈·실버·골드 가격)
static func quality_price(item: ItemDef, quality: String) -> int:
	return price_from(item.sell_price, item, quality)


## 판매 방식까지 반영한 개당 판매가
static func unit_price(item: ItemDef, quality: String, channel: String) -> int:
	if item == null or not item.is_sellable():
		return 0
	return roundi(quality_price(item, quality) * channel_multiplier(channel))


## 기준가를 따로 받아 품질을 반영한다 (하늘시장의 그날 가격 등). 소수점은 버림 (사용자 결정, 경제 기준 v1.0)
static func price_from(base: int, item: ItemDef, quality: String) -> int:
	return floori(base * Quality.multiplier(Quality.normalize(item, quality)) + 0.0001)
