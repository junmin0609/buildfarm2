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
## 농장 출하함 (맵의 'O')
var shipping_bin: ShippingBin
## 하루 마감 흐름 (scripts/time/day_cycle.gd)
var day_cycle: DayCycle
## 저장 / 불러오기 (scripts/save/save_manager.gd)
var save_manager: SaveManager


func _ready() -> void:
	add_to_group("farm_world")  # HUD 전력 표시처럼 월드를 찾아야 하는 UI 용
	build.world = self
	obstacles.world = self
	# 시설이나 장애물이 있는 칸은 괭이로 갈 수 없다 (온실 안쪽 밭은 된다)
	farm.blocked = func(cell: Vector2i) -> bool: return build.blocks_farming(cell) or obstacles.is_blocked(cell)
	var tile_set := TerrainTileSet.build()
	ground.tile_set = tile_set
	edges.tile_set = tile_set
	details.tile_set = tile_set
	fences.tile_set = tile_set
	_edge_corners = TileMapLayer.new()
	_edge_corners.name = "EdgeCorners"
	_edge_corners.tile_set = tile_set
	add_child(_edge_corners)
	move_child(_edge_corners, edges.get_index() + 1)
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
	# 맵·장애물을 새 게임 상태로 다 만든 뒤에 붙인다 (저장이 있으면 여기서 불러온다)
	save_manager = SaveManager.new()
	save_manager.name = "SaveManager"
	save_manager.world = self
	add_child(save_manager)


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
			elif ch == "T":
				_place_tree(cell)
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
				if building is ShippingBin:
					shipping_bin = building


# ---------- 나무 / 숲 (비주얼만: 칸·충돌은 예전과 같다)

## 나무 변형: 그림, 발밑(그림 안 바닥 가운데), 고를 비중. 열매 나무는 드물게
const TREE_VARIANTS := [
	["res://assets/art/tree_wide.png", Vector2(19, 34), 3],
	["res://assets/art/tree_tall.png", Vector2(15, 42), 3],
	["res://assets/art/tree_lean.png", Vector2(18, 38), 3],
	["res://assets/art/tree_fruit.png", Vector2(17, 36), 1],
]
const UNDERGROWTH := ["res://assets/art/undergrowth_0.png", "res://assets/art/undergrowth_1.png"]
## 나무 밑동 충돌 (예전 tree.tscn 과 같음)
const TREE_COLLISION := Rect2(-4, -5, 9, 5)


func _is_tree(cell: Vector2i) -> bool:
	var size := MapLayout.size()
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
		return true  # 맵 밖은 숲이 이어진다고 본다
	return MapLayout.char_at(cell) == "T"


## 칸마다 정해진 나무 변형 번호 (비중대로). 왼쪽·위 이웃과 같은 모양이 이어지지 않게 한 칸 밀어 준다
func _tree_variant(cell: Vector2i) -> int:
	var v := _weighted_variant(cell)
	if v == _weighted_variant(cell + Vector2i.LEFT):
		v = (v + 1) % TREE_VARIANTS.size()
	if v == _weighted_variant(cell + Vector2i.UP):
		v = (v + 2) % TREE_VARIANTS.size()
	return v


func _weighted_variant(cell: Vector2i) -> int:
	var total := 0
	for t: Array in TREE_VARIANTS:
		total += int(t[2])
	var pick := absi(hash(cell * 13 + Vector2i(5, 9))) % total
	for i in TREE_VARIANTS.size():
		pick -= int(TREE_VARIANTS[i][2])
		if pick < 0:
			return i
	return 0


func _place_tree(cell: Vector2i) -> void:
	var h := absi(hash(cell * 7 + Vector2i(3, 11)))
	var open_dirs: Array[Vector2i] = []
	for d: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
		if not _is_tree(cell + d):
			open_dirs.append(d)
	var interior := open_dirs.is_empty() and _is_tree(cell + Vector2i(1, 1)) and _is_tree(cell + Vector2i(-1, 1)) \
			and _is_tree(cell + Vector2i(1, -1)) and _is_tree(cell + Vector2i(-1, -1))
	var prop := Prop.new()
	prop.collision = TREE_COLLISION
	var edge := not open_dirs.is_empty()
	# 숲 깊은 곳은 가끔 나무 그림을 빼서 작은 빈 틈을 만든다 (막힘은 그대로: 바깥 나무와 맵 경계가 막는다)
	if interior and h % 9 == 0:
		prop.texture = null
	elif edge and (h / 3) % 5 == 0:
		# 가장자리 나무 몇 그루는 어린 나무로 — 숲 경계선에 들쭉날쭉한 틈이 생긴다 (밑동 충돌은 같다)
		prop.texture = load("res://assets/art/young_tree.png")
		prop.foot = Vector2(8, 23)
	else:
		var v: Array = TREE_VARIANTS[_tree_variant(cell)]
		prop.texture = load(v[0])
		prop.foot = v[1]
	# 칸 중심에서 조금씩 어긋나게 (가로 ±3px, 세로 -2~+1px) — 숲 가장자리가 자로 잰 듯 보이지 않게
	var jitter := Vector2(float(h % 7) - 3.0, float((h / 7) % 4) - 2.0)
	if edge:
		jitter += Vector2(open_dirs[0]) * float((h / 11) % 5)  # 가장자리 나무는 트인 쪽으로 0~4px 더 나오거나 들어간다
	prop.position = cell_center(cell) + Vector2(0, TILE / 2.0 - 2) + jitter
	if not edge:
		prop.modulate = Color(0.9, 0.94, 0.9)  # 숲 안쪽은 살짝 어둡게: 가장자리 나무가 앞으로 나와 보이고 숲에 깊이가 생긴다
	objects.add_child(prop)
	# 숲 가장자리(트인 쪽이 있는 나무) 앞에 작은 수풀 (지나갈 수 있는 장식)
	if edge and (h / 28) % 2 == 0:
		var d: Vector2i = open_dirs[(h / 84) % open_dirs.size()]
		var bush := Prop.new()
		bush.texture = load(UNDERGROWTH[(h / 5) % UNDERGROWTH.size()])
		bush.foot = Vector2(8, 12)
		bush.solid = false
		bush.position = prop.position + Vector2(d) * Vector2(9, 5) + Vector2(0, 3)
		objects.add_child(bush)


## 길·물·흙 칸 옆이 잔디면 그쪽 가장자리에 잔디를 살짝 덮어 경계를 부드럽게 한다.
## 같은 무늬가 줄지어 반복되지 않게 칸마다 경계 변형을 고르고(EDGE_VARIANTS),
## 대각선 이웃만 잔디인 안쪽 모서리는 따로 둥글린다 (_edge_corners 층).
var _edge_corners: TileMapLayer


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
			var kind: int = TerrainTileSet.EDGE_ROWS[ch]
			if mask:
				var variant := absi(hash(cell * 5 + Vector2i(1, 2))) % TerrainTileSet.EDGE_VARIANTS
				edges.set_cell(cell, TerrainTileSet.EDGE_SOURCE_ID, Vector2i(mask, kind * TerrainTileSet.EDGE_VARIANTS + variant))
			var corner := 0
			for entry: Array in [[1, Vector2i(1, -1)], [2, Vector2i(1, 1)], [4, Vector2i(-1, 1)], [8, Vector2i(-1, -1)]]:
				var diag: Vector2i = entry[1]
				if _is_grass_neighbor(cell + diag) and not _is_grass_neighbor(cell + Vector2i(diag.x, 0)) \
						and not _is_grass_neighbor(cell + Vector2i(0, diag.y)):
					corner |= int(entry[0])
			if corner:
				_edge_corners.set_cell(cell, TerrainTileSet.EDGE_CORNER_SOURCE_ID, Vector2i(corner, kind))


## 경계를 덮어야 하는 잔디 쪽 이웃인가 (길·물·흙이 아니고 맵 안)
func _is_grass_neighbor(cell: Vector2i) -> bool:
	var other := _floor_char_at(cell)
	if other == "#":
		other = "~"
	return other != "" and not TerrainTileSet.EDGE_ROWS.has(other)


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
## 0 풀, 1 긴 풀, 2~4 꽃, 5 클로버, 6 조약돌, 7 버섯, 8 작은 풀잎, 9 어두운 얼룩, 10 밝은 얼룩, 11 작은 돌, 12 잡초, 13 작은 흰 꽃
const DETAIL_WEIGHTS := [5, 3, 2, 2, 2, 3, 2, 1, 7, 7, 6, 2, 1, 2]
## 장식이 놓이는 잔디 칸 비율 (%). 너무 많으면 지저분해진다
const DETAIL_PERCENT := 22


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
			if h % 100 >= DETAIL_PERCENT:
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
	_fit_camera_zoom()
	if not get_viewport().size_changed.is_connected(_fit_camera_zoom):
		get_viewport().size_changed.connect(_fit_camera_zoom)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(map_px.x)
	cam.limit_bottom = int(map_px.y)
	cam.reset_smoothing()


## 화면 크기 대응 (project.godot: stretch mode canvas_items, aspect expand)
##   UI 와 월드는 창 크기에 맞춰 함께 커지고(기본 1280x720 기준), 화면 비율이 달라지면 보이는 월드가 넓어진다.
##   그런데 창 배율 s 가 소수(예: 1700x1000 창이면 1.33)면 도트 한 칸이 4×1.33 = 5.3px 로 그려져 픽셀 크기가 들쭉날쭉해진다.
##   그래서 카메라 줌을 살짝 조정해 "창 배율 × 줌"이 항상 정수가 되게 한다 → 어떤 창 크기에서도 도트가 고르게 선명.
func _fit_camera_zoom() -> void:
	var visible := get_viewport().get_visible_rect().size
	if visible.x <= 0.0:
		return
	var s := float(get_window().size.x) / visible.x   # canvas_items 늘이기 배율
	if s <= 0.0:
		s = 1.0
	var pixel := maxf(1.0, roundf(CAMERA_ZOOM * s))   # 도트 한 칸이 화면에서 차지할 실제 픽셀 수 (정수)
	player.camera.zoom = Vector2.ONE * (pixel / s)


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
	Events.weather_changed.connect(func(_w: String) -> void: _on_time_changed(GameState.day, GameState.minutes))
	_on_time_changed(GameState.day, GameState.minutes)


func _on_time_changed(_day: int, minutes: int) -> void:
	var target: Color = DAYLIGHT[-1][1]
	for i in DAYLIGHT.size() - 1:
		var a: Array = DAYLIGHT[i]
		var b: Array = DAYLIGHT[i + 1]
		if minutes >= a[0] and minutes <= b[0]:
			target = (a[1] as Color).lerp(b[1], float(minutes - a[0]) / (b[0] - a[0]))
			break
	target *= Weather.tint(GameState.weather)  # 흐림·비·눈은 조금 어둡고 푸르게
	var tween := create_tween()
	tween.tween_property(_daylight, "color", target, 1.5)


# ---------- 좌표 도우미

func world_to_cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE), floori(pos.y / TILE))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE) + Vector2(TILE, TILE) / 2.0
