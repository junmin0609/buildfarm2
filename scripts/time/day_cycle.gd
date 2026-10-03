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
## 당일 판매 정산: 출하함 판매(§83) + 오늘 장부 → report.sales (판매 수익 요약 §99)
const SETTLE_SALES := "settle_sales"
## 작물 성장·밭 마르기 (§15), 작은 자원 재생 (§103)
const FARM_DAILY := "farm_daily"
## 날짜 +1, 시계 07:00
const ADVANCE_DATE := "advance_date"
## 계절 변경 판정 (§30, §34, §12): 날짜가 새 계절로 넘어가면 작물 시듦·빈 밭 되돌림 → report.season
const SEASON := "season"
## 오늘 날씨 정하기, 비 오면 바깥 밭 적시기 (§32, §100) → report.weather
const WEATHER := "weather"
## 야간 5시간 생산 (§97 — 아직 없음)
const NIGHT_PRODUCTION := "night_production"
## 상점 일일 특가 (§101 — 아직 없음)
const SHOP_REFRESH := "shop_refresh"
## 집에서 07:00 시작 (지금은 집 앞 '@' 칸, 집 내부 맵이 생기면 침대), 시설 아침 동작
const WAKE_UP := "wake_up"
## 자동 저장 (§102 — 아직 없음). 날짜·07:00·집 시작 위치가 모두 반영된 뒤 맨 마지막에 저장한다.
const SAVE := "save"

## 하루 마감 순서. 순서를 바꿀 때는 여기만 고친다.
## 확정 규칙: 하루 종료 처리 → 다음 날 날짜·상태 반영 → 07:00 → 집 시작 위치 → 자동 저장
const PHASES: Array[String] = [
	END_ACTIVITIES,
	SETTLE_SALES,
	FARM_DAILY,
	ADVANCE_DATE,
	SEASON,
	WEATHER,
	NIGHT_PRODUCTION,
	SHOP_REFRESH,
	WAKE_UP,
	SAVE,
]

var world: FarmWorld
## 마지막 하루 마감 결과 (테스트·요약용)
var last_report := {}

## 날씨 뽑기용
var rng := RandomNumberGenerator.new()

var _steps := {}   # 단계 -> Array[Callable]
var _running := false


func _ready() -> void:
	rng.randomize()
	for phase in PHASES:
		_steps[phase] = []
	Events.day_end_requested.connect(end_day)
	# 지금 있는 시스템의 하루 처리 (새 시스템은 각자 add_step 으로 붙인다)
	add_step(SETTLE_SALES, _settle_sales)
	add_step(SEASON, _change_season)
	add_step(WEATHER, _decide_weather)
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


## 출하함을 팔고, 오늘 번 돈(광장 즉시 판매 포함)을 report.sales 로 모은다.
## report.sales = {"by_channel": {채널: G}, "total": G}, report.shipping = 출하함 정산 내역
## 하늘시장 같은 판매 수단은 이 단계에 add_step 으로 붙이고 GameState.record_sale 로 장부에 적으면 요약에 같이 나온다.
func _settle_sales(report: Dictionary) -> void:
	if world.shipping_bin:
		report["shipping"] = world.shipping_bin.settle()
	var by_channel := GameState.take_today_sales()
	var total := 0
	for amount: Variant in by_channel.values():
		total += int(amount)
	report["sales"] = {"by_channel": by_channel, "total": total}


## 날짜가 새 계절로 넘어갔으면 농사에 계절 변화를 적용한다.
## report.season = {"from", "to", "withered", "reverted"} (계절이 그대로면 없음)
func _change_season(report: Dictionary) -> void:
	var before := Calendar.season_of(report.from_day)
	var now := Calendar.season_of(GameState.day)
	if before == now:
		return
	var result := world.farm.change_season(now)
	report["season"] = {"from": before, "to": now, "withered": result.withered, "reverted": result.reverted}
	Events.season_changed.emit(now)


## 새 날의 날씨를 정한다 (하루 동안 바뀌지 않음, 예보 없음). 비면 바깥 밭이 07:00부터 젖어 있다.
## report.weather = {"id": 날씨, "watered": 적신 칸 수}
func _decide_weather(report: Dictionary) -> void:
	var weather := Weather.roll(GameState.day, rng)
	GameState.set_weather(weather)
	var watered := world.farm.water_outdoor() if Weather.waters_soil(weather) else 0
	report["weather"] = {"id": weather, "watered": watered}


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
