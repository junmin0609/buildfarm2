class_name BuildMode
extends Node2D
## 건설 모드: 미리보기를 그리고, 클릭으로 설치·이동·철거한다.
##   클릭 / Space   확정        우클릭 / E / Esc   취소 (이동 중이면 원래 자리로)
##   R              시계 방향 90° 회전 (설치할 때, 옮길 때. 돌릴 수 있는 시설만 §54)
## 건설 모드인 동안 농장 땅에 격자를 보여 준다 (BuildGridOverlay, §49).
## 마우스를 움직이면 마우스 칸을, 키보드로 걸으면 플레이어 앞 칸을 기준으로 놓는다.
## 돈·재료는 설치할 때 내고, 철거하면 전부 돌려받는다. 이동은 무료.
## 안에 작물이 있는 온실처럼 시설이 막으면(Placeable.removal_problem) 옮기거나 철거할 수 없다.
## 설치·이동·철거 모드인 동안은 시간이 멈춘다 (BUILD_FARM_PLAN §49, §94).

enum Mode { OFF, PLACE, MOVE, REMOVE }

const OK_FILL := Color(0.55, 0.95, 0.55, 0.28)
const OK_LINE := Color(0.85, 1.0, 0.8, 0.9)
const BAD_FILL := Color(1.0, 0.45, 0.4, 0.32)
const BAD_LINE := Color(1.0, 0.75, 0.7, 0.95)
const PICK_LINE := Color(1.0, 0.9, 0.55, 0.95)
const REMOVE_LINE := Color(1.0, 0.55, 0.5, 0.95)
const ARROW := Color(1.0, 0.98, 0.9, 0.95)
const ARROW_OUTLINE := Color(0.36, 0.23, 0.16, 0.9)

var mode := Mode.OFF
var place_def: PlaceableDef
## 이동 모드에서 집어 든 시설
var moving: Placeable
## 미리보기(설치할 시설·옮기는 시설)의 회전 횟수. 옮길 때는 내려놓아야 시설에 적용된다.
var turns := 0
var grid_overlay: BuildGridOverlay

var _hover := Vector2i.ZERO
var _check := {"ok": false, "bad": [], "reason": ""}
var _use_mouse := true
var _pulse := 0.0


func _ready() -> void:
	z_index = 50
	Events.build_requested.connect(_on_build_requested)
	_attach_overlay.call_deferred()


## 격자는 밭 그림 바로 다음(나무·시설 아래)에 그려야 해서 FarmWorld 의 Farm 노드 뒤에 끼워 넣는다
func _attach_overlay() -> void:
	var world := _world()
	grid_overlay = BuildGridOverlay.new()
	grid_overlay.name = "BuildGridOverlay"
	grid_overlay.world = world
	grid_overlay.visible = is_active()
	world.add_child(grid_overlay)
	world.move_child(grid_overlay, world.farm.get_index() + 1)


func _world() -> FarmWorld:
	return get_parent() as FarmWorld


func is_active() -> bool:
	return mode != Mode.OFF


# ---------- 모드 전환

func _on_build_requested(what: String, def_id: String) -> void:
	match what:
		"place":
			start_place(def_id)
		"move":
			start(Mode.MOVE)
		"remove":
			start(Mode.REMOVE)


func start_place(def_id: String) -> void:
	place_def = PlaceableDB.get_def(def_id)
	if place_def:
		turns = 0
		start(Mode.PLACE)


func start(new_mode: Mode) -> void:
	_drop_moving()
	mode = new_mode
	GameState.set_time_paused("build_mode", mode != Mode.OFF)
	_show_grid(mode != Mode.OFF)
	_update_hint()
	queue_redraw()


func stop() -> void:
	_drop_moving()
	mode = Mode.OFF
	place_def = null
	GameState.set_time_paused("build_mode", false)
	_show_grid(false)
	Events.build_hint_changed.emit("")
	queue_redraw()


func _show_grid(on: bool) -> void:
	if grid_overlay:
		grid_overlay.visible = on


func _update_hint() -> void:
	var text := ""
	var def := _current_def()
	var rotate_hint := " · R 회전" if def and def.rotatable else ""
	match mode:
		Mode.PLACE:
			text = "%s 배치 (%s) · 클릭 설치%s · 우클릭/Esc 끝내기" % [place_def.name, place_def.cost_text(), rotate_hint]
		Mode.MOVE:
			text = ("%s 옮기는 중 · 클릭 내려놓기%s · 우클릭 취소" % [moving.def.name, rotate_hint]) if moving else "옮길 시설을 클릭 · 우클릭/Esc 끝내기"
		Mode.REMOVE:
			text = "철거할 시설을 클릭 (값·재료는 모두 돌려받아요) · 우클릭/Esc 끝내기"
	Events.build_hint_changed.emit(text)


# ---------- 입력

func _unhandled_input(event: InputEvent) -> void:
	if mode == Mode.OFF or GameState.is_input_locked():
		return
	if event is InputEventMouseMotion:
		_use_mouse = true
	elif event.is_action_pressed("move_up") or event.is_action_pressed("move_down") \
			or event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		_use_mouse = false
	if event.is_action_pressed("use_tool"):
		_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate"):
		rotate_preview()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or event.is_action_pressed("cancel"):
		_cancel()
		get_viewport().set_input_as_handled()


func _confirm() -> void:
	match mode:
		Mode.PLACE:
			try_place(_origin_for(place_def))
		Mode.MOVE:
			if moving == null:
				pick(_hover)
			else:
				try_drop(_origin_for(moving.def))
		Mode.REMOVE:
			try_remove(_hover)


func _cancel() -> void:
	if mode == Mode.MOVE and moving:
		_drop_moving()
		_update_hint()
	else:
		stop()


# ---------- 동작 (테스트에서도 바로 부른다)

## 미리보기를 시계 방향으로 90° 돌린다. 돌릴 수 없는 시설이면 false.
func rotate_preview() -> bool:
	var def := _current_def()
	if def == null or not def.rotatable:
		return false
	turns = (turns + 1) % 4
	_update_hint()
	queue_redraw()
	return true


func try_place(origin: Vector2i) -> bool:
	var grid := _world().build
	var result := grid.check(place_def, origin, null, turns)
	if not result.ok:
		Events.toast.emit(result.reason)
		return false
	var inv := GameState.inventory
	var short := place_def.afford_problem(inv)
	if short != "" or not GameState.try_spend(place_def.price):
		Events.toast.emit(short if short != "" else "돈이 부족해요. (%d G 필요)" % place_def.price)
		return false
	for mat_id: String in place_def.materials:
		inv.remove(mat_id, int(place_def.materials[mat_id]))
	grid.place(place_def, origin, turns)
	Events.toast.emit("%s 설치!" % place_def.name)
	return true


func pick(cell: Vector2i) -> bool:
	var obj := _world().build.object_at(cell)
	if obj == null:
		return false
	var problem := obj.removal_problem(_world())
	if problem != "":
		Events.toast.emit(problem)
		return false
	moving = obj
	moving.modulate.a = 0.35
	turns = obj.turns
	_update_hint()
	return true


func try_drop(origin: Vector2i) -> bool:
	var result := _world().build.check(moving.def, origin, moving, turns)
	if not result.ok:
		Events.toast.emit(result.reason)
		return false
	_world().build.move(moving, origin, turns)
	Events.toast.emit("%s 옮김" % moving.def.name)
	_drop_moving()
	_update_hint()
	return true


func try_remove(cell: Vector2i) -> bool:
	var obj := _world().build.object_at(cell)
	if obj == null:
		return false
	# 안에 든 아이템 + 재료가 가방에 다 들어가야 철거한다 (§106, 아이템이 사라지지 않게)
	var inv := GameState.inventory
	var back: Array = obj.contents().duplicate(true)
	for mat_id: String in obj.def.materials:
		back.append({"id": mat_id, "count": int(obj.def.materials[mat_id]), "quality": Quality.NONE})
	var problem := obj.removal_problem(_world())
	if problem == "" and not inv.can_add_stacks(back):
		problem = "가방에 돌려받을 물건을 넣을 자리가 없어요."
	if problem != "":
		Events.toast.emit(problem)
		return false
	var def := obj.def
	obj.take_contents()
	_world().build.remove(obj)
	GameState.add_money(def.price)
	for st: Dictionary in back:
		inv.add(st.id, int(st.count), st.quality)
	Events.toast.emit("%s 철거 (+%s)" % [def.name, def.cost_text()])
	return true


func _drop_moving() -> void:
	if moving and is_instance_valid(moving):
		moving.modulate.a = 1.0
	moving = null


# ---------- 미리보기

func _process(delta: float) -> void:
	if mode == Mode.OFF:
		return
	_pulse += delta
	var world := _world()
	_hover = world.world_to_cell(get_global_mouse_position()) if _use_mouse else world.player.target_cell()
	var def := _current_def()
	if def:
		_check = world.build.check(def, _origin_for(def), moving, turns)
	queue_redraw()


func _current_def() -> PlaceableDef:
	if mode == Mode.PLACE:
		return place_def
	if mode == Mode.MOVE and moving:
		return moving.def
	return null


## 커서 칸이 시설의 아래쪽 가운데가 되도록 왼쪽 위 칸을 정한다
func _origin_for(def: PlaceableDef) -> Vector2i:
	var s := def.size_for(turns)
	return _hover - Vector2i((s.x - 1) / 2, s.y - 1)


func _draw() -> void:
	if mode == Mode.OFF:
		return
	var def := _current_def()
	if def:
		_draw_ghost(def, _origin_for(def))
	else:
		var obj := _world().build.object_at(_hover)
		var line := REMOVE_LINE if mode == Mode.REMOVE else PICK_LINE
		if obj:
			_draw_cells(obj.footprint(), Color(line, 0.2), line)
		else:
			_draw_cells([_hover], Color(1, 1, 1, 0.08), Color(1, 1, 1, 0.5))


func _draw_ghost(def: PlaceableDef, origin: Vector2i) -> void:
	var ok: bool = _check.ok
	var bad: Array = _check.bad
	for c in Placeable.footprint_of(def, origin, turns):
		var is_bad := c in bad
		_draw_cells([c], BAD_FILL if is_bad else OK_FILL, BAD_LINE if is_bad else OK_LINE)
	var s := def.size_for(turns)
	var tex := def.texture_for(turns)
	var foot := Vector2(origin.x * Art.TILE + s.x * Art.TILE / 2.0, (origin.y + s.y) * Art.TILE)
	var tint := Color(1, 1, 1, 0.7) if ok else Color(1, 0.6, 0.55, 0.6)
	tint.a *= 0.85 + 0.15 * sin(_pulse * 5.0)
	if tex:
		draw_texture(tex, foot - Vector2(tex.get_width() / 2.0, tex.get_height()), tint)
	if def.directional:
		var center := Vector2(origin * Art.TILE) + Vector2(s * Art.TILE) / 2.0
		_draw_arrow(center, Vector2(Placeable.DIRS[turns]))


## 방향이 있는 시설의 앞쪽을 가리키는 화살표
func _draw_arrow(center: Vector2, dir: Vector2) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := center + dir * 6.0
	var points := PackedVector2Array([tip, center - dir * 2.0 + side * 4.0, center - dir * 2.0 - side * 4.0])
	var outline := PackedVector2Array([tip + dir, center - dir * 3.0 + side * 5.5, center - dir * 3.0 - side * 5.5])
	draw_colored_polygon(outline, ARROW_OUTLINE)
	draw_colored_polygon(points, ARROW)


func _draw_cells(cells: Array, fill: Color, line: Color) -> void:
	for c: Vector2i in cells:
		var r := Rect2(Vector2(c * Art.TILE), Vector2(Art.TILE, Art.TILE)).grow(-1)
		draw_rect(r, fill)
		draw_rect(r, line, false, 1.0)
