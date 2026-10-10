class_name Interior
extends Node2D
## 건물 안 (사용자 결정: 걸어 다니는 작은 실내 맵). 잡화점 · 대장간 · 기계상점.
## 하늘섬처럼 농장 맵 바깥에 따로 그려 두고, 문으로 들어가면 플레이어를 옮기고 카메라 범위만 바꾼다 (FarmWorld.enter_interior).
## 걸을 때는 시간이 흐르고, NPC와 대화·거래하는 동안에는 멈춘다 (사용자 결정, 대화 창·상점 창이 멈춤).
##
## 방 (12x9칸, 무드 개편): 그림은 방마다 한 장 (assets/art/interior_*.png, tools/make_art.py 의 make_interiors).
## rows 글자는 충돌만 정한다:  W 벽 · D 문(밟으면 밖으로) · . 바닥 · 그 밖의 글자는 가구(못 지나감)
##   NPC 는 계산대 뒤(npc 칸)에 서 있고, 플레이어는 계산대 바로 아래 칸에서 [E] 로 말을 건다.
## 대화에서 고를 수 있는 것은 options: [화면 이름, 하는 일] — 하는 일은 HUD 가 처리 ("buy" · "sell" · "machine" · "smith" · "" 나가기)

const TILE := Art.TILE
const SIZE := Vector2i(12, 9)
## 카메라가 볼 여백 (방보다 화면이 넓어서 바깥은 어둡게 칠한다). 방끼리 카메라 범위가 겹치지 않게 origin 을 띄운다
const MARGIN := Vector2i(20, 12)

const ROOMS := {
	"store": {
		"origin": Vector2i(202, 12),
		"name": "잡화점",
		"texture": "res://assets/art/interior_store.png",
		# S 씨앗 선반 · K 난로 · C 계산대 · A 씨앗 자루 · T 모종 진열대 · B 통 · P 화분
		"rows": ["WWWWWWWWWWWW", "WSSSS...SKKW", "W...CCCCC..W", "W..........W", "WA..TTTT..BW", "WA..TTTT..BW", "W..........W", "WP........PW", "WWWWWDDWWWWW"],
		"npc": {"cell": Vector2i(6, 1), "name": "잡화점 주인 하나", "texture": "res://assets/art/npc_store.png",
			"greet": "어서 오세요! 씨앗도 팔고, 작물도 사요.",
			"options": [["씨앗·비료 사기", "buy"], ["작물·가공품 팔기", "sell"], ["나가기", ""]]},
	},
	"smith": {
		"origin": Vector2i(202, 46),
		"name": "대장간",
		"texture": "res://assets/art/interior_smith.png",
		# R 광석 선반 · F 화덕 · C 계산대 · N 모루 · T 공구 걸이 · I 주괴 탁자 · X 석탄 통 · B 통 · G 숫돌
		"rows": ["WWWWWWWWWWWW", "WRRR....FFFW", "W...CCCCC..W", "W.........NW", "WT..IIII..XW", "WT..IIII..XW", "WT.........W", "WB........GW", "WWWWWDDWWWWW"],
		"npc": {"cell": Vector2i(6, 1), "name": "대장장이 철수", "texture": "res://assets/art/npc_smith.png",
			"greet": "도구를 맡기면 바로 고쳐 주지!",
			"options": [["도구 강화", "smith"], ["용광로 사기", "smith_shop"], ["나가기", ""]]},
	},
	"machine": {
		"origin": Vector2i(202, 80),
		"name": "기계상점",
		"texture": "res://assets/art/interior_machine.png",
		# B 보일러 · S 부품 선반 · C 계산대 · V 미니 컨베이어 · X 기계 상자 · M 기계 진열대 · P 화분
		"rows": ["WWWWWWWWWWWW", "WBB.....SSSW", "W...CCCCC..W", "W.........VW", "WX..MMMM..VW", "WX..MMMM..VW", "WX........VW", "WP........VW", "WWWWWDDWWWWW"],
		"npc": {"cell": Vector2i(6, 1), "name": "기계상점 미나", "texture": "res://assets/art/npc_machine.png",
			"greet": "자동화 기계는 여기서! 사면 가방에 넣어 드려요.",
			"options": [["기계 사기", "machine"], ["나가기", ""]]},
	},
}

const OUTSIDE := Color("1c130c")

var id := ""
var world: FarmWorld
var npc: Npc


static func room(room_id: String) -> Dictionary:
	return ROOMS.get(room_id, {})


static func origin_of(room_id: String) -> Vector2i:
	return room(room_id).get("origin", Vector2i.ZERO)


static func view_rect_of(room_id: String) -> Rect2:
	return Rect2(Vector2((origin_of(room_id) - MARGIN) * TILE), Vector2((SIZE + MARGIN * 2) * TILE))


## pos 가 어느 방 안(카메라 범위)인가. 아니면 ""
static func room_at(pos: Vector2) -> String:
	for room_id: String in ROOMS:
		if view_rect_of(room_id).has_point(pos):
			return room_id
	return ""


## 문 칸 (방 왼쪽 위 기준, 두 칸 중 왼쪽)
static func door_cell(room_id: String) -> Vector2i:
	var rows: Array = room(room_id).get("rows", [])
	for y in rows.size():
		var x := str(rows[y]).find("D")
		if x >= 0:
			return Vector2i(x, y)
	return Vector2i.ZERO


## 들어오면 서는 곳 (문 바로 안쪽, 두 문 칸 사이)
static func arrive_position(room_id: String) -> Vector2:
	var c := origin_of(room_id) + door_cell(room_id) + Vector2i(0, -1)
	return Vector2(c * TILE) + Vector2(TILE, TILE / 2.0)


func char_at(local: Vector2i) -> String:
	var rows: Array = room(id).get("rows", [])
	if local.y < 0 or local.y >= rows.size() or local.x < 0 or local.x >= str(rows[local.y]).length():
		return ""
	return str(rows[local.y])[local.x]


## 이 칸(월드)이 문인가
func is_door(cell: Vector2i) -> bool:
	return char_at(cell - origin_of(id)) == "D"


func build(farm_world: FarmWorld, room_id: String) -> void:
	world = farm_world
	id = room_id
	name = "Interior_" + id
	z_index = -1
	var picture := Sprite2D.new()
	picture.texture = load(str(room(id).get("texture", "")))
	picture.centered = false
	picture.position = Vector2(origin_of(id) * TILE)
	add_child(picture)
	_add_walls()
	var n: Dictionary = room(id).npc
	npc = Npc.new()
	npc.setup(n, id)
	var c: Vector2i = origin_of(id) + n.cell
	npc.position = Vector2(c.x * TILE, (c.y + 1) * TILE)
	world.objects.add_child(npc)
	queue_redraw()


## 벽·가구 칸과 문 바깥 줄을 막는다
func _add_walls() -> void:
	var body := StaticBody2D.new()
	for y in SIZE.y + 1:
		for x in SIZE.x:
			var ch := char_at(Vector2i(x, y))
			if ch in ["W", "C", "S", "F"] or y == SIZE.y:
				var shape := CollisionShape2D.new()
				var rect := RectangleShape2D.new()
				rect.size = Vector2(TILE, TILE)
				shape.shape = rect
				shape.position = Vector2((origin_of(id) + Vector2i(x, y)) * TILE) + Vector2.ONE * TILE / 2.0
				body.add_child(shape)
	add_child(body)


## 방 둘레(카메라 여백)는 어둡게. 방 그림은 build 에서 Sprite2D 로 얹는다
func _draw() -> void:
	draw_rect(view_rect_of(id), OUTSIDE)
