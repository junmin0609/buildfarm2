class_name Router
extends Conveyor
## 분배기 · 합류기 · 필터 분배기 (BUILD_FARM_PLAN §62). 컨베이어처럼 한 칸에 물건 1개를 잠깐 들고 있다가 넘긴다.
## placeables.json 의 "router": {"kind": "split" / "merge" / "filter"}. 전기는 쓰지 않는다 (컨베이어와 같은 규칙).
##
## 방향: facing = 앞(내보내는 기본 방향). 왼쪽·오른쪽은 물건이 흐르는 방향 기준 (앞을 보고 선 사람의 왼손·오른손)
##   split  분배기 (사용자 결정: 3갈래): 뒤에서 받아 왼쪽 → 앞 → 오른쪽 순서로 돌아가며 1개씩.
##          벨트가 이어지지 않았거나 막힌 쪽은 건너뛴다 (2곳만 이어졌으면 반반)
##   merge  합류기: 뒤·왼쪽·오른쪽에서 받아 앞으로. 여러 쪽에서 기다리면 번갈아 받는다 (한쪽만 계속 들어가지 않게)
##   filter 필터 분배기 (사용자 결정): 왼쪽·오른쪽 출구마다 보낼 물건을 정한다 (창고 필터와 같은 종류).
##          맞는 물건은 그쪽으로(둘 다 맞으면 번갈아), 아무 데도 안 맞으면 앞으로. 정한 쪽이 막히면 기다린다 (섞이지 않게)
## 물건은 사라지지 않는다. 철거하면 들고 있던 물건을 돌려준다 (Conveyor 와 같음).

const REACH := 14.0
## 필터 분배기 출구 필터 종류 (저장값) → 화면 이름. "none" = 아무것도 안 보냄
const FILTERS := {
	"none": "안 보냄",
	"crop": "작물만",
	"seed": "씨앗만",
	"material": "재료만",
	"processed": "가공품만",
	"items": "지정 아이템",
}
const MAX_FILTER_ITEMS := 9

var prompt := "[E] 필터 분배기"
## 분배기: 다음에 먼저 시도할 출구 (0 왼쪽, 1 앞, 2 오른쪽)
var turn := 0
## 합류기: 마지막으로 받은 쪽 (움직인 방향)
var last_in := Vector2i.ZERO
## 필터 분배기: {"left": {"mode", "items"}, "right": {...}}
var filters := {"left": {"mode": "none", "items": [] as Array[String]}, "right": {"mode": "none", "items": [] as Array[String]}}


func kind() -> String:
	var c: Variant = def.data.get("router", {}) if def else {}
	return str(c.get("kind", "split")) if c is Dictionary else "split"


func left_dir() -> Vector2i:
	var f := facing()
	return Vector2i(f.y, -f.x)


func right_dir() -> Vector2i:
	var f := facing()
	return Vector2i(-f.y, f.x)


func _ready() -> void:
	super._ready()
	_belt.visible = false  # 벨트 무늬 대신 시설 그림
	_sprite.show_behind_parent = true  # 위에 올린 물건이 그림 위에 보이게
	if kind() == "filter":
		add_to_group("interactables")


# ---------- 연결 규칙 (Conveyor 덮어쓰기)

func set_shape(_s: Shape) -> void:
	pass


func accepts_dir(d: Vector2i) -> bool:
	if kind() == "merge":
		return d != -facing()
	return d == facing()  # 분배기·필터 분배기: 뒤에서만


func can_take(d: Vector2i, grid: BuildGrid) -> bool:
	if not super.can_take(d, grid):
		return false
	if kind() != "merge":
		return true
	# 합류기: 뒤 → 왼쪽 → 오른쪽 순서로 돌아가며 받는다. 마지막으로 받은 쪽 다음부터 보면서
	# d 보다 차례가 앞선 쪽에 기다리는 물건이 있으면 양보한다 (어느 한쪽도 굶지 않게)
	var cycle := [facing(), -left_dir(), -right_dir()]
	var start := (cycle.find(last_in) + 1) % 3 if last_in in cycle else 0
	for k in 3:
		var side: Vector2i = cycle[(start + k) % 3]
		if side == d:
			return true
		if _waiting_from(side, grid):
			return false
	return true


## side 방향으로 움직여 이 칸에 들어오려고 끝에서 기다리는 물건이 있는가
func _waiting_from(side: Vector2i, grid: BuildGrid) -> bool:
	var n := grid.object_at(cell - side) as Conveyor
	return n != null and n.has_item() and n.progress >= 1.0 and side in n.exit_dirs()


func all_exit_dirs() -> Array[Vector2i]:
	var out: Array[Vector2i] = [facing()]
	if kind() != "merge":
		out = [left_dir(), facing(), right_dir()]
	return out


func exit_dirs() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match kind():
		"merge":
			out.append(facing())
		"filter":
			var it := ItemDB.get_item(str(item.get("id", "")))
			var to_left := matches("left", it)
			var to_right := matches("right", it)
			if to_left and to_right:
				out.append(left_dir() if turn % 2 == 0 else right_dir())
				out.append(right_dir() if turn % 2 == 0 else left_dir())
			elif to_left:
				out.append(left_dir())
			elif to_right:
				out.append(right_dir())
			else:
				out.append(facing())
		_:
			var dirs := [left_dir(), facing(), right_dir()]
			for i in 3:
				out.append(dirs[(turn + i) % 3])
	return out


func on_sent(d: Vector2i) -> void:
	match kind():
		"split":
			turn = ([left_dir(), facing(), right_dir()].find(d) + 1) % 3
		"filter":
			if d == left_dir() or d == right_dir():
				turn = (turn + 1) % 2


func put(item_id: String, quality: String, at := 0.0, from_dir := Vector2i.ZERO) -> bool:
	if not super.put(item_id, quality, at, from_dir):
		return false
	last_in = from_dir
	return true


## 들어온 가장자리 → 가운데 (어디로 나갈지는 넘길 때 정해진다)
func item_position() -> Vector2:
	var center := Vector2(0, -TILE / 2.0)
	var from := -Vector2(came_dir if came_dir != Vector2i.ZERO else facing()) * (TILE / 2.0)
	return center + from * (1.0 - clampf(progress, 0.0, 1.0))


# ---------- 필터 분배기

func matches(side: String, it: ItemDef) -> bool:
	var f: Dictionary = filters.get(side, {})
	var mode := str(f.get("mode", "none"))
	if it == null or mode == "none":
		return false
	var items: Array[String] = []
	for id: Variant in f.get("items", []):
		items.append(str(id))
	return Warehouse._matches(it, mode, items)


func set_filter_mode(side: String, mode: String) -> bool:
	if not filters.has(side) or not FILTERS.has(mode):
		return false
	filters[side].mode = mode
	Events.router_changed.emit()
	return true


func add_filter_item(side: String, item_id: String) -> bool:
	var items: Array = filters[side].items if filters.has(side) else []
	if not filters.has(side) or not ItemDB.has_item(item_id) or item_id in items or items.size() >= MAX_FILTER_ITEMS:
		return false
	items.append(item_id)
	Events.router_changed.emit()
	return true


func remove_filter_item(side: String, item_id: String) -> void:
	if filters.has(side) and item_id in filters[side].items:
		filters[side].items.erase(item_id)
		Events.router_changed.emit()


func filter_text(side: String) -> String:
	var f: Dictionary = filters.get(side, {})
	if str(f.get("mode", "none")) != "items":
		return FILTERS.get(str(f.get("mode", "none")), "안 보냄")
	var names: Array[String] = []
	for id: Variant in f.get("items", []):
		names.append(ItemDB.get_item(str(id)).name)
	return "지정: " + (", ".join(names) if not names.is_empty() else "없음")


func interact_point() -> Vector2:
	return global_position + Vector2(0, 7)


func can_interact(from: Vector2) -> bool:
	return kind() == "filter" and from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	Events.router_requested.emit(self)


# ---------- 저장

func save_state() -> Dictionary:
	var out := super.save_state()
	out["turn"] = turn
	out["last_in"] = [last_in.x, last_in.y]
	if not came_dir == Vector2i.ZERO:
		out["came"] = [came_dir.x, came_dir.y]
	if kind() == "filter":
		out["filters"] = {"left": {"mode": filters.left.mode, "items": filters.left.items.duplicate()},
				"right": {"mode": filters.right.mode, "items": filters.right.items.duplicate()}}
	return out


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	turn = clampi(int(data.get("turn", 0)), 0, 2) if typeof(data.get("turn")) in [TYPE_INT, TYPE_FLOAT] else 0
	last_in = DataFile.to_vector2i(data.get("last_in"), Vector2i.ZERO)
	came_dir = DataFile.to_vector2i(data.get("came"), Vector2i.ZERO)
	var raw: Variant = data.get("filters")
	if raw is Dictionary:
		for side in ["left", "right"]:
			var f: Variant = raw.get(side)
			if not f is Dictionary:
				continue
			filters[side].mode = str(f.get("mode", "none")) if FILTERS.has(str(f.get("mode", ""))) else "none"
			filters[side].items.clear()
			var items: Variant = f.get("items", [])
			if items is Array:
				for id: Variant in items:
					if ItemDB.has_item(str(id)) and filters[side].items.size() < MAX_FILTER_ITEMS and str(id) not in filters[side].items:
						filters[side].items.append(str(id))
