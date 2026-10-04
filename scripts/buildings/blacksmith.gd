class_name Blacksmith
extends Interactable
## 광장의 대장간 (BUILD_FARM_PLAN §43). [E]를 누르면 도구 강화 창이 열린다 (강화 규칙은 ToolUpgrade).


func _init() -> void:
	size_tiles = Vector2i(3, 2)
	solid_height = 18.0
	door_x = 24.0
	prompt = "[E] 대장간 (도구 강화)"


func interact(_player: Node) -> void:
	Events.blacksmith_requested.emit()
