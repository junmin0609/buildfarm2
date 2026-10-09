class_name SkyIslandBuilding
extends Interactable
## 하늘섬의 건물 (§84, §90). kind 로 하는 일이 갈린다.
##   "market"  하늘시장 가판대 → 하늘시장 창
##   "dock"    비행선 → 광장으로 돌아가기 (편도 게임 시계 1시간)

@export var kind := "market"


func _ready() -> void:
	if kind == "dock":
		size_tiles = Vector2i(4, 3)
		solid_height = 22.0
		door_x = 32.0
		prompt = "[E] 비행선 타기 (농장 광장으로)"
	else:
		size_tiles = Vector2i(3, 2)
		solid_height = 18.0
		door_x = 24.0
		prompt = "[E] 하늘시장"
	super._ready()


func interact(_player: Node) -> void:
	if kind == "dock":
		Events.travel_requested.emit("home")
	else:
		Events.sky_market_requested.emit()
