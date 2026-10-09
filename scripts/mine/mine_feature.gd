class_name MineFeature
extends Interactable
## 광산 안의 [E] 로 쓰는 것: 내려가는 사다리 · 올라가는 사다리 · 엘리베이터 · 보물 상자 (Mine 이 층마다 놓고 지운다).
## 엘리베이터는 가게 NPC 처럼 대화 창을 연다 (npc_name · greeting · options). 층을 고르면 HUD 가 Events.mine_requested 를 보낸다.

enum Kind { DOWN, UP, ELEVATOR, CHEST }

var kind := Kind.DOWN
var cell := Vector2i.ZERO
var mine: Mine
## 엘리베이터 대화 창용
var npc_name := "엘리베이터"
var greeting := ""
var options: Array = []


func setup(owner_mine: Mine, feature_kind: Kind, at_cell: Vector2i) -> void:
	mine = owner_mine
	kind = feature_kind
	cell = at_cell
	match kind:
		Kind.DOWN:
			texture = preload("res://assets/art/mine_ladder_down.png")
			z_index = -1  # 바닥 구멍: 플레이어가 위에 서도 가리지 않게
			prompt = "[E] 아래로 내려가기 (%d층)" % (mine.floor_no + 1)
		Kind.UP:
			texture = preload("res://assets/art/mine_ladder_up.png")
			prompt = "[E] 입구층으로 올라가기"
		Kind.ELEVATOR:
			texture = preload("res://assets/art/mine_elevator.png")
			size_tiles = Vector2i(2, 1)
			solid_height = 10.0
			door_x = TILE
			prompt = "[E] 엘리베이터 타기"
		Kind.CHEST:
			texture = preload("res://assets/art/mine_chest.png")
			solid_height = 8.0
			prompt = "[E] 보물 상자 열기"
	name = "MineFeature_%d_%d" % [cell.x, cell.y]
	position = Vector2(cell.x * TILE, (cell.y + 1) * TILE)


func _add_collision() -> void:
	if kind in [Kind.ELEVATOR, Kind.CHEST]:
		super._add_collision()


## 사다리는 그 칸 위·옆에서, 엘리베이터·상자는 바로 앞에서
func interact_point() -> Vector2:
	if kind == Kind.DOWN:
		return global_position + Vector2(TILE / 2.0, -TILE / 2.0)
	return super.interact_point()


func interact(_player: Node) -> void:
	match kind:
		Kind.DOWN:
			Events.mine_requested.emit(mine.floor_no + 1)
		Kind.UP:
			Events.mine_requested.emit(0)
		Kind.CHEST:
			mine.open_chest(self)
		Kind.ELEVATOR:
			_fill_options()
			Events.npc_talk_requested.emit(self)


## 갈 수 있는 층 버튼 (지금 층은 빼고) + 닫기
func _fill_options() -> void:
	options = []
	for n: int in Mine.elevator_stops():
		if n != mine.floor_no:
			options.append(["입구층" if n == 0 else "%d층" % n, "mine:%d" % n])
	options.append(["닫기", ""])
	var next := (floori(Mine.deepest() / float(Mine.elevator_every())) + 1) * Mine.elevator_every()
	greeting = "어느 층으로 갈까요?" if options.size() > 1 else "아직 열린 정류장이 없어요."
	if next <= Mine.bottom():
		greeting += " (%d층에 처음 닿으면 그 층 정류장이 열려요)" % next
