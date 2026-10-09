class_name Conveyor
extends Placeable
## 컨베이어 한 칸 (BUILD_FARM_PLAN §56~§61). 화살표 방향(facing)으로 물건을 옮긴다.
## 물건을 옮기는 일은 ConveyorNet 이 벨트 전체를 한꺼번에 처리한다 (이 노드는 상태와 그림만 맡는다).
##
## 규칙
##   - 한 칸에 물건 1개. progress 0 = 들어온 쪽 가장자리, 1 = 나가는 쪽 가장자리
##   - 다음 칸(벨트 또는 시설 입구)이 받지 못하면 끝에서 기다리고, 뒤 칸들도 차례로 밀린다 (§61, 아이템은 사라지지 않음)
##   - 플레이어 이동을 막지 않는다 (§56). 땅에 깔린 것이라 나무·시설·플레이어보다 아래에 그린다
##   - 모양(직선 / 왼쪽에서 꺾임 / 오른쪽에서 꺾임)은 이웃 벨트·시설 출구를 보고 저절로 정해진다 (§58)
## 철거하면 벨트 위 물건도 가방으로 돌려준다 (§106, BuildMode 가 contents 로 처리).

## conveyor.png 의 줄: 직선 / 왼쪽에서 들어와 꺾임 / 오른쪽에서 들어와 꺾임 (회전 0 = 아래로 흐름 기준)
enum Shape { STRAIGHT, FROM_LEFT, FROM_RIGHT }

const SHEET := preload("res://assets/art/conveyor.png")
const FRAMES := 4
## 벨트 위 물건 그림 크기 (픽셀)
const ITEM_SIZE := 10.0
const LAYER := "Belts"

## 벨트 위 물건 {"id", "quality"} (없으면 빈 사전)
var item: Dictionary = {}
var progress := 0.0
var shape := Shape.STRAIGHT
## 물건이 들어올 때 움직인 방향 (분배기·합류기가 어느 쪽에서 들어왔는지 그릴 때 쓴다)
var came_dir := Vector2i.ZERO

var _belt: Sprite2D
var _frame := 0


func _ready() -> void:
	super._ready()
	_belt = Sprite2D.new()
	_belt.texture = SHEET
	_belt.region_enabled = true
	_belt.show_behind_parent = true
	_belt.position = Vector2(0, -TILE / 2.0)
	add_child(_belt)
	_update_belt()


func _update_visual() -> void:
	super._update_visual()
	_update_belt()


func set_shape(new_shape: Shape) -> void:
	if shape != new_shape:
		shape = new_shape
		_update_belt()
		queue_redraw()


## 벨트 무늬 움직임 (ConveyorNet 이 물건이 흐른 거리만큼 넘긴다 — 시계가 멈추면 같이 멈춘다)
func set_frame(f: int) -> void:
	f = posmod(f, FRAMES)
	if f != _frame:
		_frame = f
		_update_belt()


func _update_belt() -> void:
	if _belt == null:
		return
	_belt.region_rect = Rect2(_frame * TILE, int(shape) * TILE, TILE, TILE)
	_belt.rotation = turns * PI / 2.0


## 물건이 들어오는 쪽 (이 칸에서 본 방향)
func entry_dir() -> Vector2i:
	match shape:
		Shape.FROM_LEFT:
			return rotate_dir(Vector2i.LEFT, turns)
		Shape.FROM_RIGHT:
			return rotate_dir(Vector2i.RIGHT, turns)
	return -facing()


func has_item() -> bool:
	return not item.is_empty()


## 물건을 올린다 (비어 있을 때만). from_dir = 들어오며 움직인 방향
func put(item_id: String, quality: String, at := 0.0, from_dir := Vector2i.ZERO) -> bool:
	if has_item() or not ItemDB.has_item(item_id):
		return false
	item = {"id": item_id, "quality": quality}
	progress = clampf(at, 0.0, 1.0)
	came_dir = from_dir
	queue_redraw()
	return true


# ---------- 연결 규칙 (ConveyorNet 이 쓴다. 분배기·합류기(Router)가 덮어쓴다)

## d 방향으로 움직여 온 물건을 이 칸이 받는 모양인가 (비었는지는 보지 않음). 벨트: 마주 보며 들어오는 것만 아니면
func accepts_dir(d: Vector2i) -> bool:
	return d != -facing()


## 지금 d 방향으로 들어오는 물건을 받을 수 있는가
func can_take(d: Vector2i, _grid: BuildGrid) -> bool:
	return not has_item() and accepts_dir(d)


## 지금 물건을 내보낼 방향들 (앞에서부터 시도). 벨트: 앞 하나
func exit_dirs() -> Array[Vector2i]:
	var out: Array[Vector2i] = [facing()]
	return out


## 내보낼 수 있는 모든 방향 (물건과 상관없이, 순서 계산·모양용)
func all_exit_dirs() -> Array[Vector2i]:
	var out: Array[Vector2i] = [facing()]
	return out


## d 방향으로 내보냈을 때 (분배기가 다음 차례를 정한다)
func on_sent(_d: Vector2i) -> void:
	pass


func clear_item() -> void:
	item = {}
	progress = 0.0
	queue_redraw()


## 물건이 그려질 자리 (노드 기준). 들어온 가장자리 → 칸 가운데 → 나가는 가장자리를 잇는 곡선
func item_position() -> Vector2:
	var center := Vector2(0, -TILE / 2.0)
	var a := Vector2(entry_dir()) * (TILE / 2.0)
	var b := Vector2(facing()) * (TILE / 2.0)
	var t := clampf(progress, 0.0, 1.0)
	return center + a * (1.0 - t) * (1.0 - t) + b * t * t


func _draw() -> void:
	if not has_item():
		return
	var it := ItemDB.get_item(str(item.id))
	if it == null:
		return
	var p := item_position().round()
	draw_circle(p + Vector2(0, 3), ITEM_SIZE * 0.35, Color(0.36, 0.23, 0.16, 0.35))
	draw_texture_rect_region(Art.ITEMS, Rect2(p - Vector2.ONE * ITEM_SIZE / 2.0, Vector2.ONE * ITEM_SIZE), Art.item_region(it))


# ---------- Placeable 훅

## 땅에 깔린 것이라 나무·시설·플레이어(Y 정렬되는 Objects)보다 아래 층으로 옮긴다
func on_placed(world: FarmWorld) -> void:
	var layer := world.get_node_or_null(LAYER)
	if layer == null:
		layer = Node2D.new()
		layer.name = LAYER
		world.add_child(layer)
		world.move_child(layer, world.objects.get_index())
	if get_parent() != layer:
		reparent(layer)


func contents() -> Array:
	return [{"id": item.id, "count": 1, "quality": item.quality}] if has_item() else []


func take_contents() -> void:
	clear_item()


func save_state() -> Dictionary:
	return {"item": item.duplicate(), "progress": snappedf(progress, 0.001)} if has_item() else {}


func load_state(data: Dictionary) -> void:
	var raw: Variant = data.get("item")
	if raw is Dictionary and ItemDB.has_item(str(raw.get("id", ""))):
		var it := ItemDB.get_item(str(raw.id))
		var at := float(data.get("progress", 0.0)) if typeof(data.get("progress")) in [TYPE_INT, TYPE_FLOAT] else 0.0
		put(it.id, Quality.normalize(it, str(raw.get("quality", ""))), at)
