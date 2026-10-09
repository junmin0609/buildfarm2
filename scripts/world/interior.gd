class_name Interior
extends Node2D
## 건물 안 (사용자 결정: 걸어 다니는 작은 실내 맵). 잡화점 · 대장간 · 기계상점.
## 하늘섬처럼 농장 맵 바깥에 따로 그려 두고, 문으로 들어가면 플레이어를 옮기고 카메라 범위만 바꾼다 (FarmWorld.enter_interior).
## 걸을 때는 시간이 흐르고, NPC와 대화·거래하는 동안에는 멈춘다 (사용자 결정, 대화 창·상점 창이 멈춤).
##
## 방 (10x7칸, rows 글자):  W 벽 · C 계산대 · S 선반 · F 화덕 · D 문(밟으면 밖으로) · 나머지 바닥
##   NPC 는 계산대 뒤(npc 칸)에 서 있고, 플레이어는 계산대 바로 아래 칸에서 [E] 로 말을 건다.
## 대화에서 고를 수 있는 것은 options: [화면 이름, 하는 일] — 하는 일은 HUD 가 처리 ("buy" · "sell" · "machine" · "smith" · "" 나가기)

const TILE := Art.TILE
const SIZE := Vector2i(10, 7)
## 카메라가 볼 여백 (방보다 화면이 넓어서 바깥은 어둡게 칠한다)
const MARGIN := Vector2i(6, 4)

const ROOMS := {
	"store": {
		"origin": Vector2i(160, 4),
		"name": "잡화점",
		"rows": ["WWWWWWWWWW", "WSSS..SSSW", "W..CCCC..W", "W........W", "W........W", "W........W", "WWWWDDWWWW"],
		"npc": {"cell": Vector2i(5, 1), "name": "잡화점 주인 하나", "texture": "res://assets/art/npc_store.png",
			"greet": "어서 오세요! 씨앗도 팔고, 작물도 사요.",
			"options": [["씨앗·비료 사기", "buy"], ["작물·가공품 팔기", "sell"], ["나가기", ""]]},
		"wall": Color("c9a27e"), "accent": Color("7fb069"),
	},
	"smith": {
		"origin": Vector2i(160, 16),
		"name": "대장간",
		"rows": ["WWWWWWWWWW", "WSS....SSW", "W..CCCC..W", "W........W", "WF.......W", "W........W", "WWWWDDWWWW"],
		"npc": {"cell": Vector2i(5, 1), "name": "대장장이 철수", "texture": "res://assets/art/npc_smith.png",
			"greet": "도구를 맡기면 바로 고쳐 주지!",
			"options": [["도구 강화", "smith"], ["나가기", ""]]},
		"wall": Color("a99782"), "accent": Color("f29b50"),
	},
	"machine": {
		"origin": Vector2i(160, 28),
		"name": "기계상점",
		"rows": ["WWWWWWWWWW", "WSSS..SSSW", "W..CCCC..W", "W........W", "W........W", "W........W", "WWWWDDWWWW"],
		"npc": {"cell": Vector2i(5, 1), "name": "기계상점 미나", "texture": "res://assets/art/npc_machine.png",
			"greet": "자동화 기계는 여기서! 사면 가방에 넣어 드려요.",
			"options": [["기계 사기", "machine"], ["나가기", ""]]},
		"wall": Color("8fa3b8"), "accent": Color("f2c443"),
	},
}

const FLOOR := [Color("e6c99a"), Color("d9b98a")]
const FLOOR_LINE := Color("c9a273")
const COUNTER := [Color("a8714a"), Color("e6b77f"), Color("7a4e32")]
const OUTSIDE := Color("2e2119")
const GOODS := [Color("e0715f"), Color("f2c443"), Color("7fb069"), Color("5a64b8"), Color("f6e6c4")]

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


## 들어오면 서는 곳 (문 바로 안쪽)
static func arrive_position(room_id: String) -> Vector2:
	var c := origin_of(room_id) + Vector2i(4, 5)
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
	_add_walls()
	var n: Dictionary = room(id).npc
	npc = Npc.new()
	npc.setup(n, id)
	var c: Vector2i = origin_of(id) + n.cell
	npc.position = Vector2(c.x * TILE, (c.y + 1) * TILE)
	world.objects.add_child(npc)
	queue_redraw()


## 벽·계산대·선반·화덕 칸과 문 바깥 줄을 막는다
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


func _draw() -> void:
	var r: Dictionary = room(id)
	draw_rect(view_rect_of(id), OUTSIDE)
	var wall: Color = r.get("wall", Color("c9a27e"))
	var accent: Color = r.get("accent", Color("7fb069"))
	for y in SIZE.y:
		for x in SIZE.x:
			var local := Vector2i(x, y)
			var at := Vector2((origin_of(id) + local) * TILE)
			var cell_rect := Rect2(at, Vector2(TILE, TILE))
			match char_at(local):
				"W":
					draw_rect(cell_rect, wall)
					draw_rect(Rect2(at + Vector2(0, TILE - 4), Vector2(TILE, 4)), wall.darkened(0.25))
					if y == 0:
						draw_rect(Rect2(at + Vector2(2, 5), Vector2(TILE - 4, 2)), wall.lightened(0.2))
				"D":
					_floor(at, local)
					draw_rect(Rect2(at + Vector2(1, 4), Vector2(TILE - 2, TILE - 4)), Color("8a5a3a"))
					draw_rect(Rect2(at + Vector2(3, 7), Vector2(TILE - 6, TILE - 9)), accent.darkened(0.1))
				"C":
					_floor(at, local)
					draw_rect(Rect2(at + Vector2(0, 2), Vector2(TILE, TILE - 2)), COUNTER[0])
					draw_rect(Rect2(at + Vector2(0, 2), Vector2(TILE, 3)), COUNTER[1])
					draw_rect(Rect2(at + Vector2(0, TILE - 2), Vector2(TILE, 2)), COUNTER[2])
				"S":
					draw_rect(cell_rect, wall)
					draw_rect(Rect2(at + Vector2(1, 3), Vector2(TILE - 2, TILE - 4)), COUNTER[2])
					for k in 3:
						draw_rect(Rect2(at + Vector2(2 + k * 4, 5), Vector2(3, 4)), GOODS[(x + y + k) % GOODS.size()])
						draw_rect(Rect2(at + Vector2(2 + k * 4, 11), Vector2(3, 3)), GOODS[(x * 2 + k) % GOODS.size()])
				"F":
					_floor(at, local)
					draw_rect(Rect2(at + Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), Color("7d6f63"))
					draw_circle(at + Vector2(8, 9), 4.5, Color("f29b50"))
					draw_circle(at + Vector2(8, 9), 2.5, Color("ffd27a"))
				_:
					_floor(at, local)
	# 문 앞 깔개
	var mat := Vector2((origin_of(id) + Vector2i(4, 5)) * TILE)
	draw_rect(Rect2(mat + Vector2(2, 9), Vector2(TILE * 2 - 4, 6)), accent)
	draw_rect(Rect2(mat + Vector2(3, 10), Vector2(TILE * 2 - 6, 1)), accent.lightened(0.3))


func _floor(at: Vector2, local: Vector2i) -> void:
	draw_rect(Rect2(at, Vector2(TILE, TILE)), FLOOR[(local.x + local.y) % 2])
	draw_rect(Rect2(at + Vector2(0, 7), Vector2(TILE, 1)), FLOOR_LINE)
	draw_rect(Rect2(at + Vector2(5 + (local.y % 2) * 6, 0), Vector2(1, 7)), FLOOR_LINE)
