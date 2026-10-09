class_name SkyIsland
extends Node2D
## 하늘섬 (BUILD_FARM_PLAN §84, §90). 사용자 결정: 비행선을 타고 가는 작은 하늘섬 맵.
## 농장 맵(MapLayout) 바깥 오른쪽 먼 곳에 따로 그려 두고, 비행하면 플레이어를 옮기고 카메라가 보는 범위만 바꾼다 (FarmWorld.travel).
## 섬 칸은 농장 맵이 아니라서 밭·건설·장애물이 생기지 않는다.
##
## 섬 (SIZE 칸, ORIGIN 기준)
##   위 가운데 하늘시장 가판대 (3x2) / 왼쪽 아래 비행선 선착장 (4x3, 돌아가는 비행선) / 가운데 돌길 / 가로등·통·화분
##   둘레는 보이지 않는 벽. 바깥은 하늘 (구름)
## 그림은 tiles.png 의 잔디·광장 돌 칸을 그대로 쓰고, 섬 아래 흙 절벽과 하늘·구름만 여기서 그린다.

const TILE := Art.TILE
## 섬 왼쪽 위 칸 (농장 맵 오른쪽 바깥)
const ORIGIN := Vector2i(80, 6)
## 화면(약 20x11칸)보다 작게 해서 둘레로 하늘이 보이게 (떠 있는 섬)
const SIZE := Vector2i(14, 9)
## 카메라가 볼 하늘 여백 (칸)
const MARGIN := Vector2i(8, 6)
## 걸을 수 있는 칸 (섬 안쪽, 섬 기준)
const WALK := Rect2i(1, 1, 12, 7)
const MARKET_AT := Vector2i(6, 1)
const DOCK_AT := Vector2i(1, 3)
## 비행선에서 내리는 칸 (선착장 앞)
const ARRIVE_AT := Vector2i(3, 7)
const PATH_CELLS := [Vector2i(3, 7), Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7),
		Vector2i(7, 6), Vector2i(7, 5), Vector2i(7, 4), Vector2i(6, 3), Vector2i(7, 3), Vector2i(8, 3)]
const PROPS := {Vector2i(10, 4): "L", Vector2i(5, 5): "L", Vector2i(11, 2): "b", Vector2i(10, 2): "f", Vector2i(5, 2): "f", Vector2i(11, 6): "h"}

const SKY := [Color("a9d8ee"), Color("b8e0f1"), Color("c8e8f4"), Color("d9eff7")]
const CLOUD := Color("fbfdfe")
const CLOUD_SHADE := Color("e3f1f8")
const CLIFF := [Color("8a5a3a"), Color("6e452b"), Color("a06b45")]

var world: FarmWorld
var market: SkyIslandBuilding
var dock: SkyIslandBuilding


## 카메라가 볼 범위 (픽셀): 섬 + 하늘 여백
static func view_rect() -> Rect2:
	return Rect2(Vector2((ORIGIN - MARGIN) * TILE), Vector2((SIZE + MARGIN * 2) * TILE))


static func island_rect() -> Rect2:
	return Rect2(Vector2(ORIGIN * TILE), Vector2(SIZE * TILE))


static func contains(pos: Vector2) -> bool:
	return view_rect().has_point(pos)


static func arrive_position() -> Vector2:
	var c := ORIGIN + ARRIVE_AT
	return Vector2(c * TILE) + Vector2(TILE / 2.0, TILE / 2.0)


## 섬 모양: 둥근 모서리 (네 귀퉁이 칸을 깎는다)
static func is_island_cell(local: Vector2i) -> bool:
	if local.x < 0 or local.y < 0 or local.x >= SIZE.x or local.y >= SIZE.y:
		return false
	var corner := (local.x in [0, SIZE.x - 1]) and (local.y in [0, SIZE.y - 1])
	return not corner


func build(farm_world: FarmWorld) -> void:
	world = farm_world
	name = "SkyIsland"
	z_index = -1  # 밭·벨트처럼 바닥: 나무·건물·플레이어 아래
	market = _spawn_building("market", MARKET_AT, preload("res://assets/art/sky_stall.png"))
	dock = _spawn_building("dock", DOCK_AT, preload("res://assets/art/airship.png"))
	for local: Vector2i in PROPS:
		var prop: Node2D = load(MapLayout.PROPS[PROPS[local]]).instantiate()
		prop.position = world.cell_center(ORIGIN + local) + Vector2(0, TILE / 2.0 - 2)
		world.objects.add_child(prop)
	_add_walls()
	queue_redraw()


func _spawn_building(kind: String, local: Vector2i, tex: Texture2D) -> SkyIslandBuilding:
	var b := SkyIslandBuilding.new()
	b.kind = kind
	b.texture = tex
	var cell := ORIGIN + local
	var h := 3 if kind == "dock" else 2
	b.position = Vector2(cell.x * TILE, (cell.y + h) * TILE)
	world.objects.add_child(b)
	return b


## 걸을 수 있는 칸(WALK) 둘레에 보이지 않는 벽
func _add_walls() -> void:
	var r := Rect2(Vector2((ORIGIN + WALK.position) * TILE), Vector2(WALK.size * TILE))
	var body := StaticBody2D.new()
	for wall: Rect2 in [Rect2(r.position.x - 32, r.position.y - 32, r.size.x + 64, 32), Rect2(r.position.x - 32, r.end.y, r.size.x + 64, 32),
			Rect2(r.position.x - 32, r.position.y, 32, r.size.y), Rect2(r.end.x, r.position.y, 32, r.size.y)]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = wall.size
		shape.shape = rect
		shape.position = wall.get_center()
		body.add_child(shape)
	add_child(body)


func _draw() -> void:
	var view := view_rect()
	# 하늘: 위에서 아래로 밝아지는 띠
	var band := view.size.y / SKY.size()
	for i in SKY.size():
		draw_rect(Rect2(view.position + Vector2(0, band * i), Vector2(view.size.x, band + 1)), SKY[i])
	# 구름 (늘 같은 자리)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 14:
		var p := view.position + Vector2(rng.randf() * view.size.x, rng.randf() * view.size.y)
		if island_rect().grow(24).has_point(p):
			continue
		var w := rng.randf_range(18, 40)
		_cloud(p.round(), w)
	# 섬 아래 흙 절벽 (아래로 갈수록 좁아짐)
	var ir := island_rect()
	for k in 4:
		var inset := 6 + k * 18
		var y := ir.end.y + k * 6
		draw_rect(Rect2(ir.position.x + inset, y - 2, ir.size.x - inset * 2, 8), CLIFF[k % 2])
		draw_rect(Rect2(ir.position.x + inset, y + 4, ir.size.x - inset * 2, 1), CLIFF[2])
	# 섬 위: 잔디 칸 (가장자리는 아래쪽에 흙 테두리), 돌길
	for y in SIZE.y:
		for x in SIZE.x:
			var local := Vector2i(x, y)
			if not is_island_cell(local):
				continue
			var at := Vector2((ORIGIN + local) * TILE)
			var coords: Vector2i = TerrainTileSet.PLAZA[(x + y) % 2] if local in PATH_CELLS else TerrainTileSet.GRASS[absi(hash(local)) % TerrainTileSet.GRASS.size()]
			draw_texture_rect_region(Art.TILES, Rect2(at, Vector2(TILE, TILE)), Art.tile_region(coords))
			if not is_island_cell(local + Vector2i.DOWN):
				draw_rect(Rect2(at + Vector2(0, TILE - 3), Vector2(TILE, 3)), CLIFF[2])
				draw_rect(Rect2(at + Vector2(0, TILE), Vector2(TILE, 4)), CLIFF[0])


func _cloud(p: Vector2, w: float) -> void:
	draw_circle(p + Vector2(0, 2), w * 0.32, CLOUD_SHADE)
	draw_circle(p + Vector2(w * 0.3, 3), w * 0.26, CLOUD_SHADE)
	draw_circle(p, w * 0.3, CLOUD)
	draw_circle(p + Vector2(w * 0.28, 1), w * 0.24, CLOUD)
	draw_circle(p + Vector2(-w * 0.26, 2), w * 0.2, CLOUD)
