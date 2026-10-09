class_name Blacksmith
extends Interactable
## 광장의 대장간 (BUILD_FARM_PLAN §43). [E] → 안으로 들어가 대장장이에게 말을 걸어 도구를 강화한다 (사용자 요청).
## 강화 규칙은 ToolUpgrade, 실내는 Interior("smith").


func _init() -> void:
	size_tiles = Vector2i(4, 3)
	solid_height = 22.0
	door_x = 32.0
	sign_text = "대장간"
	sign_rect = Rect2(6, 25, 52, 18)
	prompt = "[E] 대장간 들어가기"


func interact(_player: Node) -> void:
	Events.enter_requested.emit("smith")
