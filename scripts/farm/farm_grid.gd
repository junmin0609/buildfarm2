class_name FarmGrid
extends Node2D
## 격자 기반 농사. 갈아 놓은 밭과 작물 상태를 칸 단위로 들고 있고 직접 그린다.
## 나중에 스프링클러 같은 자동화는 till/water/plant/harvest 를 그대로 불러 쓰면 된다.

signal tile_changed(cell: Vector2i)

const TILE := Art.TILE

## 밭으로 갈 수 있는 칸 (맵에서 'd')
var farmable_cells: Dictionary = {}  # Vector2i -> true
## 갈아 놓은 칸
var tiles: Dictionary = {}  # Vector2i -> SoilTile
## 칸이 다른 것(설치된 시설 등)으로 막혀 있는지 알려 주는 함수. FarmWorld 가 넣어 준다.
var blocked: Callable

## 수확량·품질 뽑기용
var rng := RandomNumberGenerator.new()

var _cursor_cell := Vector2i.ZERO
var _cursor_visible := false


var _pulse := 0.0


func _ready() -> void:
	rng.randomize()
	Events.day_started.connect(_on_day_started)


func _process(delta: float) -> void:
	if _cursor_visible:
		_pulse += delta
		queue_redraw()


# ---------- 밭 조작 (자동화·저장 기능도 이 함수들을 쓴다)

func is_farmable(cell: Vector2i) -> bool:
	return farmable_cells.has(cell)


func get_tile(cell: Vector2i) -> SoilTile:
	return tiles.get(cell)


func till(cell: Vector2i) -> bool:
	if not is_farmable(cell) or tiles.has(cell):
		return false
	if blocked.is_valid() and blocked.call(cell):
		return false
	tiles[cell] = SoilTile.new()
	_changed(cell)
	return true


## 갈아 둔 밭을 보통 땅으로 되돌린다 (시설을 지을 때). 작물이 있으면 되돌리지 않는다.
func untill(cell: Vector2i) -> bool:
	var tile := get_tile(cell)
	if tile == null or tile.has_crop():
		return false
	tiles.erase(cell)
	_changed(cell)
	return true


func water(cell: Vector2i) -> bool:
	var tile := get_tile(cell)
	if tile == null or tile.watered:
		return false
	tile.watered = true
	_changed(cell)
	return true


func plant(cell: Vector2i, seed_def: ItemDef) -> bool:
	var tile := get_tile(cell)
	if seed_def == null or seed_def.kind != ItemDef.Kind.SEED:
		return false
	if tile == null:
		if is_farmable(cell):
			Events.toast.emit("먼저 괭이로 땅을 갈아 주세요.")
		return false
	if tile.has_crop():
		return false
	tile.seed_id = seed_def.id
	tile.days_grown = 0
	tile.regrowing = false
	_changed(cell)
	return true


## 다 자란 작물에서 무엇이 몇 개, 어떤 품질로 나올지 정한다. 밭은 아직 그대로다.
## 돌려주는 값: {"id": 작물 id, "count": 개수, "quality": 품질} (거둘 게 없으면 빈 사전)
## 받을 자리가 있는지 확인한 뒤 finish_harvest 로 확정한다 (자리가 없으면 작물이 그대로 남는다).
func roll_harvest(cell: Vector2i) -> Dictionary:
	var tile := get_tile(cell)
	if tile == null or not tile.is_mature():
		return {}
	var seed_def := tile.seed_item()
	return {
		"id": seed_def.grows,
		"count": rng.randi_range(seed_def.yield_min, seed_def.yield_max),
		"quality": Quality.roll(rng),
	}


## 수확을 확정한다: 한 번 거두는 작물은 사라지고, 다시 열리는 작물은 남아서 다시 자란다.
func finish_harvest(cell: Vector2i) -> void:
	var tile := get_tile(cell)
	if tile == null or not tile.is_mature():
		return
	tile.after_harvest()
	_changed(cell)


## 거둘 곳이 따로 정해진 자동화용: 뽑고 바로 확정한다.
func harvest(cell: Vector2i) -> Dictionary:
	var result := roll_harvest(cell)
	if not result.is_empty():
		finish_harvest(cell)
	return result


## 작물을 뽑는다 (§29). 씨앗은 돌려주지 않고, 밭(갈아 둔 흙·물 준 상태)은 그대로 남는다.
## 다시 열리는 작물도 포기째 사라진다. 뽑을 작물이 없으면 false.
func remove_crop(cell: Vector2i) -> bool:
	var tile := get_tile(cell)
	if tile == null or not tile.has_crop():
		return false
	tile.seed_id = ""
	tile.days_grown = 0
	tile.regrowing = false
	_changed(cell)
	return true


## 작물을 뽑을 수 있는 도구 (§29: 괭이·곡괭이)
static func removes_crops(item: ItemDef) -> bool:
	return item != null and item.kind == ItemDef.Kind.TOOL and item.tool_type in ["hoe", "pickaxe"]


func mature_produce_at(cell: Vector2i) -> String:
	var tile := get_tile(cell)
	return tile.seed_item().grows if tile != null and tile.is_mature() else ""


## 손에 든 아이템을 칸에 쓴다. 새 도구는 여기에 한 줄 추가하면 된다.
## 괭이·곡괭이로 작물이 있는 칸을 치면 작물을 뽑는다 (다 자란 작물은 그 전에 수확된다: Player 가 수확을 먼저 처리).
func use_item(cell: Vector2i, item: ItemDef) -> bool:
	if item == null:
		return false
	if removes_crops(item) and get_tile(cell) != null and get_tile(cell).has_crop():
		if remove_crop(cell):
			Events.toast.emit("작물을 뽑았어요. (씨앗은 돌아오지 않아요)")
			return true
		return false
	match item.kind:
		ItemDef.Kind.TOOL:
			match item.tool_type:
				"hoe":
					return till(cell)
				"watering_can":
					return water(cell)
		ItemDef.Kind.SEED:
			return plant(cell, item)
	return false


func set_cursor(cell: Vector2i, visible_now: bool) -> void:
	if cell == _cursor_cell and visible_now == _cursor_visible:
		return
	_cursor_cell = cell
	_cursor_visible = visible_now
	queue_redraw()


func _on_day_started(_day: int) -> void:
	for tile: SoilTile in tiles.values():
		tile.advance_day()
	queue_redraw()


func _changed(cell: Vector2i) -> void:
	tile_changed.emit(cell)
	queue_redraw()


# ---------- 저장용

func to_data() -> Dictionary:
	var out := {}
	for cell: Vector2i in tiles:
		out["%d,%d" % [cell.x, cell.y]] = tiles[cell].to_dict()
	return out


func load_data(data: Dictionary) -> void:
	tiles.clear()
	for key: String in data:
		var parts := key.split(",")
		tiles[Vector2i(int(parts[0]), int(parts[1]))] = SoilTile.from_dict(data[key])
	queue_redraw()


# ---------- 그리기 (tiles.png 의 밭 그림 + crops.png 의 작물 단계)

func _draw() -> void:
	for cell: Vector2i in tiles:
		var tile: SoilTile = tiles[cell]
		var rect := Rect2(Vector2(cell * TILE), Vector2(TILE, TILE))
		var soil := TerrainTileSet.SOIL_WET if tile.watered else TerrainTileSet.SOIL
		draw_texture_rect_region(Art.TILES, rect, Art.tile_region(soil))
		if tile.has_crop():
			var seed_def := tile.seed_item()
			var crop_rect := Rect2(crop_stage(tile) * TILE, seed_def.crop_row * TILE, TILE, TILE)
			draw_texture_rect_region(Art.CROPS, Rect2(rect.position + Vector2(0, -2), rect.size), crop_rect)
	if _cursor_visible:
		var r := Rect2(Vector2(_cursor_cell * TILE), Vector2(TILE, TILE))
		var glow := 0.6 + 0.3 * sin(_pulse * 4.0)
		draw_rect(r.grow(-3), Color(1, 0.97, 0.88, 0.12 * glow))
		draw_texture_rect_region(Art.TILES, r, Art.tile_region(TerrainTileSet.CURSOR), Color(1, 1, 1, glow))


## crops.png 의 칸: 0 씨앗, 1 새싹, 2 어린 잎, 3 다 큰 잎, 4 수확 가능
## 다시 열리는 중인 작물은 잎이 다 큰 채로 열매만 기다린다.
static func crop_stage(tile: SoilTile) -> int:
	var g := tile.growth()
	if tile.is_mature():
		return 4
	if tile.regrowing:
		return 3
	if g <= 0.0:
		return 0
	if g < 0.4:
		return 1
	if g < 0.75:
		return 2
	return 3
