class_name RecipeShop
extends Interactable
## 광장의 레시피 상점 (셰프, BUILD_FARM_PLAN §71). [E]를 누르면 레시피 상점 창이 열린다 (파는 규칙은 RecipeDB).


func _init() -> void:
	size_tiles = Vector2i(4, 3)
	solid_height = 22.0
	door_x = 32.0
	sign_text = "레시피"
	sign_rect = Rect2(6, 25, 52, 18)
	prompt = "[E] 레시피 상점 (셰프)"


func interact(_player: Node) -> void:
	Events.recipe_shop_requested.emit()
