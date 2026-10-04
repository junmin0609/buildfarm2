class_name Player
extends CharacterBody2D
## 플레이어. 이동하고, 앞 칸(또는 손 닿는 거리 안의 마우스 칸)에 손에 든 아이템을 쓴다.
## 손 닿는 거리는 data/player.json 의 reach_tiles (기획서 §9: 2칸).
## 노드 위치는 발밑이다. 그림은 player.png (16x24 프레임, 줄: 아래/위/옆, 칸: 걷기 4프레임)

const SPEED := 68.0
const FRAME_TIME := 0.14
const SWING_TIME := 0.25

const ROW_DOWN := 0
const ROW_UP := 1
const ROW_SIDE := 2

const DATA_PATH := "res://data/player.json"

@onready var sprite: Sprite2D = $Sprite2D
@onready var camera: Camera2D = $Camera2D

var facing := Vector2i.DOWN
## 마우스로 고를 수 있는 거리 (칸)
var reach := int(DataFile.load_dict(DATA_PATH).get("reach_tiles", 2))
var _anim_time := 0.0
var _swing := 0.0
var _swing_item: ItemDef = null
var _prompt_text := ""
var _bubble_time := 0.0


func _world() -> FarmWorld:
	return get_parent().get_parent() as FarmWorld


func _physics_process(delta: float) -> void:
	var dir := Vector2.ZERO
	if not GameState.is_input_locked():
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * SPEED
	move_and_slide()
	if dir != Vector2.ZERO:
		facing = Vector2i(signi(roundi(dir.x)), 0) if absf(dir.x) > absf(dir.y) else Vector2i(0, signi(roundi(dir.y)))
		_anim_time += delta
	else:
		_anim_time = 0.0
	_swing = maxf(_swing - delta, 0.0)
	_bubble_time += delta
	_update_sprite(dir != Vector2.ZERO)

	var world := _world()
	if world:
		world.farm.set_cursor(target_cell(), not world.build_mode.is_active())
	_update_prompt()
	queue_redraw()


# ---------- 저장용 (수동 저장은 저장 당시 위치에서 다시 시작한다 §102)

func to_data() -> Dictionary:
	return {"position": [global_position.x, global_position.y], "facing": [facing.x, facing.y]}


func load_data(data: Variant) -> bool:
	if not data is Dictionary or not data.has("position"):
		return false
	var pos := DataFile.to_vector2(data.get("position"), global_position)
	var dir := DataFile.to_vector2i(data.get("facing"), Vector2i.DOWN)
	wake_at(pos)
	if dir in [Vector2i.DOWN, Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT]:
		facing = dir
		if is_node_ready():
			_update_sprite(false)
	return true


## 새 날 아침: 집 앞에서 아래를 보고 선 채로 시작한다 (움직임·휘두르기 초기화)
func wake_at(pos: Vector2) -> void:
	global_position = pos
	velocity = Vector2.ZERO
	facing = Vector2i.DOWN
	_anim_time = 0.0
	_swing = 0.0
	_swing_item = null
	if is_node_ready():
		_update_sprite(false)
		camera.reset_smoothing()


func _update_sprite(moving: bool) -> void:
	var row := ROW_SIDE if facing.x != 0 else (ROW_UP if facing == Vector2i.UP else ROW_DOWN)
	var col := (int(_anim_time / FRAME_TIME) % 4) if moving else 0
	sprite.frame = row * 4 + col
	sprite.flip_h = facing == Vector2i.LEFT


## 행동할 칸: 마우스가 플레이어 주변 reach 칸 안이면 그 칸, 아니면 바라보는 방향 바로 앞 칸.
func target_cell() -> Vector2i:
	var world := _world()
	return pick_target(my_cell(), world.world_to_cell(get_global_mouse_position()))


## cell 쪽으로 일하는 방향: 내 칸에서 그 칸으로 더 많이 떨어진 축. 내 칸이면 바라보는 방향.
func work_dir(cell: Vector2i) -> Vector2i:
	var d := cell - my_cell()
	if d == Vector2i.ZERO:
		return facing
	if absi(d.x) >= absi(d.y):
		return Vector2i(signi(d.x), 0)
	return Vector2i(0, signi(d.y))


func my_cell() -> Vector2i:
	return _world().world_to_cell(global_position + Vector2(0, -3))


func pick_target(from_cell: Vector2i, mouse_cell: Vector2i) -> Vector2i:
	var d := (mouse_cell - from_cell).abs()
	if maxi(d.x, d.y) <= reach and mouse_cell != from_cell:
		return mouse_cell
	return from_cell + facing


func _unhandled_input(event: InputEvent) -> void:
	if _world() and _world().build_mode.is_active():
		return  # 건설 모드에서는 클릭이 설치·철거에 쓰인다
	if GameState.is_input_locked():
		return  # 가방 창이 열려 있는 동안 (시간은 흐른다)
	if event.is_action_pressed("use_tool"):
		_use_selected()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_interact()
		get_viewport().set_input_as_handled()


func _use_selected() -> void:
	var cell := target_cell()
	var item := GameState.selected_item()
	_start_swing(item)
	# 다 자란 작물은 무엇을 들고 있든 수확한다
	if _try_harvest(cell):
		return
	# 장애물이 있으면 개간 (도구가 맞지 않으면 안내만 하고 끝)
	if _world().obstacles.try_clear(cell, item):
		return
	if item == null:
		return
	if item.tool_type == "watering_can":
		WateringCan.use(_world(), cell, GameState.inventory, GameState.selected_slot)
		return
	if _world().farm.use_item(cell, item, work_dir(cell)) and item.kind in [ItemDef.Kind.SEED, ItemDef.Kind.FERTILIZER]:
		GameState.inventory.remove_at(GameState.selected_slot, 1)


func _start_swing(item: ItemDef) -> void:
	_swing = SWING_TIME
	_swing_item = item


func _interact() -> void:
	var target: Variant = _nearest_interactable()
	if target:
		target.interact(self)
		return
	_try_harvest(target_cell())


func _try_harvest(cell: Vector2i) -> bool:
	var farm := _world().farm
	var got := farm.roll_harvest(cell)
	if got.is_empty():
		return false
	# 자리가 없으면 작물은 밭에 그대로 남는다 (§18, §105)
	if not GameState.inventory.can_add(got.id, got.count, got.quality):
		Events.toast.emit("가방이 가득 찼어요.")
		return true
	farm.finish_harvest(cell)
	GameState.inventory.add(got.id, got.count, got.quality)
	Events.toast.emit("%s(%s) %d개 수확!" % [ItemDB.get_item(got.id).name, Quality.name_of(got.quality), got.count])
	return true


## 가장 가까운 [E] 대상. Interactable 건물과 [E] 로 쓰는 설치 시설(퇴비통 등)을 함께 찾는다.
## 둘 다 prompt / interact_point / can_interact / interact 를 가진다.
func _nearest_interactable() -> Node2D:
	var best: Node2D = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("interactables"):
		var it: Variant = node
		if it is Node2D and it.can_interact(global_position):
			var d := global_position.distance_to(it.interact_point())
			if d < best_dist:
				best = it
				best_dist = d
	return best


func _update_prompt() -> void:
	var target: Variant = _nearest_interactable()
	var text: String = target.prompt if target else ""
	if text != _prompt_text:
		_prompt_text = text
		Events.prompt_changed.emit(text)


## 도구를 휘두를 때 손에 든 아이템 그림을 앞쪽으로 휘두른다. (스프라이트 위에 그려짐)
func _draw() -> void:
	# 건물 앞이면 머리 위에 말풍선이 통통 튄다
	if _prompt_text != "":
		var bob := roundf(sin(_bubble_time * 5.0) * 1.0)
		draw_texture_rect_region(Art.UI_ICONS, Rect2(-7, -38 + bob, 16, 16), Rect2(3 * Art.TILE, 0, Art.TILE, Art.TILE))
	if _swing <= 0.0 or _swing_item == null:
		return
	var t := 1.0 - _swing / SWING_TIME
	var dir := Vector2(facing)
	var base_angle := dir.angle() - PI / 2.0
	var angle := base_angle + lerpf(-0.9, 0.9, t) * (-1.0 if facing == Vector2i.LEFT else 1.0)
	var hand := Vector2(0, -9) + dir * 4.0
	draw_set_transform(hand + Vector2(0, 7).rotated(angle) + dir * 3.0, angle + PI, Vector2.ONE * 0.75)
	draw_texture_rect_region(Art.ITEMS, Rect2(-8, -8, 16, 16), Art.item_region(_swing_item))
	draw_set_transform(Vector2.ZERO)
