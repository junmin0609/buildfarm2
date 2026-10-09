class_name FarmArea
extends RefCounted
## 1칸짜리 농사 기계(스프링클러·자동 수확기 §14, §66)가 일하는 범위 (사용자 결정: 하급·중급·상급이 같은 규칙).
## placeables.json 의 "area": {"shape": "plus" / "square", "radius": 칸}
##   plus   radius 1 → 상하좌우 4칸 (하급)
##   square radius 1 → 3x3 에서 자기 칸 뺀 8칸 (중급), radius 2 → 5x5 에서 24칸 (상급)


## 기계가 center 칸에 있을 때 일하는 칸들 (자기 칸 제외)
static func cells(center: Vector2i, area: Variant) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not area is Dictionary:
		return out
	var r := maxi(0, int(area.get("radius", 1)))
	var plus := str(area.get("shape", "square")) == "plus"
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx == 0 and dy == 0:
				continue
			if plus and dx != 0 and dy != 0:
				continue
			out.append(center + Vector2i(dx, dy))
	return out


## "상하좌우 4칸" / "3x3 (8칸)" 같은 설명
static func describe(area: Variant) -> String:
	if not area is Dictionary:
		return ""
	var r := maxi(0, int(area.get("radius", 1)))
	if str(area.get("shape", "square")) == "plus":
		return "상하좌우 %d칸" % (4 * r) if r == 1 else "+ 모양 %d칸" % (4 * r)
	var side := 2 * r + 1
	return "%dx%d (%d칸)" % [side, side, side * side - 1]
