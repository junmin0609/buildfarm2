class_name Furnace
extends Placeable
## 용광로 (사용자 결정: 1x1, 기계상점에서 사서 놓음, 손으로 넣고 꺼내기). 광석 5 + 석탄 1 → 주괴 1.
## 광석을 들고 용광로를 클릭하면 한 번 굽기 시작한다 (가방에서 광석·석탄이 빠짐). 한 번에 한 번만 굽는다.
## 게임 시계로 굽고 (창이 열려 시계가 멈추면 같이 멈춤), 밤사이에도 하던 것은 마저 굽는다.
## 다 구운 주괴는 용광로 안에 쌓이고 (같은 주괴만, max_output 까지), [E] 나 아무것이나 들고 클릭하면 가방으로 꺼낸다.
## 굽는 법은 placeables.json 의 "furnace" (광석 id → 개수·석탄·분·결과물).

## 지금 굽는 광석 id ("" = 쉬는 중)
var smelting := ""
## 굽기가 끝날 때까지 남은 게임 분
var minutes_left := 0.0
## 다 구운 주괴 (id, 개수)
var output_id := ""
var output := 0

const REACH := 14.0

var prompt := "용광로 (광석을 들고 클릭)"
var _icon: Sprite2D
var _fire: Node2D
var _bob := 0.0
var _glow := 0.0


func config() -> Dictionary:
	var c: Variant = def.data.get("furnace", {}) if def else {}
	return c if c is Dictionary else {}


func recipes() -> Dictionary:
	return config().get("recipes", {})


## ore_id 를 구우면 나오는 것 {"ore": 개수, "coal": 개수, "minutes": 분, "output": 주괴 id}. 굽는 광석이 아니면 {}
func recipe_of(ore_id: String) -> Dictionary:
	return recipes().get(ore_id, {})


func max_output() -> int:
	return int(config().get("max_output", 10))


func is_working() -> bool:
	return smelting != ""


## 광석을 넣어 굽기 시작한다. 시작했으면 "", 아니면 안 되는 이유
func start(inv: Inventory, ore_id: String) -> String:
	var r := recipe_of(ore_id)
	if r.is_empty():
		return "용광로에는 광석만 넣을 수 있어요."
	if is_working():
		return "굽는 중이에요. (남은 시간 %d분)" % ceili(minutes_left)
	var bar := str(r.get("output", ""))
	if output > 0 and output_id != bar:
		return "다 구운 %s을(를) 먼저 꺼내 주세요." % ItemDB.get_item(output_id).name
	if output >= max_output():
		return "용광로가 가득 찼어요. 주괴를 꺼내 주세요."
	var need_ore := int(r.get("ore", 5))
	var need_coal := int(r.get("coal", 1))
	if inv.count_of(ore_id) < need_ore:
		return "%s이(가) %d개 있어야 해요. (가진 것 %d)" % [ItemDB.get_item(ore_id).name, need_ore, inv.count_of(ore_id)]
	if inv.count_of("coal") < need_coal:
		return "연료로 석탄이 %d개 있어야 해요." % need_coal
	inv.remove(ore_id, need_ore)
	inv.remove("coal", need_coal)
	smelting = ore_id
	minutes_left = float(r.get("minutes", 60))
	_changed()
	return ""


## 다 구운 주괴를 가방으로. 옮긴 개수
func take_output(inv: Inventory) -> int:
	if output <= 0:
		return 0
	var n := 0
	while n < output and inv.can_add(output_id, 1):
		inv.add(output_id, 1)
		n += 1
	output -= n
	if output == 0:
		output_id = ""
	_changed()
	return n


func advance(minutes: float) -> int:
	if not is_working():
		return 0
	minutes_left -= minutes
	if minutes_left > 0.0:
		return 0
	var bar := str(recipe_of(smelting).get("output", ""))
	output_id = bar
	output += 1
	smelting = ""
	minutes_left = 0.0
	_changed()
	return 1


func on_time(minutes: float) -> void:
	advance(minutes)


## 밤사이: 굽던 것은 마저 굽는다 (손으로 넣는 기계라 새로 시작하지는 않음)
func on_night_production(_w: FarmWorld, report: Dictionary, minutes: float) -> void:
	if advance(minutes) > 0:
		var night: Dictionary = report.get("night_production", {})
		night["processed"] = int(night.get("processed", 0)) + 1
		report["night_production"] = night


# ---------- 손에 든 것으로 클릭 (Player._use_selected)

## 광석이면 넣고, 아니면 다 구운 주괴를 꺼낸다. 무언가 했거나 안내를 띄웠으면 true
func use_held_item(inv: Inventory, index: int) -> bool:
	var item := inv.item_at(index)
	if item and not recipe_of(item.id).is_empty():
		var problem := start(inv, item.id)
		if problem == "":
			Events.toast.emit("%s 굽기 시작 (%d분)" % [ItemDB.get_item(str(recipe_of(item.id).output)).name, ceili(minutes_left)])
		else:
			Events.toast.emit(problem)
		return true
	return _collect(inv)


func _collect(inv: Inventory) -> bool:
	if output > 0:
		var name_of := ItemDB.get_item(output_id).name
		var n := take_output(inv)
		Events.toast.emit("%s +%d" % [name_of, n] if n > 0 else "가방이 가득 찼어요.")
		return true
	if is_working():
		Events.toast.emit("%s 굽는 중 (남은 시간 %d분)" % [ItemDB.get_item(str(recipe_of(smelting).output)).name, ceili(minutes_left)])
	else:
		Events.toast.emit("광석을 들고 용광로를 클릭하면 구워요. (광석 5 + 석탄 1)")
	return true


# ---------- 철거·저장

## 굽던 광석·석탄은 돌려주고, 다 구운 주괴도 함께
func contents() -> Array:
	var out: Array = []
	if is_working():
		var r := recipe_of(smelting)
		out.append({"id": smelting, "count": int(r.get("ore", 5)), "quality": Quality.NONE})
		out.append({"id": "coal", "count": int(r.get("coal", 1)), "quality": Quality.NONE})
	if output > 0:
		out.append({"id": output_id, "count": output, "quality": Quality.NONE})
	return out


func take_contents() -> void:
	smelting = ""
	minutes_left = 0.0
	output = 0
	output_id = ""
	_changed()


func save_state() -> Dictionary:
	return {"smelting": smelting, "minutes_left": minutes_left, "output_id": output_id, "output": output}


func load_state(data: Dictionary) -> void:
	smelting = str(data.get("smelting", ""))
	if recipe_of(smelting).is_empty():
		smelting = ""
	minutes_left = maxf(0.0, float(data.get("minutes_left", 0.0))) if smelting != "" else 0.0
	output_id = str(data.get("output_id", ""))
	output = maxi(0, int(data.get("output", 0))) if ItemDB.has_item(output_id) else 0
	if output == 0:
		output_id = ""
	_changed()


func _changed() -> void:
	prompt = "[E] 주괴 꺼내기" if output > 0 else "용광로 (광석을 들고 클릭)"
	_update_icon()
	if _fire:
		_fire.queue_redraw()


# ---------- [E] 상호작용 · 그림

func _ready() -> void:
	super._ready()
	add_to_group("interactables")
	_icon = Sprite2D.new()
	_icon.texture = Art.ITEMS
	_icon.region_enabled = true
	_icon.scale = Vector2.ONE * Art.TILE / Art.ICON
	_icon.z_index = 5
	add_child(_icon)
	# 아궁이 불빛은 그림 위에 (부모 _draw 는 그림 아래에 그려지므로 자식 노드로)
	_fire = Node2D.new()
	_fire.draw.connect(_draw_fire)
	add_child(_fire)
	_changed()


func interact_point() -> Vector2:
	return global_position + Vector2(0, 7)


func can_interact(from: Vector2) -> bool:
	return from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	_collect(GameState.inventory)


## 다 구운 주괴가 있으면 용광로 위에 주괴 아이콘이 통통 튄다
func _update_icon() -> void:
	if _icon == null:
		return
	_icon.visible = output > 0 and ItemDB.has_item(output_id)
	if _icon.visible:
		_icon.region_rect = Art.item_region(ItemDB.get_item(output_id))
	var tex := def.texture_for(turns) if def else null
	_icon.position = Vector2(0, -(tex.get_height() if tex else 16) - 6)


func _process(delta: float) -> void:
	if _icon and _icon.visible:
		_bob += delta
		_icon.offset.y = roundf(sin(_bob * 4.0) * 1.5)
	if is_working() and _fire:
		_glow += delta
		_fire.queue_redraw()


## 굽는 동안 아궁이 불빛이 일렁인다 (그림의 아궁이 자리: 아래 가운데)
func _draw_fire() -> void:
	if not is_working():
		return
	var f := 0.75 + 0.25 * sin(_glow * 9.0)
	_fire.draw_rect(Rect2(-4, -7, 8, 4), Color(1.0, 0.55, 0.15, 0.85 * f))
	_fire.draw_rect(Rect2(-2, -6, 4, 2), Color(1.0, 0.9, 0.5, f))
