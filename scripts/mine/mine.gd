class_name Mine
extends Node2D
## 광산 (사용자 결정: 광장 북쪽 숲길 끝 동굴 입구 → 아래로 내려갈수록 좋은 광석 → 엘리베이터로 오가기).
## 하늘섬·가게 실내처럼 농장 맵 바깥(오른쪽 아래)에 한 층 크기의 자리를 두고, 층을 옮길 때마다 그 자리를 새로 꾸민다.
##   0층 (입구층): 늘 같은 모양. 엘리베이터 · 내려가는 사다리 · 아래쪽 출구 (밟으면 밖으로)
##   1층부터: 들어올 때마다 바위 배치가 새로 생긴다 (저장하지 않음). 바위를 깨면 확률로 내려가는 사다리 (깰수록 잘 나옴, 마지막 바위는 반드시)
##   엘리베이터 정류장: elevator_every 층마다. 그 층에 처음 닿으면 열리고, 입구층·정류장 층의 엘리베이터로 바로 오간다
##   보물 층 (10층마다): 광석이 잔뜩 + 상자 하나 (처음 한 번만)
## 가장 깊이 간 층은 GameState.unlocks["mine_deepest"], 연 상자는 unlocks["mine_chest:<층>"] 에 저장된다.
## 바위는 장애물(Obstacle)을 그대로 쓴다: 이 광산 전용 ObstacleGrid(rocks) 에 깔고, 곡괭이로 치는 것도 같은 규칙 (Player._use_selected).
## 수치는 data/mine.json, 바위 종류는 data/obstacles.json 의 mine_*.

const TILE := Art.TILE
const DATA_PATH := "res://data/mine.json"
## 층 자리 왼쪽 위 칸 (가게 실내 아래쪽 바깥)
const ORIGIN := Vector2i(202, 114)
const SIZE := Vector2i(22, 14)
## 카메라가 볼 여백 (칸). 바깥은 어둡게 칠한다
const MARGIN := Vector2i(20, 12)
const OUTSIDE := Color("120d0a")
## 굴 안 밝기 (낮·밤 상관없이 늘 같은 등불 빛)
const LIGHT := Color(0.86, 0.8, 0.74)

## 입구층에서 고정된 자리 (층 기준 칸)
const ELEVATOR_AT := Vector2i(3, 2)      # 2칸 폭, 그림은 위로 솟음
const ENTRY_LADDER_AT := Vector2i(17, 5)
const EXIT_CELLS := [Vector2i(10, 13), Vector2i(11, 13)]
## 1층부터: 위로 올라가는 사다리(벽에 기댐)와 내려서는 칸, 정류장 층의 엘리베이터 자리
const UP_LADDER_AT := Vector2i(3, 2)
const FLOOR_ELEVATOR_AT := Vector2i(6, 2)
const CHEST_AT := Vector2i(11, 7)

static var _data: Dictionary = {}

var world: FarmWorld
## 이 광산의 바위 (Obstacle). 층을 옮기면 다 지우고 새로 깐다
var rocks: ObstacleGrid
## 지금 꾸며져 있는 층 (-1 = 아직 아무 층도 아님)
var floor_no := -1
var rng := RandomNumberGenerator.new()

var _walls := {}            # 층 기준 칸 -> true
var _floor_variant := {}    # 층 기준 칸 -> 바닥 그림 번호
var _wall_body: StaticBody2D
var _features: Array[Node] = []
var _ladder_found := false
var _broken := 0
var _floor_tex: Texture2D = preload("res://assets/art/mine_floor.png")
var _wall_tex: Texture2D = preload("res://assets/art/mine_wall.png")


static func data() -> Dictionary:
	if _data.is_empty():
		_data = DataFile.load_dict(DATA_PATH)
	return _data


static func bottom() -> int:
	return int(data().get("bottom", 20))


static func elevator_every() -> int:
	return maxi(1, int(data().get("elevator_every", 5)))


static func is_treasure_floor(n: int) -> bool:
	return n in (data().get("treasure", {}).get("floors", []) as Array).map(func(v: Variant) -> int: return int(v))


## 광산 영역 (픽셀): 층 자리 + 둘레 어둠. 플레이어가 이 안에 있으면 광산이다
static func view_rect() -> Rect2:
	return Rect2(Vector2((ORIGIN - MARGIN) * TILE), Vector2((SIZE + MARGIN * 2) * TILE))


## 층 자리 (픽셀). 카메라는 이걸 화면 가운데에 둔다 (FarmWorld._centered_limits)
static func room_rect() -> Rect2:
	return Rect2(Vector2(ORIGIN * TILE), Vector2(SIZE * TILE))


static func contains(pos: Vector2) -> bool:
	return view_rect().has_point(pos)


static func deepest() -> int:
	return int(GameState.unlocks.get("mine_deepest", 0))


## 엘리베이터로 갈 수 있는 층 (0 = 입구층 + 가 본 정류장 층)
static func elevator_stops() -> Array[int]:
	var stops: Array[int] = [0]
	var every := elevator_every()
	for n in range(every, mini(deepest(), bottom()) + 1, every):
		stops.append(n)
	return stops


## 이 층에서 나오는 바위 비율 (from 이 가장 큰 줄)
static func rock_weights(n: int) -> Dictionary:
	if is_treasure_floor(n):
		return data().get("treasure", {}).get("weights", {})
	var result: Dictionary = {}
	for row: Dictionary in data().get("depths", []):
		if n >= int(row.get("from", 1)):
			result = row.get("rocks", {})
	return result


func _ready() -> void:
	rng.randomize()


func build(farm_world: FarmWorld) -> void:
	world = farm_world
	name = "Mine"
	z_index = -1
	rocks = ObstacleGrid.new()
	rocks.name = "MineRocks"
	rocks.world = world
	add_child(rocks)
	rocks.cleared.connect(_on_rock_cleared)
	Events.mine_requested.connect(go_to)
	# 광산 안에서 저장했다가 불러오면 (층은 저장하지 않으니) 입구층 엘리베이터 앞에서 시작한다
	Events.game_loaded.connect(func() -> void:
		if contains(world.player.global_position):
			go_to(0))


# ---------- 층 옮기기

## n 층으로 간다 (0 = 입구층). 층을 새로 꾸미고 플레이어를 내려서는 자리에 놓는다
func go_to(n: int) -> void:
	n = clampi(n, 0, bottom())
	_setup_floor(n)
	world.player.wake_at(arrive_position())
	world.player.facing = Vector2i.DOWN
	if n > deepest():
		GameState.unlocks["mine_deepest"] = n
		if n % elevator_every() == 0:
			Events.toast.emit("엘리베이터 %d층 정류장이 열렸어요." % n)
	world.enter_mine_area()
	Events.travelled.emit("mine")


## 광산 밖 (입구 앞)으로 나간다
func leave() -> void:
	world.exit_mine()


## 이 층에서 내려서는 곳: 입구층은 엘리베이터 앞, 1층부터는 올라가는 사다리 앞
func arrive_position() -> Vector2:
	var local := ELEVATOR_AT + Vector2i(0, 1) if floor_no == 0 else UP_LADDER_AT + Vector2i(0, 1)
	return world.cell_center(ORIGIN + local)


func is_exit(cell: Vector2i) -> bool:
	return floor_no == 0 and (cell - ORIGIN) in EXIT_CELLS


func is_wall(local: Vector2i) -> bool:
	return _walls.has(local)


func has_ladder() -> bool:
	return _ladder_found


func _setup_floor(n: int) -> void:
	_clear_floor()
	floor_no = n
	_broken = 0
	_ladder_found = false
	_make_walls()
	if n == 0:
		_add_feature(MineFeature.Kind.ELEVATOR, ELEVATOR_AT)
		_add_feature(MineFeature.Kind.DOWN, ENTRY_LADDER_AT)
		_ladder_found = true
	else:
		_add_feature(MineFeature.Kind.UP, UP_LADDER_AT)
		if n % elevator_every() == 0:
			_add_feature(MineFeature.Kind.ELEVATOR, FLOOR_ELEVATOR_AT)
		if is_treasure_floor(n) and not GameState.unlocks.get("mine_chest:%d" % n, false):
			_add_feature(MineFeature.Kind.CHEST, CHEST_AT)
		_place_rocks(n)
	_build_wall_body()
	queue_redraw()


func _clear_floor() -> void:
	rocks.clear()
	for f in _features:
		if is_instance_valid(f):
			f.queue_free()
	_features.clear()
	_walls.clear()
	_floor_variant.clear()


## 둘레 벽 (위는 두 줄: 굴 벽면) + 울퉁불퉁하게 벽 가장자리에 혹. 1층부터는 가운데에 작은 바위 기둥 몇 개
func _make_walls() -> void:
	var gen := RandomNumberGenerator.new()
	gen.seed = 4242 if floor_no == 0 else rng.randi()
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			_floor_variant[c] = gen.randi() % 4
			var edge := x == 0 or x == SIZE.x - 1 or y <= 1 or y == SIZE.y - 1
			var bump := (x == 1 or x == SIZE.x - 2 or y == 2 or y == SIZE.y - 2) and gen.randf() < 0.3
			if edge or bump:
				_walls[c] = true
	if floor_no > 0:
		for i in gen.randi_range(1, 3):
			var p := Vector2i(gen.randi_range(5, SIZE.x - 7), gen.randi_range(5, SIZE.y - 5))
			for d: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
				_walls[p + d] = true
	# 꼭 비워 둘 칸: 사다리·엘리베이터·출구와 그 앞, 상자
	var keep: Array[Vector2i] = []
	if floor_no == 0:
		keep = [ELEVATOR_AT, ELEVATOR_AT + Vector2i.RIGHT, ELEVATOR_AT + Vector2i.DOWN, ELEVATOR_AT + Vector2i(1, 1),
				ENTRY_LADDER_AT, ENTRY_LADDER_AT + Vector2i.DOWN, ENTRY_LADDER_AT + Vector2i.LEFT]
		for c: Vector2i in EXIT_CELLS:
			keep.append(c)
			keep.append(c + Vector2i.UP)
	else:
		keep = [UP_LADDER_AT, UP_LADDER_AT + Vector2i.DOWN, UP_LADDER_AT + Vector2i(1, 1), CHEST_AT, CHEST_AT + Vector2i.DOWN,
				FLOOR_ELEVATOR_AT, FLOOR_ELEVATOR_AT + Vector2i.RIGHT, FLOOR_ELEVATOR_AT + Vector2i.DOWN, FLOOR_ELEVATOR_AT + Vector2i(1, 1)]
	for c in keep:
		_walls.erase(c)


func _place_rocks(n: int) -> void:
	var range_key := "rocks"
	var counts: Array = data().get("treasure", {}).get(range_key, [40, 48]) if is_treasure_floor(n) else data().get(range_key, [26, 36])
	var want := rng.randi_range(int(counts[0]), int(counts[1]))
	var weights := rock_weights(n)
	var free: Array[Vector2i] = []
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			if _walls.has(c) or c.distance_to(UP_LADDER_AT + Vector2i.DOWN) < 2.5 or _feature_near(c):
				continue
			free.append(c)
	free.shuffle()
	for i in mini(want, free.size()):
		rocks.spawn(ORIGIN + free[i], ObstacleDB.pick_weighted(weights, rng), rng.randi())


func _feature_near(c: Vector2i) -> bool:
	for f: MineFeature in _features:
		if c.distance_to(f.cell - ORIGIN) < 2.0 or (f.kind == MineFeature.Kind.ELEVATOR and c.distance_to(f.cell - ORIGIN + Vector2i.RIGHT) < 2.0):
			return true
	return false


func _add_feature(kind: MineFeature.Kind, local: Vector2i) -> MineFeature:
	var f := MineFeature.new()
	f.setup(self, kind, ORIGIN + local)
	world.objects.add_child(f)
	_features.append(f)
	return f


func _build_wall_body() -> void:
	if _wall_body:
		_wall_body.queue_free()
	_wall_body = StaticBody2D.new()
	var cells: Array = _walls.keys()
	# 출구 바깥 줄도 막는다 (밟으면 나가는 칸 아래로 걸어 나가지 않게)
	for x in SIZE.x:
		cells.append(Vector2i(x, SIZE.y))
	for c: Vector2i in cells:
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(TILE, TILE)
		shape.shape = rect
		shape.position = Vector2((ORIGIN + c) * TILE) + Vector2.ONE * TILE / 2.0
		_wall_body.add_child(shape)
	add_child(_wall_body)


# ---------- 바위·사다리·상자

## 바위를 깼다: 확률로 내려가는 사다리 (깰수록 잘 나오고, 마지막 바위는 반드시). 맨 아래층은 없음
func _on_rock_cleared(cell: Vector2i, _def: ObstacleDef) -> void:
	_broken += 1
	if _ladder_found or floor_no <= 0 or floor_no >= bottom():
		return
	var cfg: Dictionary = data().get("ladder", {})
	var chance := float(cfg.get("base", 0.04)) + float(cfg.get("per_rock", 0.025)) * _broken
	if rocks.count() == 0 or rng.randf() < chance:
		_ladder_found = true
		_add_feature(MineFeature.Kind.DOWN, cell - ORIGIN)
		Events.toast.emit("아래로 내려가는 사다리를 찾았어요!")


## 보물 상자를 연다 (처음 한 번만). 가방이 모자라면 열지 않는다
func open_chest(chest: MineFeature) -> void:
	var reward: Dictionary = data().get("treasure", {}).get("chest", {}).get(str(floor_no), {})
	var items: Dictionary = reward.get("items", {})
	for item_id: String in items:
		if not GameState.inventory.can_add(item_id, int(items[item_id])):
			Events.toast.emit("가방이 가득 차서 상자를 열 수 없어요.")
			return
	var got: Array[String] = []
	var money := int(reward.get("money", 0))
	if money > 0:
		GameState.add_money(money)
		got.append("%d G" % money)
	for item_id: String in items:
		GameState.inventory.add(item_id, int(items[item_id]))
		got.append("%s +%d" % [ItemDB.get_item(item_id).name, int(items[item_id])])
	GameState.unlocks["mine_chest:%d" % floor_no] = true
	_features.erase(chest)
	chest.queue_free()
	Events.toast.emit("보물 상자! " + " · ".join(got))


# ---------- 그림

func _draw() -> void:
	draw_rect(view_rect(), OUTSIDE)
	if floor_no < 0:
		return
	for y in SIZE.y:
		for x in SIZE.x:
			var c := Vector2i(x, y)
			var at := Rect2(Vector2((ORIGIN + c) * TILE), Vector2(TILE, TILE))
			if _walls.has(c):
				draw_texture_rect_region(_wall_tex, at, Rect2((x + y) % 2 * TILE, 0, TILE, TILE))
			else:
				draw_texture_rect_region(_floor_tex, at, Rect2(int(_floor_variant.get(c, 0)) * TILE, 0, TILE, TILE))
	if floor_no == 0:
		# 출구: 밖에서 들어오는 햇빛
		for c: Vector2i in EXIT_CELLS:
			draw_rect(Rect2(Vector2((ORIGIN + c) * TILE), Vector2(TILE, TILE)), Color("d9b98a"))
			draw_rect(Rect2(Vector2((ORIGIN + c + Vector2i.UP) * TILE), Vector2(TILE, TILE)), Color(0.95, 0.85, 0.6, 0.25))
