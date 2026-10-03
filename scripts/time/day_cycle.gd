class_name DayCycle
extends Node
## 하루 마감 흐름 (BUILD_FARM_PLAN §95~§102). 하루를 끝내는 길은 이 노드 하나뿐이다.
##   - 15분이 다 지나 강제로 끝날 때: GameState.advance_time → request_day_end("time_up")
##   - 집에서 잠잘 때:               House → GameState.sleep() → request_day_end("sleep")
## 둘 다 Events.day_end_requested 로 여기에 와서 PHASES 순서를 그대로 탄다. 패널티는 없다 (§96).
##
## 새 시스템은 하루 끝 처리를 자기 파일 여기저기에 넣지 말고, 알맞은 단계에 함수 하나를 등록한다.
##   world.day_cycle.add_step(DayCycle.NIGHT_PRODUCTION, my_func)    # func my_func(report: Dictionary)
## report 에 결과를 적어 두면 (예: report.sales, report.night_production) 아침 요약(§98, §99)에 쓸 수 있다.
## 하루가 다 넘어가면 Events.day_ended(report) 를 보낸다.

## 열린 창·건설 모드 닫기, 시간 정지·입력 잠금 풀기
const END_ACTIVITIES := "end_activities"
## 당일 판매 정산 (출하함 §83 — 아직 없음)
const SETTLE_SALES := "settle_sales"
## 작물 성장·밭 마르기 (§15), 작은 자원 재생 (§103)
const FARM_DAILY := "farm_daily"
## 날짜 +1, 시계 07:00
const ADVANCE_DATE := "advance_date"
## 계절 변경 판정 (§30, §34 — 아직 없음)
const SEASON := "season"
## 오늘 날씨 정하기·비 오면 밭 젖히기 (§32, §100 — 아직 없음)
const WEATHER := "weather"
## 야간 5시간 생산 (§97 — 아직 없음)
const NIGHT_PRODUCTION := "night_production"
## 상점 일일 특가 (§101 — 아직 없음)
const SHOP_REFRESH := "shop_refresh"
## 자동 저장 (§102 — 아직 없음)
const SAVE := "save"
## 집에서 07:00 시작, 시설 아침 동작, Events.day_started
const WAKE_UP := "wake_up"

## 하루 마감 순서. 순서를 바꿀 때는 여기만 고친다.
const PHASES: Array[String] = [
	END_ACTIVITIES,
	SETTLE_SALES,
	FARM_DAILY,
	ADVANCE_DATE,
	SEASON,
	WEATHER,
	NIGHT_PRODUCTION,
	SHOP_REFRESH,
	SAVE,
	WAKE_UP,
]

var world: FarmWorld
## 마지막 하루 마감 결과 (테스트·요약용)
var last_report := {}

var _steps := {}   # 단계 -> Array[Callable]
var _running := false


func _ready() -> void:
	for phase in PHASES:
		_steps[phase] = []
	Events.day_end_requested.connect(end_day)
	# 지금 있는 시스템의 하루 처리 (새 시스템은 각자 add_step 으로 붙인다)
	add_step(FARM_DAILY, func(_r: Dictionary) -> void: world.farm.process_day())
	add_step(FARM_DAILY, func(_r: Dictionary) -> void: world.obstacles.process_day())
	add_step(WAKE_UP, func(_r: Dictionary) -> void: world.build.start_day())


func add_step(phase: String, step: Callable) -> void:
	assert(_steps.has(phase), "모르는 하루 마감 단계: %s" % phase)
	_steps[phase].append(step)


func remove_step(phase: String, step: Callable) -> void:
	_steps.get(phase, []).erase(step)


func is_running() -> bool:
	return _running


## 하루를 끝내고 다음 날 아침 07:00 집에서 시작한다. reason: "time_up" / "sleep"
func end_day(reason: String) -> Dictionary:
	if _running:
		return last_report  # 마감 도중 다시 불려도 한 번만 처리
	_running = true
	var report := {"reason": reason, "from_day": GameState.day, "to_day": GameState.day, "phases": []}
	for phase in PHASES:
		_run_core(phase, report)
		for step: Callable in _steps[phase]:
			step.call(report)
		report.phases.append(phase)
	report.to_day = GameState.day
	last_report = report
	_running = false
	Events.day_started.emit(GameState.day)
	Events.time_changed.emit(GameState.day, GameState.minutes)
	Events.day_ended.emit(report)
	return report


## 이 노드가 직접 하는 단계
func _run_core(phase: String, report: Dictionary) -> void:
	match phase:
		END_ACTIVITIES:
			Events.day_ending.emit(report.reason)  # HUD 가 창을 닫는다
			world.build_mode.stop()
			GameState.clear_pauses_and_locks()
		ADVANCE_DATE:
			GameState.advance_date()
		WAKE_UP:
			world.player.wake_at(world.home_position)
