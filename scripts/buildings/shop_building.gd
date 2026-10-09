class_name ShopBuilding
extends Interactable
## 들어가는 가게 건물 (사용자 요청). [E] → 문으로 들어가 실내(Interior)로 간다. 거래는 안의 NPC 에게 말을 걸어서.
##   잡화점 (room_id "store", 5x3): 씨앗 상점과 작물 판매처를 합친 곳
##   기계상점 (room_id "machine", 5x3): 공장·자동화 기계를 아이템으로 파는 곳

@export var room_id := "store"
## 차지하는 칸 (FarmWorld 가 자리를 정할 때 쓰므로 씬에서 값이 들어오는 순간 맞춘다)
@export var tiles := Vector2i(4, 3):
	set(v):
		tiles = v
		size_tiles = v
		door_x = v.x * TILE / 2.0


func _init() -> void:
	solid_height = 20.0
	size_tiles = tiles
	door_x = tiles.x * TILE / 2.0


func interact(_player: Node) -> void:
	Events.enter_requested.emit(room_id)
