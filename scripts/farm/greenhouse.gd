class_name Greenhouse
extends Placeable
## 온실 (BUILD_FARM_PLAN §35). 건설 모드로 농장에 짓는 큰 건물. 크기·문 너비는 placeables.json.
##   - 바깥 한 줄은 유리벽 (지나갈 수 없음). 앞벽 가운데 "door_width" 칸이 문
##   - 안쪽 칸은 온실 밭: 맵 글자와 상관없이 괭이로 갈 수 있다 (FarmGrid.indoor_cells)
##   - 계절 제한 없음: 어느 계절 작물이든 심고, 계절이 바뀌어도 시들지 않고, 빈 밭도 되돌아가지 않는다
##   - 날씨 영향 없음: 비가 와도 젖지 않는다 (물뿌리개로 물을 줘야 한다)
##   - 안에 작물이 있으면 옮기거나 철거할 수 없다 (§105 아이템이 사라지지 않게)
## 그림은 지붕 없이 벽만 있어서 안쪽 밭이 그대로 보인다. 플레이어가 벽 앞뒤로 자연스럽게 가려지도록
## 뒷벽·옆벽·앞벽을 따로 잘라 Y 정렬에 맡긴다.

## 지금 등록해 둔 안쪽 밭 칸 (옮길 때 이전 자리를 지우려고 들고 있다)
var _indoor: Array[Vector2i] = []
var _indoor_set := {}
var _walls: StaticBody2D
var _pieces: Array[Sprite2D] = []


func door_width() -> int:
	return clampi(int(def.data.get("door_width", 2)), 1, maxi(1, size().x - 2))


## 안쪽 밭 칸 (바깥 한 줄을 뺀 나머지)
func indoor_cells() -> Array[Vector2i]:
	var s := size()
	var out: Array[Vector2i] = []
	for y in range(1, s.y - 1):
		for x in range(1, s.x - 1):
			out.append(cell + Vector2i(x, y))
	return out


## 앞벽(맨 아래 줄)의 문 칸
func door_cells() -> Array[Vector2i]:
	var s := size()
	var start := (s.x - door_width()) / 2
	var out: Array[Vector2i] = []
	for x in door_width():
		out.append(cell + Vector2i(start + x, s.y - 1))
	return out


func allows_farming(c: Vector2i) -> bool:
	return _indoor_set.has(c)


func removal_problem(world: FarmWorld) -> String:
	for c in _indoor:
		var tile := world.farm.get_tile(c)
		if tile != null and tile.has_crop():
			return "온실 안 작물을 먼저 거두거나 뽑아야 해요."
	return ""


func on_placed(world: FarmWorld) -> void:
	_register_indoor(world)


func on_moved(world: FarmWorld) -> void:
	_unregister_indoor(world)
	_register_indoor(world)


func on_removed(world: FarmWorld) -> void:
	_unregister_indoor(world)


func _register_indoor(world: FarmWorld) -> void:
	_indoor = indoor_cells()
	_indoor_set.clear()
	for c in _indoor:
		_indoor_set[c] = true
		world.farm.indoor_cells[c] = true


## 안쪽 칸을 온실 밭에서 뺀다. 남은 빈 밭은 보통 땅이 된다 (작물이 있으면 옮기기·철거가 막혀 여기까지 오지 않는다).
func _unregister_indoor(world: FarmWorld) -> void:
	for c in _indoor:
		world.farm.indoor_cells.erase(c)
		world.farm.untill(c)
	_indoor.clear()
	_indoor_set.clear()


# ---------- 그림·벽

func _ready() -> void:
	y_sort_enabled = true
	super._ready()


func _update_visual() -> void:
	super._update_visual()
	if _sprite == null:
		return
	_sprite.visible = false
	_build_pieces()
	_build_walls()


## 그림을 뒷벽(맨 위 줄과 그 위 지붕), 왼쪽·오른쪽 벽, 앞벽(맨 아래 줄)으로 잘라 각자 발밑 높이로 정렬한다
func _build_pieces() -> void:
	for p in _pieces:
		p.queue_free()
	_pieces.clear()
	var tex := def.texture_for(turns)
	if tex == null:
		return
	var s := size()
	var w := s.x * TILE
	var h := s.y * TILE
	var roof := tex.get_height() - h  # 발자리 위로 솟은 부분
	var side_h := (s.y - 2) * TILE
	var left := -w / 2.0
	# [그림에서 자를 영역, 정렬 기준(발밑) 위치]
	var parts := [
		[Rect2(0, 0, tex.get_width(), roof + TILE), Vector2(left, -h + TILE)],
		[Rect2(0, roof + TILE, TILE, side_h), Vector2(left, -TILE)],
		[Rect2(tex.get_width() - TILE, roof + TILE, TILE, side_h), Vector2(left + w - TILE, -TILE)],
		[Rect2(0, roof + h - TILE, tex.get_width(), TILE), Vector2(left, 0)],
	]
	for part: Array in parts:
		var region: Rect2 = part[0]
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.centered = false
		sp.region_enabled = true
		sp.region_rect = region
		sp.position = part[1]
		sp.offset = Vector2(0, -region.size.y)
		add_child(sp)
		_pieces.append(sp)


## 벽 충돌: 뒷벽·옆벽 전체, 앞벽은 문 칸만 비운다
func _build_walls() -> void:
	if _walls:
		_walls.queue_free()
	_walls = StaticBody2D.new()
	add_child(_walls)
	var s := size()
	var top_left := Vector2(-s.x * TILE / 2.0, -s.y * TILE)
	var rects: Array[Rect2] = [
		Rect2(0, 0, s.x, 1),
		Rect2(0, 1, 1, s.y - 1),
		Rect2(s.x - 1, 1, 1, s.y - 1),
	]
	var door_start := (s.x - door_width()) / 2
	rects.append(Rect2(1, s.y - 1, door_start - 1, 1))
	rects.append(Rect2(door_start + door_width(), s.y - 1, s.x - 1 - door_start - door_width(), 1))
	for r in rects:
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = r.size * TILE
		shape.shape = rect
		shape.position = top_left + (r.position + r.size / 2.0) * TILE
		_walls.add_child(shape)
