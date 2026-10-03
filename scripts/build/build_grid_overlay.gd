class_name BuildGridOverlay
extends Node2D
## 건설 모드의 격자 (BUILD_FARM_PLAN §49). 화면에 보이는 농장 땅 칸에 얇은 선을 긋고,
## 시설·장애물·작물이 있어서 지금 지을 수 없는 칸은 살짝 어둡게 칠한다.
## 바닥 바로 위(밭 그림 다음), 나무·시설보다 아래에 그려지도록 BuildMode 가 FarmWorld 에 붙인다.

const LINE := Color(1.0, 0.97, 0.86, 0.22)
const TAKEN := Color(0.35, 0.2, 0.12, 0.22)

var world: FarmWorld


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## 지금 화면에 보이는 칸 범위
func visible_cells() -> Rect2i:
	var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport_rect()
	var from := world.world_to_cell(view.position) - Vector2i.ONE
	var to := world.world_to_cell(view.end) + Vector2i.ONE
	return Rect2i(from, to - from)


## 격자를 그릴 칸 (보이는 범위 안의 지을 수 있는 땅)
func grid_cells(area: Rect2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if world.build.is_buildable_ground(c):
				cells.append(c)
	return cells


func _draw() -> void:
	if world == null:
		return
	var t := float(Art.TILE)
	for c in grid_cells(visible_cells()):
		var r := Rect2(Vector2(c) * t, Vector2(t, t))
		if world.build.is_cell_taken(c):
			draw_rect(r, TAKEN)
		# 칸마다 위·왼쪽 선만 긋고, 오른쪽·아래가 땅 끝이면 그쪽도 긋는다 (선이 겹쳐 두꺼워지지 않게)
		draw_line(r.position, Vector2(r.end.x, r.position.y), LINE, 1.0)
		draw_line(r.position, Vector2(r.position.x, r.end.y), LINE, 1.0)
		if not world.build.is_buildable_ground(c + Vector2i.RIGHT):
			draw_line(Vector2(r.end.x, r.position.y), r.end, LINE, 1.0)
		if not world.build.is_buildable_ground(c + Vector2i.DOWN):
			draw_line(Vector2(r.position.x, r.end.y), r.end, LINE, 1.0)
