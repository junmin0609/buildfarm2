extends Node
## 돈, 날짜·시간, 인벤토리, 핫바 선택 같은 플레이어 진행 상태.
##
## 시간 (BUILD_FARM_PLAN §94, §95, 수치는 data/time.json)
##   하루 = 실제로 시간이 흐른 day_length_seconds(15분). 남은 시간이 warning_seconds_left(1분)가 되면 경고.
##   시계(minutes)는 흐른 시간에서 계산해 보여 주기만 한다.
##   상점·건설 창·건설 모드(설치·이동·철거) 동안은 멈춘다 (set_time_paused). 가방 창에서는 흐른다.

const TIME_DATA_PATH := "res://data/time.json"
const START_MONEY := 500

const STARTING_ITEMS := [
	["hoe", 1],
	["watering_can", 1],
	["carrot_seed", 12],
	["axe", 1],
	["pickaxe", 1],
]

var money := START_MONEY
var day := 1
var minutes := 0
## 오늘 실제로 흐른 시간(초). 멈춘 동안은 늘지 않는다.
var day_seconds := 0.0
var inventory := Inventory.new()
var selected_slot := 0

## 하루 길이·시계 설정 (data/time.json)
var day_length := 900.0
var warning_seconds := 60.0
var day_start := 7 * 60
var day_end := 26 * 60
var clock_step := 10

var _warned := false
## 시간을 멈추게 하는 이유들 ("shop", "build_menu", "build_mode" ...). 하나라도 있으면 멈춘다.
var _pause_reasons := {}
## 플레이어 조작을 막는 이유들 ("inventory" ...). 시간과는 따로다.
var _input_locks := {}


func _ready() -> void:
	# 트리가 멈춰도(창이 열려도) 시계는 _pause_reasons 만 보고 판단한다
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_time_config()
	_setup_input()
	inventory.changed.connect(func() -> void: Events.inventory_changed.emit())
	new_game()


func new_game() -> void:
	money = START_MONEY
	day = 1
	_reset_day_clock()
	_pause_reasons.clear()
	_input_locks.clear()
	inventory.load_data([])
	for entry: Array in STARTING_ITEMS:
		inventory.add(entry[0], entry[1])
	select_slot(0)
	Events.money_changed.emit(money)
	Events.time_changed.emit(day, minutes)


func _process(delta: float) -> void:
	advance_time(delta)


func _load_time_config() -> void:
	var cfg := DataFile.load_dict(TIME_DATA_PATH)
	day_length = maxf(1.0, float(cfg.get("day_length_seconds", day_length)))
	warning_seconds = float(cfg.get("warning_seconds_left", warning_seconds))
	day_start = int(cfg.get("day_start_minutes", day_start))
	day_end = int(cfg.get("day_end_minutes", day_end))
	clock_step = maxi(1, int(cfg.get("clock_step_minutes", clock_step)))


# ---------- 시간

## 실제 시간 seconds 만큼 하루를 흘려보낸다. 멈춘 상태면 아무것도 하지 않는다.
func advance_time(seconds: float) -> void:
	if is_time_paused():
		return
	day_seconds += seconds
	var shown := _clock_at(day_seconds)
	if shown != minutes:
		minutes = shown
		Events.time_changed.emit(day, minutes)
	if not _warned and seconds_left() <= warning_seconds:
		_warned = true
		Events.day_ending_soon.emit(seconds_left())
	if day_seconds >= day_length:
		request_day_end("time_up")


func seconds_left() -> float:
	return maxf(0.0, day_length - day_seconds)


func is_day_ending_soon() -> bool:
	return _warned


func set_time_paused(reason: String, paused: bool) -> void:
	if paused:
		_pause_reasons[reason] = true
	else:
		_pause_reasons.erase(reason)


func is_time_paused() -> bool:
	return not _pause_reasons.is_empty()


## 하루가 끝날 때: 시간 정지·입력 잠금을 모두 푼다
func clear_pauses_and_locks() -> void:
	_pause_reasons.clear()
	_input_locks.clear()


func set_input_locked(reason: String, locked: bool) -> void:
	if locked:
		_input_locks[reason] = true
	else:
		_input_locks.erase(reason)


func is_input_locked() -> bool:
	return not _input_locks.is_empty()


## 시계를 특정 시각으로 맞춘다 (테스트·화면 확인용). 흐른 시간도 그 시각에 맞춘다.
func set_clock(clock_minutes: int) -> void:
	var span := float(day_end - day_start)
	day_seconds = clampf((clock_minutes - day_start) / span, 0.0, 1.0) * day_length
	minutes = _clock_at(day_seconds)
	_warned = seconds_left() <= warning_seconds
	Events.time_changed.emit(day, minutes)


func _clock_at(seconds: float) -> int:
	var t := clampf(seconds / day_length, 0.0, 1.0)
	var raw := day_start + int(t * (day_end - day_start))
	return raw - posmod(raw - day_start, clock_step)


func _reset_day_clock() -> void:
	day_seconds = 0.0
	minutes = day_start
	_warned = false


# ---------- 돈

func add_money(amount: int) -> void:
	money += amount
	Events.money_changed.emit(money)


func try_spend(amount: int) -> bool:
	if amount > money:
		return false
	money -= amount
	Events.money_changed.emit(money)
	return true


# ---------- 날짜

## 집에서 잠을 자서 하루를 끝낸다 (기존 호출 호환용 이름)
func sleep() -> void:
	request_day_end("sleep")


## 하루를 끝낸다. 실제 처리 순서는 DayCycle (scripts/time/day_cycle.gd) 한 곳에 있다.
## reason: "time_up" 15분 경과 / "sleep" 집에서 잠
func request_day_end(reason: String) -> void:
	if Events.day_end_requested.get_connections().is_empty():
		# 월드가 없을 때(단독 실행)만: 날짜만 넘긴다
		advance_date()
		Events.day_started.emit(day)
		Events.time_changed.emit(day, minutes)
		return
	Events.day_end_requested.emit(reason)


## 날짜 +1, 시계는 다음 날 07:00 (DayCycle 의 advance_date 단계에서 부른다)
func advance_date() -> void:
	day += 1
	_reset_day_clock()


static func format_clock(total_minutes: int) -> String:
	var h := int(total_minutes / 60.0) % 24
	var m := total_minutes % 60
	var period := "오전" if h < 12 else "오후"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%s %d:%02d" % [period, h12, m]


# ---------- 핫바

func select_slot(index: int) -> void:
	selected_slot = posmod(index, Inventory.HOTBAR_SIZE)
	Events.hotbar_selection_changed.emit(selected_slot)


func selected_item() -> ItemDef:
	return inventory.item_at(selected_slot)


# ---------- 입력

## 키 설정을 코드로 등록한다. (project.godot 을 직접 고치지 않아도 되게)
func _setup_input() -> void:
	_bind("move_up", [KEY_W, KEY_UP])
	_bind("move_down", [KEY_S, KEY_DOWN])
	_bind("move_left", [KEY_A, KEY_LEFT])
	_bind("move_right", [KEY_D, KEY_RIGHT])
	_bind("use_tool", [KEY_SPACE, KEY_J], [MOUSE_BUTTON_LEFT])
	_bind("interact", [KEY_E, KEY_K], [MOUSE_BUTTON_RIGHT])
	_bind("toggle_inventory", [KEY_I, KEY_TAB])
	_bind("build_menu", [KEY_B])
	_bind("rotate", [KEY_R])
	_bind("cancel", [KEY_ESCAPE])


func _bind(action: StringName, keys: Array, mouse_buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key: Key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	for button: MouseButton in mouse_buttons:
		var mev := InputEventMouseButton.new()
		mev.button_index = button
		InputMap.action_add_event(action, mev)
