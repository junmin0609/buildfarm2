class_name TerrainTileSet
extends RefCounted
## assets/art/tiles.png (16px 격자) 로 TileSet을 만든다. 충돌 모양과 물 애니메이션도 여기서 정한다.

const TILE_SIZE := Art.TILE
const SOURCE_ID := 0
## 길·물·흙 가장자리를 잔디가 살짝 덮는 경계 타일 (edges.png)
const EDGE_SOURCE_ID := 1
const EDGE_ROWS := {"s": 0, "@": 0, "p": 0, "~": 1, "d": 2, "x": 2}
## 종류마다 경계 무늬 변형 수 (edges.png 줄 = 종류 × EDGE_VARIANTS + 변형). 칸마다 골라 반복이 안 보이게 한다
const EDGE_VARIANTS := 3
## 안쪽 모서리 둥글리기 (edge_corners.png, 줄 = 종류, 칸 = 대각선 잔디 비트 북동1 남동2 남서4 북서8)
const EDGE_CORNER_SOURCE_ID := 3
## 잔디 위 작은 장식 (details.png): 0 풀, 1 긴 풀, 2~4 꽃, 5 클로버, 6 조약돌, 7 버섯,
## 8 작은 풀잎, 9 어두운 얼룩, 10 밝은 얼룩, 11 작은 돌, 12 잡초, 13 작은 흰 꽃
const DETAIL_SOURCE_ID := 2
const DETAIL_COUNT := 14

const GRASS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
const FLOWERS: Array[Vector2i] = [Vector2i(4, 0), Vector2i(5, 0)]
## 조금 더 노랗고 따뜻한 풀밭 (맵 곳곳에 넓게 섞인다)
const GRASS_WARM: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2)]
const DIRT := Vector2i(6, 0)
## 둥근 돌길 4종 (칸마다 섞어서 반복이 덜 보이게)
const PATHS: Array[Vector2i] = [Vector2i(7, 0), Vector2i(5, 2), Vector2i(6, 2), Vector2i(7, 2)]
const PLAZA: Array[Vector2i] = [Vector2i(0, 3), Vector2i(1, 3)]
const BRIDGE := Vector2i(2, 3)
## 개울가 석축 (무드 개편, 못 지나감)
const EMBANK := Vector2i(3, 3)
const WATER := Vector2i(0, 1)      # (0,1)~(1,1) 두 프레임 애니메이션
const SOIL := Vector2i(2, 1)
const SOIL_WET := Vector2i(3, 1)
const FENCE_H := Vector2i(4, 1)
const FENCE_V := Vector2i(5, 1)
const FENCE_POST := Vector2i(6, 1)
const CURSOR := Vector2i(0, 2)

## 못 지나가는 타일과 충돌 사각형 (타일 중심 기준)
const SOLID := {
	WATER: Rect2(-8, -8, 16, 16),
	FENCE_H: Rect2(-8, -3, 16, 6),
	FENCE_V: Rect2(-2, -8, 4, 16),
	FENCE_POST: Rect2(-2, -4, 4, 8),
	EMBANK: Rect2(-8, -8, 16, 16),
}


static func build() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_physics_layer()

	var source := TileSetAtlasSource.new()
	source.texture = Art.TILES
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(source, SOURCE_ID)

	var plain: Array[Vector2i] = []
	plain.append_array(GRASS)
	plain.append_array(FLOWERS)
	plain.append_array(GRASS_WARM)
	plain.append_array(PATHS)
	plain.append_array(PLAZA)
	plain.append_array([DIRT, SOIL, SOIL_WET, FENCE_H, FENCE_V, FENCE_POST, CURSOR, BRIDGE, EMBANK])
	for coords in plain:
		source.create_tile(coords)

	source.create_tile(WATER)
	source.set_tile_animation_frames_count(WATER, 2)
	source.set_tile_animation_speed(WATER, 1.6)

	var edges := TileSetAtlasSource.new()
	edges.texture = Art.EDGES
	edges.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(edges, EDGE_SOURCE_ID)
	for row in 3 * EDGE_VARIANTS:
		for mask in range(1, 16):
			edges.create_tile(Vector2i(mask, row))

	var corners := TileSetAtlasSource.new()
	corners.texture = Art.EDGE_CORNERS
	corners.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(corners, EDGE_CORNER_SOURCE_ID)
	for row in 3:
		for mask in range(1, 16):
			corners.create_tile(Vector2i(mask, row))

	var details := TileSetAtlasSource.new()
	details.texture = Art.DETAILS
	details.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(details, DETAIL_SOURCE_ID)
	for i in DETAIL_COUNT:
		details.create_tile(Vector2i(i, 0))

	for coords: Vector2i in SOLID:
		var r: Rect2 = SOLID[coords]
		var data := source.get_tile_data(coords, 0)
		data.add_collision_polygon(0)
		data.set_collision_polygon_points(0, 0, PackedVector2Array([
			r.position,
			Vector2(r.end.x, r.position.y),
			r.end,
			Vector2(r.position.x, r.end.y),
		]))
	return tile_set
