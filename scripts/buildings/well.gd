class_name Well
extends Interactable
## 농장 우물 (BUILD_FARM_PLAN §14). 물뿌리개의 기본 충전 수단.
##   - 우물 앞에서 [E] → 가방 속 물뿌리개를 모두 최대 용량까지 채운다
##   - 물뿌리개를 들고 우물 칸을 클릭해도 채워진다
## 우물 물은 무한하다.
##
## 물 공급원 규칙 (WateringCan.WATER_SOURCES 그룹). 나중에 펌프·물탱크·자동 관개도 같은 규칙을 따르면
## 물뿌리개(WateringCan)가 그대로 채워 쓴다.
##   covers_cell(cell) -> bool        이 칸이 공급원인가 (물뿌리개로 클릭했을 때)
##   provide_water(amount) -> int     amount 만큼 달라고 하면 실제로 준 양 (물탱크는 남은 양만큼만)
##   water_source_name() -> String    안내 문구용 이름


func _init() -> void:
	size_tiles = Vector2i(2, 2)
	solid_height = 16.0
	door_x = 16.0
	prompt = "[E] 물 긷기 (물뿌리개 채우기)"


func _ready() -> void:
	super()
	add_to_group(WateringCan.WATER_SOURCES)


func interact(_player: Node) -> void:
	WateringCan.refill_all(GameState.inventory, self)


# ---------- 물 공급원

## 차지하는 칸 (노드 위치는 왼쪽 아래 모서리)
func footprint() -> Array[Vector2i]:
	var bottom_left := Vector2i(floori(global_position.x / TILE), floori(global_position.y / TILE))
	var cells: Array[Vector2i] = []
	for y in size_tiles.y:
		for x in size_tiles.x:
			cells.append(bottom_left + Vector2i(x, -1 - y))
	return cells


func covers_cell(cell: Vector2i) -> bool:
	return cell in footprint()


func provide_water(amount: int) -> int:
	return maxi(amount, 0)


func water_source_name() -> String:
	return "우물"
