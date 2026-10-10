class_name Interior
extends Node2D
## 건물 안 (사용자 결정: 걸어 다니는 작은 실내 맵). 씨앗상점(room_id "store") · 대장간 · 기계상점.
## 하늘섬처럼 농장 맵 바깥에 따로 그려 두고, 문으로 들어가면 플레이어를 옮기고 카메라 범위만 바꾼다 (FarmWorld.enter_interior).
## 걸을 때는 시간이 흐르고, NPC와 대화·거래하는 동안에는 멈춘다 (사용자 결정, 대화 창·상점 창이 멈춤).
##
## 방 크기는 rows 가 정한다 (실내 개편: 세 가게 모두 18x12). 그림은 방마다 한 장
## (assets/art/interior_*.png, tools/make_art.py 의 make_interior_store · make_interior_smith · make_interior_machine).
## 성격: 씨앗상점 = 꽃·모종·밝은 나무 / 대장간 = 불·금속·강화 / 기계상점 = 자동화·부품·설계도
## rows 글자는 충돌만 정한다:  W 벽 · D 문(밟으면 밖으로) · . 바닥 · 그 밖의 글자는 가구(못 지나감)
## 카메라는 방을 화면 가운데에 고정한다 (FarmWorld._centered_limits, 광산과 같은 방식).
## lights: 등불 자리 (방 그림 왼쪽 위 기준 px) — 저녁이면 NightLight 로 노랗게 비춘다. Vector3 면 z 가 빛 반지름
##   NPC 는 계산대 뒤(npc 칸)에 서 있고, 플레이어는 계산대 바로 아래 칸에서 [E] 로 말을 건다.
## 대화에서 고를 수 있는 것은 options: [화면 이름, 하는 일] — 하는 일은 HUD 가 처리 ("buy" · "sell" · "machine" · "smith" · "" 나가기)

const TILE := Art.TILE
## 가장 큰 방 크기 (방마다 크기는 size_of)
const SIZE := Vector2i(18, 12)
## 방 둘레를 어둡게 칠할 여백 (방보다 화면이 넓다). 방끼리 겹치지 않게 origin 을 띄운다 (세로 34칸 간격)
const MARGIN := Vector2i(20, 10)
## 화면 위(퀘스트 창·시계)와 아래(단축바)가 가리는 높이 (월드 px). 카메라 범위를 이만큼 위아래로 늘려
## 방이 화면보다 높아도 뒷벽·문이 HUD 밑에 숨지 않게 한다 (방이 낮으면 그대로 화면 가운데에 고정)
const HUD_PAD_TOP := 38.0
const HUD_PAD_BOTTOM := 28.0

const ROOMS := {
	"store": {
		"origin": Vector2i(202, 12),
		"name": "씨앗상점",
		"texture": "res://assets/art/interior_store.png",
		# (실내 개편 18x12) 뒷벽 2줄 · S 씨앗 봉투 장 · H 화분 선반 · J 씨앗 병 선반 · K 장작 난로 · C 계산대
		# V 큰 화분 · P 꽃 화분 · A 씨앗 자루 · Y 모종 받침대 · L 모종 상자 · G 가운데 진열대 · R 씨앗 봉투 진열대
		# O 화분 더미 · Q 꽃 상자·물뿌리개 · Z 칠판 · B 통
		"rows": [
			"WWWWWWWWWWWWWWWWWW",
			"WWWWWWWWWWWWWWWWWW",
			"WSSSSHH.....JJJKKW",
			"WV....CCCCCCC...AW",
			"WP..............AW",
			"WY.............RRW",
			"WLL...GGGGGG...RRW",
			"WLL...GGGGGG...RRW",
			"WO..............BW",
			"WQQ...........Z.BW",
			"WP..............PW",
			"WWWWWWWWDDWWWWWWWW",
		],
		"lights": [Vector2(104, 18), Vector2(188, 18), Vector2(188, 42), Vector2(6, 72), Vector2(282, 72), Vector2(118, 178), Vector2(169, 178)],
		"npc": {"cell": Vector2i(9, 2), "name": "씨앗상점 주인 하나", "texture": "res://assets/art/npc_store.png",
			"greet": "어서 오세요! 씨앗도 팔고, 작물도 사요.",
			"options": [["씨앗·비료 사기", "buy"], ["작물·가공품 팔기", "sell"], ["나가기", ""]]},
	},
	"smith": {
		"origin": Vector2i(202, 46),
		"name": "대장간",
		"texture": "res://assets/art/interior_smith.png",
		# (실내 개편 18x12) 계산대는 왼쪽, 오른쪽 위는 큰 화덕과 그 앞 돌바닥의 모루
		# R 광석 선반 · T 공구 벽 · X 석탄 통 · F 화덕 · I 주괴 선반 · C 계산대 · O 광석 상자 · G 숫돌 바퀴
		# B 통 · N 모루 · Q 담금질 통 · H 농기구 걸이 · E 강화 작업대 · M 쇠막대·광석 수레·석탄 자루 · S 석탄 양동이
		"rows": [
			"WWWWWWWWWWWWWWWWWW",
			"WWWWWWWWWWWWWWWWWW",
			"WRR.....TTXFFFFFIW",
			"WO.CCCCC...FFFFFIW",
			"WO..............GW",
			"WB..........NNQ..W",
			"WH...............W",
			"WH..EEEE......MMMW",
			"WH............MMMW",
			"WB...............W",
			"WS..............SW",
			"WWWWWWWWDDWWWWWWWW",
		],
		"lights": [Vector2(57, 19), Vector2(121, 19), Vector3(216, 46, 84.0), Vector3(200, 76, 30.0), Vector3(96, 110, 30.0), Vector2(118, 178), Vector2(169, 178)],
		"npc": {"cell": Vector2i(5, 2), "name": "대장장이 철수", "texture": "res://assets/art/npc_smith.png",
			"greet": "도구를 맡기면 바로 고쳐 주지!",
			"options": [["도구 강화", "smith"], ["용광로 사기", "smith_shop"], ["나가기", ""]]},
	},
	"machine": {
		"origin": Vector2i(202, 80),
		"name": "기계상점",
		"texture": "res://assets/art/interior_machine.png",
		# (실내 개편 18x12) 가운데 철판 통로 양옆에 기계 진열대, 오른쪽 벽을 따라 시연용 컨베이어
		# B 보일러 · P 부품 선반 · S 도면 서랍장 · M 철제 사물함 · C 계산대 · X 부품 상자 · T 톱니 걸이판
		# Q 발전기·펌프 진열대 · E 필터·분배기 진열대 · R 컨베이어 · Z 받는 상자 · N 정비 작업대 · K 수리 작업대 · P 화분 · B 기름통
		"rows": [
			"WWWWWWWWWWWWWWWWWW",
			"WWWWWWWWWWWWWWWWWW",
			"WBBPPP....SSSMMMMW",
			"WX....CCCCC.....RW",
			"WX..............RW",
			"WT..............RW",
			"WT.QQQQ....EEEE.RW",
			"WT.QQQQ....EEEE.RW",
			"W...............ZW",
			"WNN...........KKKW",
			"WP..............BW",
			"WWWWWWWWDDWWWWWWWW",
		],
		"lights": [Vector2(109, 25), Vector2(194, 25), Vector3(32, 36, 30.0), Vector2(170, 36), Vector2(118, 178), Vector2(169, 178)],
		"npc": {"cell": Vector2i(9, 2), "name": "기계상점 미나", "texture": "res://assets/art/npc_machine.png",
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


## 방 크기 (칸) = rows 의 폭 x 줄 수
static func size_of(room_id: String) -> Vector2i:
	var rows: Array = room(room_id).get("rows", [])
	if rows.is_empty():
		return Vector2i.ZERO
	return Vector2i(str(rows[0]).length(), rows.size())


## 방 자리 (픽셀). 카메라는 이걸 화면 가운데에 둔다 (FarmWorld._centered_limits)
static func room_rect_of(room_id: String) -> Rect2:
	return Rect2(Vector2(origin_of(room_id) * TILE), Vector2(size_of(room_id) * TILE))


## 카메라가 볼 범위: 방 + HUD 여백 (가로는 방 가운데)
static func camera_rect_of(room_id: String) -> Rect2:
	return room_rect_of(room_id).grow_individual(0.0, HUD_PAD_TOP, 0.0, HUD_PAD_BOTTOM)


static func view_rect_of(room_id: String) -> Rect2:
	return Rect2(Vector2((origin_of(room_id) - MARGIN) * TILE), Vector2((size_of(room_id) + MARGIN * 2) * TILE))


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


## 걸을 수 있는 바닥 칸인가 (방 왼쪽 위 기준)
static func is_floor(room_id: String, local: Vector2i) -> bool:
	var rows: Array = room(room_id).get("rows", [])
	if local.y < 0 or local.y >= rows.size() or local.x < 0 or local.x >= str(rows[local.y]).length():
		return false
	return str(rows[local.y])[local.x] == "."


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
	for p: Variant in room(id).get("lights", []):
		if p is Vector3:
			add_child(NightLight.make(picture.position + Vector2(p.x, p.y), p.z))
		else:
			add_child(NightLight.make(picture.position + (p as Vector2), 44.0))
	_add_walls()
	var n: Dictionary = room(id).npc
	npc = Npc.new()
	npc.setup(n, id)
	var c: Vector2i = origin_of(id) + n.cell
	npc.position = Vector2(c.x * TILE, (c.y + 1) * TILE)
	world.objects.add_child(npc)
	queue_redraw()


## 벽·가구 칸과 문 바깥 줄을 막는다 (바닥 '.' 과 문 'D' 만 지나갈 수 있다)
func _add_walls() -> void:
	var body := StaticBody2D.new()
	var size := size_of(id)
	for y in size.y + 1:
		for x in size.x:
			var ch := char_at(Vector2i(x, y))
			if not ch in [".", "D"] or y == size.y:
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
