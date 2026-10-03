class_name ShopStall
extends Interactable
## 광장의 가게. [E]를 누르면 shop_mode 에 맞는 상점 창이 열린다.
## 씨앗 상점(buy)과 작물 판매처(sell)가 같은 스크립트를 쓰고, 씬에서 그림·모드·안내만 바꾼다.

## "buy" 씨앗 사기, "sell" 작물 팔기, "all" 둘 다
@export var shop_mode := "buy"


func _init() -> void:
	size_tiles = Vector2i(3, 2)
	solid_height = 16.0
	door_x = 24.0
	prompt = "[E] 씨앗 상점"


func interact(_player: Node) -> void:
	Events.shop_requested.emit(shop_mode)
