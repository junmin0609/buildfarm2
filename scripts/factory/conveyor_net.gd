class_name ConveyorNet
extends RefCounted
## 한 지역(BuildGrid)의 컨베이어 전체를 움직인다 (BUILD_FARM_PLAN §56~§61).
## BuildGrid 가 게임 시계(Events.time_advanced)와 야간 생산 때 tick 을 부른다 — 사용자 결정: 게임 시계 기준.
##
## 한 번 움직일 때
##   1. 앞(물건이 나가는 쪽) 벨트부터 차례로: 물건을 밀고, 끝에 닿으면 다음 칸에 넘긴다
##      다음 칸 = 같은 방향이 아닌 마주 보지 않는 벨트(비어 있을 때) 또는 그 칸을 입구로 가진 시설(accept_item)
##      넘기지 못하면 끝에서 기다린다 → 뒤 벨트도 차례로 막힌다 (§61). 아이템은 사라지지 않는다.
##   2. 시설 출구 앞 벨트가 비어 있으면 시설에서 1개를 꺼내 올린다 (provide_item)
## 앞 벨트부터 처리해서, 줄지어 선 물건들이 같은 순간에 함께 움직인다.
## 칸마다 받는 방향·내보낼 방향은 Conveyor 의 훅(accepts_dir / can_take / exit_dirs / all_exit_dirs / on_sent)이 정한다.
## 벨트는 앞으로 하나, 분배기·합류기·필터 분배기(Router, §62)는 이 훅을 덮어써서 갈래를 나누거나 합친다.
## 한 번에 반 칸 넘게 움직이지 않도록 잘게 나눈다 (야간 생산은 10분씩 들어온다).

## 벨트 무늬 한 바퀴(4장)가 도는 데 걸리는 이동 칸 수 (무늬 간격 8px = 반 칸)
const FRAME_TILES := 0.5

var grid: BuildGrid
## 다시 계산할 것: 앞 벨트부터의 순서, 모양, 시설 출구 목록 (시설이 바뀌면 BuildGrid 가 표시한다)
var _dirty := true
var _order: Array[Conveyor] = []
var _outputs: Array[Dictionary] = []   # [{"obj": Placeable, "port": 포트}]
var _phase := 0.0


func _init(build_grid: BuildGrid) -> void:
	grid = build_grid


func mark_dirty() -> void:
	_dirty = true


## 지금 바로 다시 계산한다 (시간이 멈춘 건설 모드에서도 꺾인 모양이 바로 보이게)
func refresh() -> void:
	_rebuild()


func belts() -> Array[Conveyor]:
	var out: Array[Conveyor] = []
	for obj in grid.objects():
		if obj is Conveyor:
			out.append(obj)
	return out


## 한 시간(게임 시계)에 물건이 지나가는 칸 수 (placeables.json conveyor.conveyor.tiles_per_hour)
func tiles_per_hour() -> float:
	var def := PlaceableDB.get_def("conveyor")
	var c: Variant = def.data.get("conveyor", {}) if def else {}
	return maxf(0.0, float(c.get("tiles_per_hour", 60))) if c is Dictionary else 60.0


# ---------- 연결 판정

## 벨트 b 가 앞으로 물건을 넘길 다음 칸(벨트·분배기·합류기). 받지 않는 모양이면 null (마주 보는 벨트 등)
func next_belt(b: Conveyor) -> Conveyor:
	var n := grid.object_at(b.cell + b.facing()) as Conveyor
	if n == null or not n.accepts_dir(b.facing()):
		return null
	return n


## b 가 물건을 넘길 수 있는 모든 다음 칸 (분배기는 여러 개). 순서 계산용
func downstream(b: Conveyor) -> Array[Conveyor]:
	var out: Array[Conveyor] = []
	for d in b.all_exit_dirs():
		var n := grid.object_at(b.cell + d) as Conveyor
		if n != null and n.accepts_dir(d) and n not in out:
			out.append(n)
	return out


## 칸 at 이 d 방향으로 들어오는 물건을 받는 시설 입구면 그 시설 (아니면 null)
func _input_facility(at: Vector2i, d: Vector2i) -> Placeable:
	var obj := grid.object_at(at)
	if obj == null or obj is Conveyor:
		return null
	for p in obj.ports():
		if p.type == "in" and p.cell == at and p.dir == -d:
			return obj
	return null


## 벨트 b 가 가리키는 칸이 어떤 시설의 입구면 그 시설 (아니면 null)
func target_facility(b: Conveyor) -> Placeable:
	return _input_facility(b.cell + b.facing(), b.facing())


## 이 칸으로 물건을 넣어 주는 쪽이 side(이 칸에서 본 방향)에 있는가: 이 칸을 가리키는 벨트, 또는 이 칸이 바깥인 시설 출구
func _fed_from(b: Conveyor, side: Vector2i) -> bool:
	var obj := grid.object_at(b.cell + side)
	if obj == null:
		return false
	if obj is Conveyor:
		return -side in obj.all_exit_dirs()
	for p in obj.ports():
		if p.type == "out" and p.outside == b.cell and p.dir == -side:
			return true
	return false


## 들어오는 쪽을 보고 모양을 정한다 (§58): 뒤에서 들어오거나 양옆 모두/아무 데서도 안 들어오면 직선, 한쪽 옆에서만 들어오면 꺾임
func shape_of(b: Conveyor) -> Conveyor.Shape:
	if _fed_from(b, -b.facing()):
		return Conveyor.Shape.STRAIGHT
	var left := _fed_from(b, Placeable.rotate_dir(Vector2i.LEFT, b.turns))
	var right := _fed_from(b, Placeable.rotate_dir(Vector2i.RIGHT, b.turns))
	if left and not right:
		return Conveyor.Shape.FROM_LEFT
	if right and not left:
		return Conveyor.Shape.FROM_RIGHT
	return Conveyor.Shape.STRAIGHT


func _rebuild() -> void:
	_dirty = false
	var all := belts()
	# 앞 벨트부터: 다음 벨트가 없는 벨트(끝)에서 시작해 거꾸로 따라간다. 고리 모양은 남은 순서대로 붙인다
	var feeders := {}   # Conveyor -> [그 벨트로 넘기는 벨트들]
	var heads: Array[Conveyor] = []
	for b in all:
		var next := downstream(b)
		if next.is_empty():
			heads.append(b)
		for n in next:
			if not feeders.has(n):
				feeders[n] = []
			feeders[n].append(b)
	_order.clear()
	var seen := {}
	var queue: Array[Conveyor] = heads.duplicate()
	for b in all:
		if not seen.has(b) and queue.is_empty():
			queue.append(b)  # 고리: 아무 곳에서나 시작
		while not queue.is_empty():
			var cur: Conveyor = queue.pop_front()
			if seen.has(cur):
				continue
			seen[cur] = true
			_order.append(cur)
			for f: Conveyor in feeders.get(cur, []):
				if not seen.has(f):
					queue.append(f)
	_outputs.clear()
	for obj in grid.objects():
		if obj is Conveyor:
			continue
		for p in obj.ports():
			if p.type == "out":
				_outputs.append({"obj": obj, "port": p})
	for b in all:
		if not b is Router:
			b.set_shape(shape_of(b))


# ---------- 움직이기

## 게임 시계 minutes 분만큼 움직인다
func tick(minutes: float) -> void:
	if minutes <= 0.0:
		return
	if _dirty:
		_rebuild()
	if _order.is_empty():
		return
	var tiles := tiles_per_hour() / 60.0 * minutes
	if tiles <= 0.0:
		return
	var steps := maxi(1, ceili(tiles / 0.5))
	for i in steps:
		_step(tiles / steps)
	_phase = fmod(_phase + tiles, FRAME_TILES)
	var frame := int(_phase / FRAME_TILES * Conveyor.FRAMES)
	for b in _order:
		if is_instance_valid(b):
			b.set_frame(frame)


func _step(dist: float) -> void:
	for b in _order:
		if not is_instance_valid(b) or not b.has_item():
			continue
		b.progress += dist
		if b.progress < 1.0:
			b.queue_redraw()
			continue
		var leftover := minf(b.progress - 1.0, 0.99)
		var sent := false
		for d in b.exit_dirs():
			if _send(b, d, leftover):
				b.on_sent(d)
				b.clear_item()
				sent = true
				break
		if not sent:
			b.progress = 1.0  # 넘기지 못해 끝에서 기다린다
			b.queue_redraw()
	for o in _outputs:
		var obj: Placeable = o.obj
		if not is_instance_valid(obj):
			continue
		var belt := grid.object_at(o.port.outside) as Conveyor
		if belt == null or not belt.can_take(o.port.dir, grid):
			continue
		var it := obj.provide_item()
		if not it.is_empty():
			belt.put(str(it.id), str(it.get("quality", Quality.NONE)), 0.0, o.port.dir)


## b 의 물건을 d 방향 칸(벨트·분배기·합류기 또는 시설 입구)으로 넘긴다. 넘겼으면 true
func _send(b: Conveyor, d: Vector2i, leftover: float) -> bool:
	var at := b.cell + d
	var obj := grid.object_at(at)
	if obj is Conveyor:
		return obj.can_take(d, grid) and obj.put(str(b.item.id), str(b.item.quality), leftover, d)
	var fac := _input_facility(at, d)
	if fac == null or not fac.accept_item(str(b.item.id), str(b.item.quality)):
		return false
	Events.belt_delivered.emit(fac, str(b.item.id))  # 스토리 MQ18·MQ20
	return true
