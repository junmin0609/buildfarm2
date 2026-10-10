class_name BuildMode
extends Node2D
## 건설 모드: 미리보기를 그리고, 클릭으로 설치·이동·철거한다.
##   클릭 / Space   확정        우클릭 / E / Esc   취소 (이동 중이면 원래 자리로)
##   R              시계 방향 90° 회전 (설치할 때, 옮길 때. 돌릴 수 있는 시설만 §54)
## 건설 모드인 동안 농장 땅에 격자를 보여 준다 (BuildGridOverlay, §49).
## 마우스를 움직이면 마우스 칸을, 키보드로 걸으면 플레이어 앞 칸을 기준으로 놓는다.
## 돈·재료는 설치할 때 내고, 철거하면 전부 돌려받는다 (증축 비용 포함, Placeable.extra_cost). 이동은 무료.
## 안에 작물이 있는 온실처럼 시설이 막으면(Placeable.removal_problem) 옮기거나 철거할 수 없다.
## 설치·이동·철거 모드인 동안은 시간이 멈춘다 (BUILD_FARM_PLAN §49, §94).
## 컨베이어 (§57~§59, §65)
##   설치: 누른 칸에서 끌어 놓은 칸까지 ㄱ자로 깐다 (멀리 간 쪽 먼저). 칸마다 방향은 다음 칸 쪽, 마지막 칸은 마지막 방향.
##         끌지 않고 누르기만 하면 한 칸 (R 로 정한 방향). 가진 컨베이어보다 긴 부분·막힌 칸은 빨갛게 보이고 건너뛴다.
##   철거: 누른 채 끌면 지나간 컨베이어를 모두 철거한다 (시설은 클릭한 것 하나만).
## 시설의 입구(초록 화살표, 안쪽으로)·출구(주황 화살표, 바깥쪽으로)는 건설 모드에서만 보인다 (§55).

enum Mode { OFF, PLACE, MOVE, REMOVE }

const OK_FILL := Color(0.55, 0.95, 0.55, 0.28)
const OK_LINE := Color(0.85, 1.0, 0.8, 0.9)
const BAD_FILL := Color(1.0, 0.45, 0.4, 0.32)
const BAD_LINE := Color(1.0, 0.75, 0.7, 0.95)
const PICK_LINE := Color(1.0, 0.9, 0.55, 0.95)
const REMOVE_LINE := Color(1.0, 0.55, 0.5, 0.95)
const ARROW := Color(1.0, 0.98, 0.9, 0.95)
const ARROW_OUTLINE := Color(0.36, 0.23, 0.16, 0.9)
const PORT_IN := Color("9fdc8a")
const PORT_OUT := Color("f5b65a")
## 스프링클러(물) / 자동 수확기 범위 미리보기 색
const AREA_WATER := Color("7cc4e6")
const AREA_HARVEST := Color("f2c443")

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
## 컨베이어를 끌어서 까는 중: 시작 칸 / 지금 길 [{"cell", "turns", "ok"}]
var _dragging := false
var _drag_start := Vector2i.ZERO
var _path: Array[Dictionary] = []
## 철거 모드에서 누른 채 끄는 중 (지나간 컨베이어 철거)
var _drag_remove := false
var _last_removed := Vector2i(-99999, -99999)


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
	var lock := QuestManager.lock_reason_now(def_id)
	if lock != "":
		Events.toast.emit(lock)  # 기술이 잠긴 시설은 새로 놓지 못함 (스토리 3단계)
		return
	place_def = PlaceableDB.get_def(def_id)
	if place_def:
		turns = 0
		start(Mode.PLACE)


func start(new_mode: Mode) -> void:
	_drop_moving()
	_end_drags()
	mode = new_mode
	GameState.set_time_paused("build_mode", mode != Mode.OFF)
	_show_grid(mode != Mode.OFF)
	_update_hint()
	queue_redraw()


func stop() -> void:
	_drop_moving()
	_end_drags()
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
		Mode.PLACE when _dragging:
			var bad := _path.filter(func(p: Dictionary) -> bool: return not p.ok).size()
			text = "길이 %d · 가진 %s %d개%s · 놓으면 설치" % [_path.size(), place_def.name, affordable(place_def),
					(" · 빨간 %d칸 건너뜀" % bad) if bad > 0 else ""]
		Mode.PLACE when is_belt(place_def):
			text = "%s 깔기 · 끌어서 길게%s · 우클릭/Esc 끝내기" % [place_def.name, rotate_hint]
		Mode.PLACE:
			# 값은 건설 창에 보이므로 여기서는 빼서 안내 줄이 화면 밖으로 넘치지 않게 한다
			text = "%s 배치 · 클릭 설치%s · 우클릭/Esc 끝내기" % [place_def.name, rotate_hint]
		Mode.MOVE:
			text = ("%s 옮기는 중 · 클릭 내려놓기%s · 우클릭 취소" % [moving.def.name, rotate_hint]) if moving else "옮길 시설을 클릭 · 우클릭/Esc 끝내기"
		Mode.REMOVE:
			text = "철거할 시설 클릭 (모두 돌려받음) · 컨베이어는 끌어서 · 우클릭/Esc 끝내기"
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
		if mode == Mode.PLACE and is_belt(place_def):
			begin_belt_drag(_hover)
		elif mode == Mode.REMOVE:
			_drag_remove = true
			_last_removed = _hover
			try_remove(_hover)
		else:
			_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("use_tool"):
		if _dragging:
			end_belt_drag()
			get_viewport().set_input_as_handled()
		_drag_remove = false
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
	if _dragging:
		_end_drags()
		_update_hint()
	elif mode == Mode.MOVE and moving:
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
	var lock := QuestManager.lock_reason_now(place_def.id) if place_def else ""
	if lock != "":
		Events.toast.emit(lock)
		return false
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
	_fade(moving, 0.35)
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
	var extra := obj.extra_cost()
	var refund_money := obj.def.price + int(extra.get("price", 0))
	var refund_mats: Dictionary = obj.def.materials.duplicate()
	var extra_mats: Dictionary = extra.get("materials", {})
	for mat_id: String in extra_mats:
		refund_mats[mat_id] = int(refund_mats.get(mat_id, 0)) + int(extra_mats[mat_id])
	for mat_id: String in refund_mats:
		back.append({"id": mat_id, "count": int(refund_mats[mat_id]), "quality": Quality.NONE})
	var problem := obj.demolish_problem(_world())
	if problem == "":
		problem = obj.removal_problem(_world())
	if problem == "" and not inv.can_add_stacks(back):
		problem = "가방에 돌려받을 물건을 넣을 자리가 없어요."
	if problem != "":
		Events.toast.emit(problem)
		return false
	var def := obj.def
	obj.take_contents()
	_world().build.remove(obj)
	GameState.add_money(refund_money)
	for st: Dictionary in back:
		inv.add(st.id, int(st.count), st.quality)
	Events.toast.emit("%s 철거 (+%s)" % [def.name, PlaceableDef.cost_text_of(refund_money, refund_mats)])
	return true


func _drop_moving() -> void:
	if moving and is_instance_valid(moving):
		_fade(moving, 1.0)
	moving = null


## 옮기는 중인 시설을 흐리게 (집·출하함·우물은 자리표가 안 보이므로 건물 노드를 흐리게)
func _fade(obj: Placeable, alpha: float) -> void:
	obj.modulate.a = alpha
	if obj is Fixture and (obj as Fixture).building():
		(obj as Fixture).building().modulate.a = alpha


func _end_drags() -> void:
	_dragging = false
	_path.clear()
	_drag_remove = false


# ---------- 컨베이어 끌어서 깔기 (§57~§59)

## 끌어서 길게 까는 시설인가 (컨베이어)
static func is_belt(def: PlaceableDef) -> bool:
	return def != null and def.data.has("conveyor")


## 지금 돈·재료로 몇 칸(개)을 놓을 수 있는지
static func affordable(def: PlaceableDef) -> int:
	if def == null:
		return 0
	var n := 1 << 30
	if def.price > 0:
		n = int(GameState.money / float(def.price))
	for mat_id: String in def.materials:
		n = mini(n, int(GameState.inventory.count_of(mat_id) / float(maxi(1, int(def.materials[mat_id])))))
	return n


## from 에서 to 까지 ㄱ자 길: 멀리 간 쪽(가로/세로)을 먼저. [{"cell", "turns"}]
## 칸마다 방향은 다음 칸 쪽, 마지막 칸은 마지막 방향. 한 칸뿐이면 single_turns 방향
static func belt_path(from: Vector2i, to: Vector2i, single_turns := 0) -> Array[Dictionary]:
	var cells: Array[Vector2i] = [from]
	var d := to - from
	var legs := [Vector2i(d.x, 0), Vector2i(0, d.y)] if absi(d.x) >= absi(d.y) else [Vector2i(0, d.y), Vector2i(d.x, 0)]
	var c := from
	for leg: Vector2i in legs:
		for i in absi(leg.x) + absi(leg.y):
			c += leg.sign()
			cells.append(c)
	var out: Array[Dictionary] = []
	for i in cells.size():
		var t := single_turns
		if cells.size() > 1:
			var dir := cells[i + 1] - cells[i] if i < cells.size() - 1 else cells[i] - cells[i - 1]
			t = Placeable.DIRS.find(dir)
		out.append({"cell": cells[i], "turns": t})
	return out


func begin_belt_drag(cell: Vector2i) -> void:
	_dragging = true
	_drag_start = cell
	_update_path()


## 지금 커서 칸까지 길을 다시 잡고, 칸마다 놓을 수 있는지(막힘·가진 개수) 표시한다
func _update_path() -> void:
	var grid := _world().build
	_path = belt_path(_drag_start, _hover, turns)
	var have := affordable(place_def)
	var ok_count := 0
	for p in _path:
		p.ok = grid.check(place_def, p.cell, null, p.turns).ok and ok_count < have
		if p.ok:
			ok_count += 1
	_update_hint()


## 끌기를 끝내고 길을 깐다. 놓은 칸 수
func end_belt_drag() -> int:
	_update_path()
	var path := _path.duplicate()
	_dragging = false
	_path.clear()
	if path.size() > 1:
		turns = int(path[-1].turns)
	return _place_path(path)


## 테스트·키보드용: from → to 길을 바로 깐다. 놓은 칸 수
func place_belts(from: Vector2i, to: Vector2i) -> int:
	begin_belt_drag(from)
	_hover = to
	return end_belt_drag()


func _place_path(path: Array) -> int:
	var grid := _world().build
	var inv := GameState.inventory
	var placed := 0
	var blocked := 0
	var short := 0
	for p: Dictionary in path:
		if not grid.check(place_def, p.cell, null, p.turns).ok:
			blocked += 1
			continue
		if affordable(place_def) <= 0 or not GameState.try_spend(place_def.price):
			short += 1
			continue
		for mat_id: String in place_def.materials:
			inv.remove(mat_id, int(place_def.materials[mat_id]))
		grid.place(place_def, p.cell, int(p.turns))
		placed += 1
	var msg := "%s %d칸 설치" % [place_def.name, placed] if placed > 0 else "놓을 수 있는 칸이 없어요."
	if blocked > 0:
		msg += " · 막힌 %d칸은 건너뜀" % blocked
	if short > 0:
		msg += " · %s이(가) 모자라 %d칸 못 깔았어요" % [place_def.name, short]
	Events.toast.emit(msg)
	_update_hint()
	return placed


# ---------- 미리보기

func _process(delta: float) -> void:
	if mode == Mode.OFF:
		return
	_pulse += delta
	var world := _world()
	var before := _hover
	# 키보드로 걸을 때는 바라보는 앞 칸 (target_cell 은 마우스가 가까우면 마우스 칸을 고르므로 쓰지 않는다)
	_hover = world.world_to_cell(get_global_mouse_position()) if _use_mouse else world.player.my_cell() + world.player.facing
	var def := _current_def()
	if def:
		_check = world.build.check(def, _origin_for(def), moving, turns)
	if _dragging and _hover != before:
		_update_path()
	# 철거: 누른 채 끌면 지나간 컨베이어를 철거한다 (§65)
	if _drag_remove and _hover != _last_removed:
		_last_removed = _hover
		if world.build.object_at(_hover) is Conveyor:
			try_remove(_hover)
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
	return _hover - Vector2i(int((s.x - 1) / 2.0), s.y - 1)


func _draw() -> void:
	if mode == Mode.OFF:
		return
	_draw_all_ports()
	var def := _current_def()
	if _dragging:
		_draw_path()
	elif def:
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
	_draw_ports(Placeable.ports_of(def, origin, turns))
	# 스프링클러·자동 수확기: 일하는 범위 (§14, §66)
	if def.data.has("area"):
		var area_color := AREA_HARVEST if def.data.has("harvester") else AREA_WATER
		for c in FarmArea.cells(origin, def.data.area):
			draw_rect(Rect2(Vector2(c * Art.TILE), Vector2(Art.TILE, Art.TILE)).grow(-2), Color(area_color, 0.28))
			draw_rect(Rect2(Vector2(c * Art.TILE), Vector2(Art.TILE, Art.TILE)).grow(-2), Color(area_color, 0.8), false, 1.0)


## 끌어서 까는 컨베이어 길: 칸마다 놓을 수 있으면 초록, 막혔거나 가진 개수를 넘으면 빨강 + 방향 화살표
func _draw_path() -> void:
	for p in _path:
		_draw_cells([p.cell], OK_FILL if p.ok else BAD_FILL, OK_LINE if p.ok else BAD_LINE)
		_draw_arrow(Vector2(p.cell * Art.TILE) + Vector2.ONE * Art.TILE / 2.0, Vector2(Placeable.DIRS[int(p.turns)]))


## 놓인 시설들의 입구·출구 (건설 모드에서만, §55)
func _draw_all_ports() -> void:
	for obj in _world().build.objects():
		if obj is Router:
			_draw_ports(router_ports(obj))
		elif not obj is Conveyor:
			_draw_ports(obj.ports())


## 분배기·합류기도 시설 포트처럼 들어오는 쪽(초록)·나가는 쪽(주황)을 화살표로 보여 준다 (§62)
static func router_ports(r: Router) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s: Vector2i in Placeable.DIRS:
		if r.accepts_dir(-s):
			out.append({"type": "in", "cell": r.cell, "dir": s, "outside": r.cell + s})
	for d in r.all_exit_dirs():
		out.append({"type": "out", "cell": r.cell, "dir": d, "outside": r.cell + d})
	return out


## 입구는 바깥에서 시설 안쪽을 가리키는 초록 화살표, 출구는 시설에서 바깥을 가리키는 주황 화살표 (포트 칸 가장자리에)
func _draw_ports(ports: Array[Dictionary]) -> void:
	for p in ports:
		var edge := Vector2(p.cell * Art.TILE) + Vector2.ONE * Art.TILE / 2.0 + Vector2(p.dir) * (Art.TILE / 2.0)
		var out: bool = p.type == "out"
		_draw_arrow(edge, Vector2(p.dir) if out else -Vector2(p.dir), PORT_OUT if out else PORT_IN)


## 방향이 있는 시설의 앞쪽을 가리키는 화살표
func _draw_arrow(center: Vector2, dir: Vector2, color := ARROW) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := center + dir * 6.0
	var points := PackedVector2Array([tip, center - dir * 2.0 + side * 4.0, center - dir * 2.0 - side * 4.0])
	var outline := PackedVector2Array([tip + dir, center - dir * 3.0 + side * 5.5, center - dir * 3.0 - side * 5.5])
	draw_colored_polygon(outline, ARROW_OUTLINE)
	draw_colored_polygon(points, color)


func _draw_cells(cells: Array, fill: Color, line: Color) -> void:
	for c: Vector2i in cells:
		var r := Rect2(Vector2(c * Art.TILE), Vector2(Art.TILE, Art.TILE)).grow(-1)
		draw_rect(r, fill)
		draw_rect(r, line, false, 1.0)
