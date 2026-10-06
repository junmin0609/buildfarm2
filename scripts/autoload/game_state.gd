extends Node
## 돈, 날짜·시간, 인벤토리, 핫바 선택 같은 플레이어 진행 상태.
##
## 시간 (BUILD_FARM_PLAN §94, §95, 수치는 data/time.json)
##   하루 = 실제로 시간이 흐른 day_length_seconds(15분). 남은 시간이 warning_seconds_left(1분)가 되면 경고.
##   시계(minutes)는 흐른 시간에서 계산해 보여 주기만 한다.
##   상점·출하함·건설 창·건설 모드(설치·이동·철거)·메뉴 동안은 멈춘다 (set_time_paused). 가방 창에서는 흐른다.

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
## 오늘의 특별 상품 id (data/shop_specials.json). 아침마다 바뀐다 (DayCycle 의 shop_refresh 단계).
var daily_special := ""
## 오늘 날씨 (data/weather.json 의 types). 아침에 정해지고 하루 동안 바뀌지 않는다.
var weather := "sunny"
## 오늘 번 돈 (판매 방식 -> G). 하루 마감 때 판매 수익 요약(§99)으로 보여 주고 비운다.
var today_sales := {}
## 해금 상태 (지역·레시피·상점 품목 등). id -> true. 아직 해금 시스템은 없지만 저장 구조는 미리 둔다.
var unlocks := {}

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
	unlocks.clear()
	today_sales.clear()
	set_weather(Weather.first_day())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	daily_special = DailySpecial.pick(day, rng)
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
	Events.time_advanced.emit(game_minutes_for(seconds))
	var shown := _clock_at(day_seconds)
	if shown != minutes:
		minutes = shown
		Events.time_changed.emit(day, minutes)
	if not _warned and seconds_left() <= warning_seconds:
		_warned = true
		Events.day_ending_soon.emit(seconds_left())
	if day_seconds >= day_length:
		request_day_end("time_up")


## 실제 시간 seconds 동안 흐르는 게임 시계 분 (기본: 15분에 1140분 → 1초에 약 1.27분)
func game_minutes_for(seconds: float) -> float:
	return seconds * (day_end - day_start) / day_length


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


func set_weather(new_weather: String) -> void:
	weather = new_weather
	Events.weather_changed.emit(weather)


## 판매로 번 돈을 오늘 장부에 적는다 (돈은 부른 쪽이 따로 더한다). channel: Pricing.PLAZA / SHIPPING_BIN ...
func record_sale(channel: String, amount: int) -> void:
	if amount > 0:
		today_sales[channel] = int(today_sales.get(channel, 0)) + amount


## 하루 마감 때: 오늘 장부를 꺼내고 비운다
func take_today_sales() -> Dictionary:
	var sales := today_sales.duplicate()
	today_sales.clear()
	return sales


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


# ---------- 저장용 (SaveManager 가 부른다)

func to_data() -> Dictionary:
	return {
		"money": money,
		"day": day,
		"day_seconds": day_seconds,
		"selected_slot": selected_slot,
		"inventory": inventory.to_data(),
		"unlocks": unlocks.duplicate(true),
		"today_sales": today_sales.duplicate(),
		"weather": weather,
		"daily_special": daily_special,
	}


## 받은 데이터가 통째로 틀리면 false (지금 상태 그대로). 항목 하나가 틀리면 그 항목만 기본값.
func load_data(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	money = maxi(0, int(data.get("money", START_MONEY)))
	day = maxi(1, int(data.get("day", 1)))
	day_seconds = clampf(float(data.get("day_seconds", 0.0)), 0.0, day_length - 0.01)
	minutes = _clock_at(day_seconds)
	_warned = seconds_left() <= warning_seconds
	var inv_data: Variant = data.get("inventory", [])
	inventory.load_data(inv_data if inv_data is Array else [])
	var unlock_data: Variant = data.get("unlocks", {})
	unlocks = unlock_data.duplicate(true) if unlock_data is Dictionary else {}
	today_sales.clear()
	var sales_data: Variant = data.get("today_sales", {})
	if sales_data is Dictionary:
		for channel: Variant in sales_data:
			if typeof(sales_data[channel]) in [TYPE_INT, TYPE_FLOAT]:
				record_sale(str(channel), int(sales_data[channel]))
	daily_special = str(data.get("daily_special", ""))
	if not DailySpecial.exists(daily_special):
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		daily_special = DailySpecial.pick(day, rng)
	var saved_weather := str(data.get("weather", ""))
	set_weather(saved_weather if Weather.name_of(saved_weather) != saved_weather else Weather.first_day())
	select_slot(int(data.get("selected_slot", 0)))
	Events.money_changed.emit(money)
	Events.time_changed.emit(day, minutes)
	return true


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
