extends Node
## 게임 전체에서 쓰는 신호 모음.
## 시스템끼리 서로를 직접 찾지 않고 이 신호로 소통하면, 기능을 붙이고 떼기 쉬워진다.

signal money_changed(amount: int)
signal time_changed(day: int, minutes: int)
## 게임 시계가 흐름 (흐른 게임 시각, 분 단위 소수). 멈춘 동안은 오지 않는다. 가공기처럼 시계 기준으로 일하는 시설이 쓴다
signal time_advanced(game_minutes: float)
## 새 날 아침 07:00, 플레이어가 집에서 깨어난 뒤 (DayCycle 이 보낸다)
signal day_started(day: int)
## 하루를 끝내 달라는 요청. reason: "time_up"(15분 경과) / "sleep"(집에서 잠) → DayCycle.end_day
signal day_end_requested(reason: String)
## 하루 마감이 막 시작됨: 열린 창·모드를 닫을 때
signal day_ending(reason: String)
## 하루 마감이 다 끝남. report: DayCycle.end_day 의 결과 (판매·야간 생산 요약 등에 쓴다)
signal day_ended(report: Dictionary)
## 오늘 날씨가 정해짐 ("sunny", "cloudy", "rain", "snow")
signal weather_changed(weather: String)
## 계절이 바뀜 (새 계절 id: "spring" ...). 하루 마감의 season 단계에서 보낸다.
signal season_changed(season: String)
## 하루가 끝나기 직전 (남은 실제 시간, 초). data/time.json 의 warning_seconds_left
signal day_ending_soon(seconds_left: float)
signal inventory_changed
signal hotbar_selection_changed(index: int)

## 대장간 창 열기 요청
signal blacksmith_requested
## 출하함 창 열기 요청 (bin: ShippingBin) / 출하함 내용이 바뀜
signal shipping_bin_requested(bin: Node)
signal shipping_bin_changed
## 퇴비통 창 열기 요청 (bin: CompostBin) / 퇴비통 내용이 바뀜
signal compost_bin_requested(bin: Node)
signal compost_bin_changed
## 창고 창 열기 요청 (warehouse: Warehouse) / 창고 내용·필터·단계가 바뀜
signal warehouse_requested(warehouse: Node)
signal warehouse_changed
## 가공기 창 열기 요청 (processor: Processor) / 가공기 상태가 바뀜
signal processor_requested(processor: Node)
signal processor_changed
## 발전기 창 열기 요청 (generator: Generator) / 발전기 상태가 바뀜
signal generator_requested(generator: Node)
signal generator_changed
## 지역 전기가 바뀌었을 수 있음 (시설 설치·철거·켜고 끄기). HUD 전력 표시가 다시 계산한다
signal power_changed

## 저장 (kind: "auto" 하루 전환 자동 저장 / "manual" 수동 저장)
signal game_saved(kind: String)
## 불러오기 직전 (열린 창·모드를 닫을 때) / 직후
signal game_loading
signal game_loaded
## 메뉴에서 보내는 요청 (SaveManager 가 받는다)
signal save_requested
signal load_requested
signal new_game_requested

## 마우스가 올라간 아이템 칸 (ItemSlot, 벗어나면 null) → 아이템 툴팁 §45
signal item_hover_changed(slot: Node)

## 마우스 아래 작물 정보 (FarmGrid.crop_info 형식, 빈 사전이면 숨김) §19
signal crop_hover_changed(info: Dictionary)

## 화면에 잠깐 띄울 안내 문구
signal toast(text: String)
## 플레이어 근처의 상호작용 안내 ("" 이면 숨김)
signal prompt_changed(text: String)

## mode: "buy" 씨앗 상점, "sell" 작물 판매처, "all" 둘 다
signal shop_requested(mode: String)

## 건설: what = "place"(def_id 설치) / "move" / "remove"
signal build_requested(what: String, def_id: String)
## 건설 모드 안내 문구 ("" 이면 건설 모드 끝)
signal build_hint_changed(text: String)
