class_name CursorTooltip
extends RefCounted
## 커서 옆 작은 창의 위치 계산 (BUILD_FARM_PLAN §45). 커서 대각선 아래에 두고,
## 화면 밖으로 나가면 반대쪽(왼쪽/위쪽)으로 뒤집는다. 작물 정보·아이템 툴팁이 같이 쓴다.

const OFFSET := Vector2(22, 22)


static func position_for(mouse: Vector2, box: Vector2, view: Vector2) -> Vector2:
	var pos := mouse + OFFSET
	if pos.x + box.x > view.x:
		pos.x = mouse.x - OFFSET.x - box.x
	if pos.y + box.y > view.y:
		pos.y = mouse.y - OFFSET.y - box.y
	return pos.max(Vector2.ZERO).floor()


static func place(ctrl: Control) -> void:
	ctrl.position = position_for(ctrl.get_viewport().get_mouse_position(), ctrl.size, ctrl.get_viewport_rect().size)
