class_name House
extends Interactable
## 플레이어 집. 문 앞에서 [E]를 누르면 잠을 자고 다음 날이 된다.


func _init() -> void:
	size_tiles = Vector2i(4, 3)
	solid_height = 30.0
	door_x = 32.0
	prompt = "[E] 잠자기 (다음 날 아침으로)"


func interact(_player: Node) -> void:
	GameState.sleep()
