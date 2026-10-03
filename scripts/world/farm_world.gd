class_name FarmWorld
extends Node2D
## 농장 맵 전체. MapLayout 을 읽어 바닥·울타리 타일을 깔고, 밭 칸을 정하고,
## 나무·바위·건물을 Objects(Y 정렬) 아래에 배치한 뒤 플레이어를 놓는다.

const TILE := Art.TILE
const CAMERA_ZOOM := 4.0

@onready var ground: TileMapLayer = $Ground
@onready var edges: TileMapLayer = $Edges
@onready var details: TileMapLayer = $Details
@onready var farm: FarmGrid = $Farm
@onready var objects: Node2D = $Objects
@onready var fences: TileMapLayer = $Objects/Fences
@onready var player: Player = $Objects/Player
@onready var build: BuildGrid = $Build
@onready var build_mode: BuildMode = $BuildMode
@onready var obstacles: ObstacleGrid = $Obstacles

var buildings: Array[Interactable] = []
## 매일 아침 플레이어가 깨어나는 곳 (맵의 '@', 집 앞)
var home_position := Vector2.ZERO
## 하루 마감 흐름 (scripts/time/day_cycle.gd)
var day_cycle: DayCycle


func _ready() -> void:
	build.world = self
	obstacles.world = self
	# 시설이나 장애물이 있는 칸은 괭이로 갈 수 없다
	farm.blocked = func(cell: Vector2i) -> bool: return build.is_occupied(cell) or obstacles.is_blocked(cell)
	var tile_set := TerrainTileSet.build()
	ground.tile_set = tile_set
	edges.tile_set = tile_set
	details.tile_set = tile_set
	fences.tile_set = tile_set
	_build_map()
	obstacles.generate_start(player.position)
	_build_edges()
	_build_details()
	_setup_camera()
	_add_world_bounds()
	_setup_daylight()
	day_cycle = DayCycle.new()
	day_cycle.name = "DayCycle"
	day_cycle.world = self
	add_child(day_cycle)


func _build_map() -> void:
	var map_size := MapLayout.size()
	for y in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, y)
			var ch := MapLayout.char_at(cell)
			ground.set_cell(cell, TerrainTileSet.SOURCE_ID, _ground_tile(ch, cell))
			var fence: Variant = _fence_tile(ch)
			if fence != null:
				fences.set_cell(cell, TerrainTileSet.SOURCE_ID, fence)
			if ch in MapLayout.FARMABLE:
				farm.farmable_cells[cell] = true
			elif ch == "@":
				home_position = cell_center(cell)
				player.position = home_position
			elif MapLayout.PROPS.has(ch):
				var prop: Node2D = load(MapLayout.PROPS[ch]).instantiate()
				prop.position = cell_center(cell) + Vector2(0, TILE / 2.0 - 2)
				objects.add_child(prop)
			elif MapLayout.BUILDINGS.has(ch):
				var building: Interactable = load(MapLayout.BUILDINGS[ch]).instantiate()
				# 건물 원점은 차지하는 칸들의 왼쪽 아래 (Y 정렬 기준이 발밑이 되도록)
				building.position = Vector2(cell.x * TILE, (cell.y + building.size_tiles.y) * TILE)
				objects.add_child(building)
				buildings.append(building)


## 길·물·흙 칸 옆이 잔디면 그쪽 가장자리에 잔디를 살짝 덮어 경계를 부드럽게 한다.
func _build_edges() -> void:
	var map_size := MapLayout.size()
	for y in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, y)
			var ch := _floor_char_at(cell)
			if not TerrainTileSet.EDGE_ROWS.has(ch):
				continue
			var mask := 0
			for bit: int in [1, 2, 4, 8]:
				var dir: Vector2i = {1: Vector2i.UP, 2: Vector2i.RIGHT, 4: Vector2i.DOWN, 8: Vector2i.LEFT}[bit]
				var other := _floor_char_at(cell + dir)
				if other == "#":
					other = "~"  # 다리 밑은 물로 이어진다
				if other != "" and not TerrainTileSet.EDGE_ROWS.has(other):
					mask |= bit
			if mask:
				edges.set_cell(cell, TerrainTileSet.EDGE_SOURCE_ID, Vector2i(mask, TerrainTileSet.EDGE_ROWS[ch]))


## 넓은 풀밭 얼룩용 노이즈 (따뜻한 풀밭과 보통 잔디가 자연스럽게 섞이게)
var _meadow_noise := _make_noise()


static func _make_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = 7
	n.frequency = 0.09
	return n


## 소품 밑에 깔린 바닥까지 고려한 바닥 글자
func _floor_char_at(cell: Vector2i) -> String:
	var ch := MapLayout.char_at(cell)
	if MapLayout.GROUND_UNDER.get(ch, "") == "p" and _near_plaza(cell):
		return "p"
	return "." if MapLayout.GROUND_UNDER.has(ch) else ch


func _floor_char(ch: String) -> String:
	return MapLayout.GROUND_UNDER.get(ch, ch)


## 상하좌우에 광장 돌바닥이 있는가 (광장 소품·건물 밑을 돌바닥으로 이어 깔기 위해)
func _near_plaza(cell: Vector2i) -> bool:
	for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if MapLayout.char_at(cell + d) == "p":
			return true
	return false


func _ground_tile(ch: String, cell: Vector2i) -> Vector2i:
	var h := absi(hash(cell))
	match ch:
		",":
			return TerrainTileSet.FLOWERS[h % TerrainTileSet.FLOWERS.size()]
		"d", "x":
			return TerrainTileSet.DIRT
		"#":
			return TerrainTileSet.BRIDGE
		"~":
			return TerrainTileSet.WATER
		"s", "@":
			return TerrainTileSet.PATHS[h % TerrainTileSet.PATHS.size()]
		"p":
			return TerrainTileSet.PLAZA[h % TerrainTileSet.PLAZA.size()]
	if MapLayout.GROUND_UNDER.get(ch, "") == "p" and _near_plaza(cell):
		return TerrainTileSet.PLAZA[h % TerrainTileSet.PLAZA.size()]
	# 같은 잔디가 반복돼 보이지 않게 칸마다 다른 무늬, 넓게는 따뜻한 풀밭 얼룩
	if h % 29 == 0:
		return TerrainTileSet.FLOWERS[h % 2]
	if _meadow_noise.get_noise_2d(cell.x, cell.y) > 0.15:
		return TerrainTileSet.GRASS_WARM[h % TerrainTileSet.GRASS_WARM.size()]
	return TerrainTileSet.GRASS[h % TerrainTileSet.GRASS.size()]


## 빈 잔디 칸에 작은 풀·꽃·조약돌을 드문드문 얹는다 (자리는 항상 같게)
const DETAIL_WEIGHTS := [5, 3, 2, 2, 2, 3, 2, 1]


func _build_details() -> void:
	var total := 0
	for w: int in DETAIL_WEIGHTS:
		total += w
	var map_size := MapLayout.size()
	for y in map_size.y:
		for x in map_size.x:
			var cell := Vector2i(x, y)
			if MapLayout.char_at(cell) != ".":
				continue
			var h := absi(hash(cell * 31 + Vector2i(7, 3)))
			if h % 100 >= 14:
				continue
			var pick := (h / 100) % total
			for i in DETAIL_WEIGHTS.size():
				pick -= DETAIL_WEIGHTS[i]
				if pick < 0:
					details.set_cell(cell, TerrainTileSet.DETAIL_SOURCE_ID, Vector2i(i, 0))
					break


func _fence_tile(ch: String) -> Variant:
	match ch:
		"=":
			return TerrainTileSet.FENCE_H
		"!":
			return TerrainTileSet.FENCE_V
		"+":
			return TerrainTileSet.FENCE_POST
	return null


func _setup_camera() -> void:
	var cam := player.camera
	var map_px := Vector2(MapLayout.size() * TILE)
	cam.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(map_px.x)
	cam.limit_bottom = int(map_px.y)
	cam.reset_smoothing()


## 맵 바깥으로 못 나가게 네 변에 보이지 않는 벽을 친다.
func _add_world_bounds() -> void:
	var size_px := Vector2(MapLayout.size() * TILE)
	var body := StaticBody2D.new()
	for r: Rect2 in [
		Rect2(-32, -32, size_px.x + 64, 32),
		Rect2(-32, size_px.y, size_px.x + 64, 32),
		Rect2(-32, 0, 32, size_px.y),
		Rect2(size_px.x, 0, 32, size_px.y),
	]:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size
		shape.shape = rect
		shape.position = r.get_center()
		body.add_child(shape)
	add_child(body)


# ---------- 하루 빛깔 (아침은 따뜻하게, 저녁은 노을, 밤은 푸르게)

const DAYLIGHT := [
	[6 * 60, Color(1.0, 0.96, 0.9)],
	[9 * 60, Color(1.0, 1.0, 1.0)],
	[16 * 60, Color(1.0, 1.0, 0.98)],
	[18 * 60, Color(1.0, 0.86, 0.72)],
	[20 * 60, Color(0.72, 0.7, 0.9)],
	[26 * 60, Color(0.55, 0.58, 0.82)],
]

var _daylight: CanvasModulate


func _setup_daylight() -> void:
	_daylight = CanvasModulate.new()
	add_child(_daylight)
	Events.time_changed.connect(_on_time_changed)
	_on_time_changed(GameState.day, GameState.minutes)


func _on_time_changed(_day: int, minutes: int) -> void:
	var target: Color = DAYLIGHT[-1][1]
	for i in DAYLIGHT.size() - 1:
		var a: Array = DAYLIGHT[i]
		var b: Array = DAYLIGHT[i + 1]
		if minutes >= a[0] and minutes <= b[0]:
			target = (a[1] as Color).lerp(b[1], float(minutes - a[0]) / (b[0] - a[0]))
			break
	var tween := create_tween()
	tween.tween_property(_daylight, "color", target, 1.5)


# ---------- 좌표 도우미

func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0
