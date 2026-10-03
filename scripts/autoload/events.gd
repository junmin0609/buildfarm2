extends Node
## 게임 전체에서 쓰는 신호 모음.
## 시스템끼리 서로를 직접 찾지 않고 이 신호로 소통하면, 기능을 붙이고 떼기 쉬워진다.

signal money_changed(amount: int)
signal time_changed(day: int, minutes: int)
signal day_started(day: int)
## 하루가 끝나기 직전 (남은 실제 시간, 초). data/time.json 의 warning_seconds_left
signal day_ending_soon(seconds_left: float)
signal inventory_changed
signal hotbar_selection_changed(index: int)

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
