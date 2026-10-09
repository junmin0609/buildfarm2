class_name Warehouse
extends Placeable
## 창고 (BUILD_FARM_PLAN §67, §68). 건설 모드로 짓는 실제 보관 시설.
## 수치는 placeables.json 의 "storage" (단계별 칸 수·증축 비용·지정 아이템 필터 최대 개수).
##
## 규칙
##   - 창고마다 칸 수가 정해져 있다 (가방과 같은 칸 형식, 같은 아이템·품질끼리 쌓임)
##   - 증축하면 칸이 늘지만 마지막 단계가 한도다. 한 창고가 무한히 커지지 않는다
##   - 창고끼리 합쳐지지 않는다. 창고마다 따로 보관한다 (전체 공용 인벤토리 없음)
##   - 필터: 받을 물건을 정한다 (전체 / 작물만 / 씨앗만 / 재료만 / 가공품만 / 지정 아이템).
##     필터는 넣을 때만 본다. 필터를 바꿔도 이미 든 물건은 그대로 두고 꺼낼 수 있다 (아이템을 버리지 않음 §105)
##   - 철거하면 안의 물건 + 건설비 + 증축 비용을 모두 돌려준다. 가방 자리가 없으면 철거를 막는다 (§64, §106)
##
## 컨베이어 (§55, 사용자 결정): 입구로 들어온 물건은 받을 물건 필터를 지켜 넣는다 (못 받으면 벨트에서 기다림).
##   출구로는 "내보낼 물건"(출구 필터)에 맞는 물건을 앞 칸부터 1개씩 내보낸다. 정하지 않으면("안 내보냄") 내보내지 않는다.
##   출구 필터 종류는 받을 물건 필터와 같다 (전체 / 작물만 / ... / 지정 아이템).
## 자동 수확기(§66)도 insert(아이템, 개수, 품질)를 부르면 된다 (필터를 지키고, 못 넣은 개수를 돌려줌).

const REACH := 18.0
## 필터 종류 (저장값) → 화면 이름
const FILTERS := {
	"all": "전체",
	"crop": "작물만",
	"seed": "씨앗만",
	"material": "재료만",
	"processed": "가공품만",
	"items": "지정 아이템",
}
const FILTER_KINDS := {
	"crop": ItemDef.Kind.CROP,
	"seed": ItemDef.Kind.SEED,
	"material": ItemDef.Kind.MATERIAL,
	"processed": ItemDef.Kind.PROCESSED,
}

## 출구 필터 종류 (저장값) → 화면 이름. "none" = 안 내보냄 (기본)
const OUTPUT_FILTERS := {
	"none": "안 내보냄",
	"all": "전체",
	"crop": "작물만",
	"seed": "씨앗만",
	"material": "재료만",
	"processed": "가공품만",
	"items": "지정 아이템",
}

var prompt := "[E] 창고"
## 증축 단계 (0 = 처음 지은 상태)
var level := 0
var filter_mode := "all"
## filter_mode == "items" 일 때 받는 아이템 id
var filter_items: Array[String] = []
## 출구로 내보낼 물건 (컨베이어)
var output_mode := "none"
var output_items: Array[String] = []
var storage: Inventory


func setup(placeable_def: PlaceableDef, origin: Vector2i, new_turns := 0) -> void:
	super.setup(placeable_def, origin, new_turns)
	storage = Inventory.new(slot_count())
	storage.changed.connect(_changed)


# ---------- 설정

func config() -> Dictionary:
	var c: Variant = def.data.get("storage", {}) if def else {}
	return c if c is Dictionary else {}


func levels() -> Array:
	var l: Variant = config().get("levels", [])
	return l if l is Array and not l.is_empty() else [{"slots": 36}]


func max_level() -> int:
	return levels().size() - 1


func slots_at(lv: int) -> int:
	var entry: Variant = levels()[clampi(lv, 0, max_level())]
	return maxi(1, int(entry.get("slots", 36))) if entry is Dictionary else 36


func slot_count() -> int:
	return slots_at(level)


func max_filter_items() -> int:
	return maxi(1, int(config().get("max_filter_items", 9)))


# ---------- 증축

func can_upgrade_more() -> bool:
	return level < max_level()


## 다음 단계로 올리는 비용 {"price", "materials", "slots"}. 최고 단계면 빈 사전
func next_upgrade() -> Dictionary:
	if not can_upgrade_more():
		return {}
	var entry: Dictionary = levels()[level + 1]
	var mats := {}
	var raw: Variant = entry.get("materials", {})
	if raw is Dictionary:
		for mat_id: String in raw:
			mats[mat_id] = int(raw[mat_id])
	return {"price": int(entry.get("price", 0)), "materials": mats, "slots": slots_at(level + 1)}


## 증축할 수 없는 이유. 할 수 있으면 ""
func upgrade_problem(inv: Inventory) -> String:
	var next := next_upgrade()
	if next.is_empty():
		return "이미 가장 큰 창고예요."
	if GameState.money < next.price:
		return "돈이 부족해요. (%d G 필요)" % next.price
	for mat_id: String in next.materials:
		if inv.count_of(mat_id) < int(next.materials[mat_id]):
			var mat := ItemDB.get_item(mat_id)
			return "%s이(가) 부족해요. (%d개 필요)" % [mat.name if mat else mat_id, next.materials[mat_id]]
	return ""


## 돈·재료를 내고 한 단계 증축한다. 안의 물건은 그대로, 칸만 늘어난다.
func upgrade(inv: Inventory) -> bool:
	if upgrade_problem(inv) != "":
		return false
	var next := next_upgrade()
	if not GameState.try_spend(next.price):
		return false
	for mat_id: String in next.materials:
		inv.remove(mat_id, int(next.materials[mat_id]))
	level += 1
	storage.grow(slot_count())
	_changed()
	return true


## 지금까지 증축에 들인 돈·재료 (철거하면 돌려준다)
func extra_cost() -> Dictionary:
	var price := 0
	var mats := {}
	for lv in range(1, level + 1):
		var entry: Variant = levels()[lv]
		if not entry is Dictionary:
			continue
		price += int(entry.get("price", 0))
		var raw: Variant = entry.get("materials", {})
		if raw is Dictionary:
			for mat_id: String in raw:
				mats[mat_id] = int(mats.get(mat_id, 0)) + int(raw[mat_id])
	return {"price": price, "materials": mats}


# ---------- 필터

func accepts(item: ItemDef) -> bool:
	return _matches(item, filter_mode, filter_items)


## 출구로 내보낼 물건인가
func sends(item: ItemDef) -> bool:
	return output_mode != "none" and _matches(item, output_mode, output_items)


static func _matches(item: ItemDef, mode: String, items: Array[String]) -> bool:
	if item == null:
		return false
	match mode:
		"all":
			return true
		"items":
			return item.id in items
	return FILTER_KINDS.has(mode) and item.kind == FILTER_KINDS[mode]


func set_filter_mode(mode: String) -> bool:
	if not FILTERS.has(mode):
		return false
	filter_mode = mode
	_changed()
	return true


## 지정 아이템 필터에 추가 (최대 max_filter_items 개)
func add_filter_item(item_id: String) -> bool:
	if not ItemDB.has_item(item_id) or item_id in filter_items or filter_items.size() >= max_filter_items():
		return false
	filter_items.append(item_id)
	_changed()
	return true


func remove_filter_item(item_id: String) -> void:
	if item_id in filter_items:
		filter_items.erase(item_id)
		_changed()


func filter_text() -> String:
	if filter_mode != "items":
		return FILTERS[filter_mode]
	return _items_text(filter_items)


func set_output_mode(mode: String) -> bool:
	if not OUTPUT_FILTERS.has(mode):
		return false
	output_mode = mode
	_changed()
	return true


## 출구 지정 아이템에 추가 (최대 max_filter_items 개)
func add_output_item(item_id: String) -> bool:
	if not ItemDB.has_item(item_id) or item_id in output_items or output_items.size() >= max_filter_items():
		return false
	output_items.append(item_id)
	_changed()
	return true


func remove_output_item(item_id: String) -> void:
	if item_id in output_items:
		output_items.erase(item_id)
		_changed()


func output_text() -> String:
	if output_mode != "items":
		return OUTPUT_FILTERS[output_mode]
	return _items_text(output_items)


static func _items_text(ids: Array[String]) -> String:
	var names: Array[String] = []
	for id in ids:
		names.append(ItemDB.get_item(id).name)
	return "지정: " + (", ".join(names) if not names.is_empty() else "없음")


# ---------- 넣기 / 꺼내기

## 가방 index 칸에서 count 개(-1 이면 칸 전부)를 창고로 옮긴다. 옮긴 개수를 돌려준다.
## 필터에 맞지 않거나 자리가 없으면 0. 자리가 모자라면 들어가는 만큼만 옮긴다.
func deposit_slot(inv: Inventory, index: int, count := -1) -> int:
	if not accepts(inv.item_at(index)):
		return 0
	return _move_slot(inv, index, storage, count)


## 창고 index 칸에서 count 개(-1 이면 칸 전부)를 가방으로 꺼낸다. 필터와 상관없이 꺼낼 수 있다.
func withdraw_slot(inv: Inventory, index: int, count := -1) -> int:
	return _move_slot(storage, index, inv, count)


## 가방의 받을 수 있는 물건을 모두 창고로 (핫바 칸은 손에 든 도구라 건너뛴다). 옮긴 개수 합계
func deposit_all(inv: Inventory) -> int:
	var moved := 0
	for i in range(Inventory.HOTBAR_SIZE, inv.size()):
		if inv.get_slot(i) != null:
			moved += deposit_slot(inv, i)
	return moved


## 컨베이어·자동 투입용: 필터를 지키며 넣고, 못 넣은 개수를 돌려준다.
func insert(item_id: String, count: int, quality := Quality.NONE) -> int:
	if not accepts(ItemDB.get_item(item_id)):
		return count
	return storage.add(item_id, count, quality)


## 컨베이어 입구 (§55): 받을 물건 필터를 지켜 1개 넣는다
func accept_item(item_id: String, quality: String) -> bool:
	return insert(item_id, 1, quality) == 0


## 컨베이어 출구: 출구 필터에 맞는 물건을 앞 칸부터 1개 꺼낸다
func provide_item() -> Dictionary:
	if output_mode == "none":
		return {}
	for i in storage.size():
		var slot: Variant = storage.get_slot(i)
		if slot != null and sends(ItemDB.get_item(slot.id)):
			var it := {"id": slot.id, "quality": slot.get("quality", Quality.NONE)}
			storage.remove_at(i, 1)
			return it
	return {}


func used_slots() -> int:
	return storage.size() - storage.free_slots()


func is_empty() -> bool:
	return storage.free_slots() == storage.size()


static func _move_slot(from: Inventory, index: int, to: Inventory, count: int) -> int:
	var slot: Variant = from.get_slot(index)
	if slot == null:
		return 0
	var n: int = slot.count if count < 0 else mini(count, slot.count)
	var piece: Dictionary = slot.duplicate(true)
	piece.count = n
	var moved := n - to.put_slot(piece)
	if moved > 0:
		from.remove_at(index, moved)
	return moved


# ---------- 철거·저장

func contents() -> Array:
	var out: Array = []
	for slot: Variant in storage.slots:
		if slot != null:
			out.append(slot.duplicate(true))
	return out


func take_contents() -> void:
	storage.slots.fill(null)
	storage.changed.emit()


func save_state() -> Dictionary:
	return {"level": level, "filter": {"mode": filter_mode, "items": filter_items.duplicate()},
			"output": {"mode": output_mode, "items": output_items.duplicate()}, "slots": storage.to_data()}


func load_state(data: Dictionary) -> void:
	if typeof(data.get("level")) in [TYPE_INT, TYPE_FLOAT]:
		level = clampi(int(data.level), 0, max_level())
	storage.grow(slot_count())
	var filter: Variant = data.get("filter")
	if filter is Dictionary:
		filter_mode = str(filter.get("mode", "all")) if FILTERS.has(str(filter.get("mode", ""))) else "all"
		filter_items.clear()
		var items: Variant = filter.get("items", [])
		if items is Array:
			for id: Variant in items:
				if ItemDB.has_item(str(id)) and str(id) not in filter_items and filter_items.size() < max_filter_items():
					filter_items.append(str(id))
	var out: Variant = data.get("output")
	if out is Dictionary:
		output_mode = str(out.get("mode", "none")) if OUTPUT_FILTERS.has(str(out.get("mode", ""))) else "none"
		output_items.clear()
		var items: Variant = out.get("items", [])
		if items is Array:
			for id: Variant in items:
				if ItemDB.has_item(str(id)) and str(id) not in output_items and output_items.size() < max_filter_items():
					output_items.append(str(id))
	if data.get("slots") is Array:
		storage.load_data(data.slots)
	_changed()


func _changed() -> void:
	Events.warehouse_changed.emit()


# ---------- [E] 상호작용 (Interactable 건물과 같은 이름)

func _ready() -> void:
	super._ready()
	add_to_group("interactables")


func interact_point() -> Vector2:
	return global_position + Vector2(0, 7)


func can_interact(from: Vector2) -> bool:
	return from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	Events.warehouse_requested.emit(self)
