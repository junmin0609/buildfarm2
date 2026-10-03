class_name BuildMode
extends Node2D
## 건설 모드: 미리보기를 그리고, 클릭으로 설치·이동·철거한다.
##   클릭 / Space   확정        우클릭 / E / Esc   취소 (이동 중이면 원래 자리로)
## 마우스를 움직이면 마우스 칸을, 키보드로 걸으면 플레이어 앞 칸을 기준으로 놓는다.
## 돈은 설치할 때 내고, 철거하면 전액 돌려받는다. 이동은 무료.
## 설치·이동·철거 모드인 동안은 시간이 멈춘다 (BUILD_FARM_PLAN §49, §94).

enum Mode { OFF, PLACE, MOVE, REMOVE }

const OK_FILL := Color(0.55, 0.95, 0.55, 0.28)
const OK_LINE := Color(0.85, 1.0, 0.8, 0.9)
const BAD_FILL := Color(1.0, 0.45, 0.4, 0.32)
const BAD_LINE := Color(1.0, 0.75, 0.7, 0.95)
const PICK_LINE := Color(1.0, 0.9, 0.55, 0.95)
const REMOVE_LINE := Color(1.0, 0.55, 0.5, 0.95)

var mode := Mode.OFF
var place_def: PlaceableDef
## 이동 모드에서 집어 든 시설
var moving: Placeable

var _hover := Vector2i.ZERO
var _check := {"ok": false, "bad": [], "reason": ""}
var _use_mouse := true
var _pulse := 0.0


func _ready() -> void:
	z_index = 50
	Events.build_requested.connect(_on_build_requested)


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
		start(Mode.PLACE)


func start(new_mode: Mode) -> void:
	_drop_moving()
	mode = new_mode
	GameState.set_time_paused("build_mode", mode != Mode.OFF)
	_update_hint()
	queue_redraw()


func stop() -> void:
	_drop_moving()
	mode = Mode.OFF
	place_def = null
	GameState.set_time_paused("build_mode", false)
	Events.build_hint_changed.emit("")
	queue_redraw()


func _update_hint() -> void:
	var text := ""
	match mode:
		Mode.PLACE:
			text = "%s 배치 (%d G) · 클릭 설치 · 우클릭/Esc 끝내기" % [place_def.name, place_def.price]
		Mode.MOVE:
			text = ("%s 옮기는 중 · 클릭 내려놓기 · 우클릭 취소" % moving.def.name) if moving else "옮길 시설을 클릭 · 우클릭/Esc 끝내기"
		Mode.REMOVE:
			text = "철거할 시설을 클릭 (값은 모두 돌려받아요) · 우클릭/Esc 끝내기"
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

func try_place(origin: Vector2i) -> bool:
	var grid := _world().build
	var result := grid.check(place_def, origin)
	if not result.ok:
		Events.toast.emit(result.reason)
		return false
	if not GameState.try_spend(place_def.price):
		Events.toast.emit("돈이 부족해요. (%d G 필요)" % place_def.price)
		return false
	grid.place(place_def, origin)
	Events.toast.emit("%s 설치!" % place_def.name)
	return true


func pick(cell: Vector2i) -> bool:
	var obj := _world().build.object_at(cell)
	if obj == null:
		return false
	moving = obj
	moving.modulate.a = 0.35
	_update_hint()
	return true


func try_drop(origin: Vector2i) -> bool:
	var result := _world().build.check(moving.def, origin, moving)
	if not result.ok:
		Events.toast.emit(result.reason)
		return false
	_world().build.move(moving, origin)
	Events.toast.emit("%s 옮김" % moving.def.name)
	_drop_moving()
	_update_hint()
	return true


func try_remove(cell: Vector2i) -> bool:
	var obj := _world().build.object_at(cell)
	if obj == null:
		return false
	var refund := obj.def.price
	var obj_name := obj.def.name
	_world().build.remove(obj)
	GameState.add_money(refund)
	Events.toast.emit("%s 철거 (+%d G)" % [obj_name, refund])
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
		_check = world.build.check(def, _origin_for(def), moving)
	queue_redraw()


func _current_def() -> PlaceableDef:
	if mode == Mode.PLACE:
		return place_def
	if mode == Mode.MOVE and moving:
		return moving.def
	return null


## 커서 칸이 시설의 아래쪽 가운데가 되도록 왼쪽 위 칸을 정한다
func _origin_for(def: PlaceableDef) -> Vector2i:
	return _hover - Vector2i((def.size.x - 1) / 2, def.size.y - 1)


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
	for c in Placeable.footprint_of(def, origin):
		var is_bad := c in bad
		_draw_cells([c], BAD_FILL if is_bad else OK_FILL, BAD_LINE if is_bad else OK_LINE)
	var tex := def.texture
	var foot := Vector2(origin.x * Art.TILE + def.size.x * Art.TILE / 2.0, (origin.y + def.size.y) * Art.TILE)
	var tint := Color(1, 1, 1, 0.7) if ok else Color(1, 0.6, 0.55, 0.6)
	tint.a *= 0.85 + 0.15 * sin(_pulse * 5.0)
	draw_texture(tex, foot - Vector2(tex.get_width() / 2.0, tex.get_height()), tint)


func _draw_cells(cells: Array, fill: Color, line: Color) -> void:
	for c: Vector2i in cells:
		var r := Rect2(Vector2(c * Art.TILE), Vector2(Art.TILE, Art.TILE)).grow(-1)
		draw_rect(r, fill)
		draw_rect(r, line, false, 1.0)
