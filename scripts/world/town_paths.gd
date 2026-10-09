class_name TownPaths
extends RefCounted
## 광장 돌길 위로 다니는 길 찾기 (주민 walker 용). 맵의 돌바닥('p') 칸만 지나간다.

static var _grid: AStarGrid2D


static func _build() -> AStarGrid2D:
	var g := AStarGrid2D.new()
	var size := MapLayout.size()
	g.region = Rect2i(Vector2i.ZERO, size)
	g.cell_size = Vector2(Art.TILE, Art.TILE)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	g.update()
	for y in size.y:
		for x in size.x:
			if MapLayout.char_at(Vector2i(x, y)) != "p":
				g.set_point_solid(Vector2i(x, y), true)
	return g


## from 칸에서 to 칸까지 지나갈 칸 가운데 좌표들 (못 가면 빈 배열). from 이 돌길이 아니면 가장 가까운 돌길에서 시작
static func route(world: FarmWorld, from: Vector2i, to: Vector2i) -> Array[Vector2]:
	if _grid == null:
		_grid = _build()
	var out: Array[Vector2] = []
	if not _grid.is_in_boundsv(from) or not _grid.is_in_boundsv(to) or _grid.is_point_solid(to):
		return out
	var start := from
	if _grid.is_point_solid(start):
		for r in range(1, 4):
			for d: Vector2i in [Vector2i(r, 0), Vector2i(-r, 0), Vector2i(0, r), Vector2i(0, -r)]:
				if _grid.is_in_boundsv(from + d) and not _grid.is_point_solid(from + d):
					start = from + d
					break
			if start != from:
				break
	for c: Vector2i in _grid.get_id_path(start, to):
		out.append(world.cell_center(c) + Vector2(0, 4))
	return out
