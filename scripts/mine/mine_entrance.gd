class_name MineEntrance
extends Interactable
## 광장 북쪽 숲길 끝의 동굴 입구 (사용자 결정). [E] → 광산 입구층 (Mine).
## 노드 위치는 차지하는 칸들의 왼쪽 아래 (FarmWorld 가 CELL 자리에 놓는다).

## 입구 그림이 덮는 칸들의 왼쪽 위 (북쪽 숲길 맨 위 끝, 길 3칸 폭)
const CELL := Vector2i(84, 0)


func _init() -> void:
	texture = preload("res://assets/art/mine_entrance.png")
	size_tiles = Vector2i(3, 3)
	solid_height = 20.0
	door_x = TILE * 1.5
	prompt = "[E] 광산으로 들어가기"
	ground_shadow = true


static func place_position() -> Vector2:
	return Vector2(CELL.x * TILE, (CELL.y + 3) * TILE)


func interact(_player: Node) -> void:
	# 새 게임은 광산 입구 수리(MQ11) 뒤에 열림. 기존 저장은 그대로 (스토리 3단계)
	var lock := QuestManager.tech_lock_reason_now("mine_access")
	if lock != "":
		Events.toast.emit("무너진 광산 입구예요. 들어가려면 " + lock.trim_prefix("잠김 · "))
		return
	Events.mine_requested.emit(0)
