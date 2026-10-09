class_name Npc
extends Interactable
## 상점 안 NPC (사용자 요청: 상점 안에 들어가 NPC에게 말을 걸어 거래). 계산대 뒤에 서 있고,
## 계산대 바로 아래 칸에서 [E] → 대화 창 (이름 · 인사 · 고를 것). 고른 일은 HUD 가 처리한다 (Interior.ROOMS 의 options).

var npc_name := ""
var greeting := ""
## [[화면 이름, 하는 일], ...]
var options: Array = []
var room_id := ""


func setup(data: Dictionary, interior_id: String) -> void:
	room_id = interior_id
	npc_name = str(data.get("name", "상인"))
	greeting = str(data.get("greet", "어서 오세요!"))
	options = data.get("options", [["나가기", ""]])
	texture = load(str(data.get("texture", "")))
	size_tiles = Vector2i(1, 1)
	solid_height = 8.0
	door_x = 8.0
	prompt = "[E] %s에게 말 걸기" % npc_name


## 말을 거는 자리: 계산대 바로 아래 칸 (NPC 칸에서 두 칸 아래)
func interact_point() -> Vector2:
	return global_position + Vector2(door_x, TILE * 1.5)


func interact(_player: Node) -> void:
	Events.npc_talk_requested.emit(self)
