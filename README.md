# BuildFarm

Godot 4.7로 만든 2D 픽셀 농장 게임의 기본 버전입니다. 16px 도트 그래픽을 4배로 확대해 보여줍니다.

## 조작
| 키 | 동작 |
|---|---|
| WASD / 방향키 | 이동 |
| 마우스 왼쪽 / Space | 손에 든 도구·씨앗 쓰기 (다 자란 작물은 수확) |
| E / 마우스 오른쪽 | 상호작용 (집: 잠자기, 상점: 열기, 작물: 수확) |
| 1~9 / 마우스 휠 | 핫바 선택 |
| I / Tab | 가방 |
| B | 건설 창 (설치·옮기기·철거) |
| Esc | 메뉴 (계속하기·저장하기·불러오기·새 게임). 창이 열려 있으면 창 닫기 |
| 도끼·곡괭이로 클릭 | 장애물 치우기 (개간) |
| Esc | 창 닫기 |

목표 칸은 마우스가 플레이어 주변 2칸 안에 있으면 그 칸, 아니면 바라보는 방향 바로 앞 칸입니다 (`data/player.json`의 `reach_tiles`).
작물 위에 마우스를 올리면 커서 옆에 정보(자란 날·오늘 물·수확까지 남은 날)가 뜹니다. 괭이·곡괭이로 자라는 작물을 치면 뽑힙니다(씨앗은 돌아오지 않음).

## 게임 규칙
- 괭이로 농장 땅을 갈고 → 씨앗을 심고 → 물을 주고 → 집에서 자면 다음 날 자랍니다.
- 물을 준 날만 하루씩 자랍니다. 매일 아침 물은 마릅니다.
- 물뿌리개는 물이 12번분 들어 있고(`items.json`의 `capacity`), 집 옆 **우물** 앞에서 [E]를 누르거나 물뿌리개로 우물을 클릭하면 최대 용량까지 찹니다. 개울·연못에서는 채워지지 않습니다.
- 하루는 실제 15분(시계 오전 7시 → 새벽 2시). 14분이 지나면 "1분 남았어요" 경고, 15분이 되면 하루가 끝나고 다음 날 오전 7시에 집 앞에서 시작(패널티 없음).
  상점·건설 창, 설치·옮기기·철거 중에는 시간이 멈추고, 가방 창에서는 흐릅니다(가방이 열린 동안은 움직일 수 없음).
- 씨앗 상점에서 씨앗을 사고, 광장 작물 판매처에서 바로 팝니다(기준가의 80%). 시작 돈은 500G.

## 하루 마감 (BUILD_FARM_PLAN §95~§102)
15분이 지나 강제로 끝나든(`time_up`) 집에서 자든(`sleep`) 똑같이 `GameState.request_day_end()` → `DayCycle.end_day()` 한 길로 갑니다.
처리 순서는 `scripts/time/day_cycle.gd`의 `PHASES` 한 곳에만 있습니다.

| 순서 | 단계 | 지금 하는 일 |
|---|---|---|
| 1 | `end_activities` | 열린 창(가방·상점·건설)과 건설 모드 닫기, 시간 정지·입력 잠금 풀기 |
| 2 | `settle_sales` | (출하함 정산 자리, 아직 없음) |
| 3 | `farm_daily` | 물 준 작물 성장·밭 마르기, 작은 장애물 재생 |
| 4 | `advance_date` | 날짜 +1, 시계 07:00 |
| 5~8 | `season` `weather` `night_production` `shop_refresh` | (계절·날씨·야간 생산·상점 특가 자리, 아직 없음) |
| 9 | `wake_up` | 집 앞(맵의 `@`)에서 아래를 보고 시작, 시설 아침 동작(`Placeable.on_day_started`) |
| 10 | `save` | (자동 저장 자리, 아직 없음) 날짜·07:00·집 시작 위치가 모두 반영된 뒤 맨 마지막 |

요약 화면(아직 없음)은 둘로 나눕니다: 하루를 끝낼 때 **판매 수익 요약**(오늘 번 돈, §99), 다음 날 아침 **야간 생산 요약**(밤새 생산된 결과, §98). 한 화면으로 합치지 않습니다.

끝나면 `Events.day_started(day)` → `Events.day_ended(report)`를 보냅니다.
새 시스템은 하루 끝 처리를 자기 파일에 흩지 말고 `world.day_cycle.add_step(DayCycle.NIGHT_PRODUCTION, func(report): ...)`처럼 단계에 등록합니다.
결과를 `report`에 적어 두면 아침 요약(§98, §99)에서 쓸 수 있습니다.

## 저장 / 불러오기 (BUILD_FARM_PLAN §102)
- 슬롯 1개: `user://save_slot_1.json` (이전 저장은 `.bak`으로 하나 남김, 임시 파일에 쓴 뒤 바꿔치기)
- **하루 전환 자동 저장**: 하루 마감의 맨 끝 단계(`save`). 날짜 → 07:00 → 집 앞 시작 위치가 반영된 상태로 저장
- **수동 저장**: Esc 메뉴 → 저장하기. 지금 위치·시각 그대로 저장하고, 불러오면 그 자리·그 시각에서 이어서 함
- 게임을 켜면 저장이 있으면 이어서 시작. 메뉴의 "새 게임"(한 번 더 눌러 확인)은 저장을 불러오지 않고 처음부터
- 저장하는 것: 돈·날짜·오늘 흐른 시간·가방(품질·물뿌리개 물 포함)·핫바 선택·해금 상태(`GameState.unlocks`),
  밭(갈림·수분·작물·성장·다시 열림), 장애물(남은 타격 포함), 시설(위치·회전), 플레이어 위치·방향
- 방어 처리: 파일이 없거나 손상됐거나 더 새 버전이면 불러오지 않고 지금 상태 유지(안내 문구). 섹션 하나만 손상되면 그 섹션만 건너뜀
- 새 시스템 추가: `world.save_manager.register("이름", to_data, load_data)` — `load_data(data: Variant) -> bool`은 모양이 틀리면 false를 돌려주고 멈추지 않아야 함.
  형식이 바뀌면 `SaveManager.VERSION`을 올리고 `_migrate()`에 변환을 추가
- 코드: `scripts/save/save_manager.gd`(`SaveManager`), 메뉴 `scripts/ui/system_menu.gd`

## 작물·품질·판매 (BUILD_FARM_PLAN §24, §36)
| 작물 | 성장 | 다시 열림 | 수확량 | 씨앗 | 브론즈 / 실버 / 골드 |
|---|---|---|---|---|---|
| 당근 | 3일 | - | 1 | 20G | 35 / 44 / 56G |
| 감자 | 5일 | - | 1~3 | 45G | 30 / 38 / 48G |
| 딸기 | 7일 | 3일마다 | 1~3 | 120G | 45 / 56 / 72G |

- 작물 수치는 `data/items.json` 씨앗 항목: `grow_days`, `regrow_days`(0 = 한 번 수확), `yield_min/max`, `seasons`(계절 시스템이 생기면 사용), `buy_price`. 작물 항목의 `sell_price`가 기준가(브론즈).
- **품질은 아이템을 나누지 않습니다.** `potato` 하나에 가방 칸마다 `quality`(`bronze`/`silver`/`gold`)가 붙고, 품질이 다르면 다른 칸에 쌓입니다. 도구·씨앗·재료는 품질 없음(`""`).
  가방 칸 형식: `{"id", "count", "quality"}` (+ 물뿌리개는 `"water"`). 창고·출하함도 같은 형식을 쓰면 됩니다.
  `Inventory.add/can_add/remove/count_of`에 품질을 넘길 수 있고, `count_of(id)`처럼 품질을 생략하면 모든 품질 합계입니다.
- 품질 배율·수확 확률(비료 없음 80/18/2)은 `data/quality.json`.
- 판매가 = 기준가 × 품질 배율 × 판매 방식 배율 (`Pricing.unit_price`). 판매 방식 배율은 `data/economy.json`:
  광장 즉시 판매 `plaza` 0.8, 농장 출하함 `shipping_bin` 1.0(출하함 시설은 아직 없음). 하늘시장은 날마다 바뀌는 가격을 `Pricing.price_from`에 넘겨 쓰면 됩니다.
- 수확: 마우스 클릭(무엇을 들고 있든). 가방에 자리가 없으면 작물은 밭에 남습니다. 딸기는 거둔 뒤에도 포기가 남아 3일마다 다시 열립니다.

## 폴더 구조
```
data/items.json          아이템 정의 (도구·씨앗·작물). 새 작물은 여기 추가
data/quality.json        품질 배율·수확 품질 확률
data/economy.json        판매 방식별 가격 배율 (광장 80%, 출하함 100%)
data/time.json           하루 길이(15분)·경고 시점(1분 전)·시계 범위
assets/art/              픽셀 아트 (tools/make_art.py 로 생성)
assets/fonts/            Neo둥근모 한글 도트 폰트 (SIL OFL 1.1, NeoDunggeunmo-LICENSE.txt)
tools/make_art.py        모든 그래픽을 코드로 찍어 내는 생성기
scenes/                  main / world / player / buildings / ui / tests
scripts/
  autoload/   Events(신호 모음), ItemDB(아이템 저장소), GameState(돈·날짜·시계·인벤토리·키 설정)
  time/       DayCycle(하루 마감 흐름)
  save/       SaveManager(저장·불러오기)
  core/       ItemDef, Inventory, Quality(품질), DataFile(JSON 읽기), Art(그림·폰트 모음)
  economy/    Pricing(판매 가격 계산)
  world/      MapLayout(글자 지도), TerrainTileSet(타일셋 생성), FarmWorld(맵 조립), Prop(나무·바위)
  farm/       SoilTile(밭 한 칸), FarmGrid(격자 농사), WateringCan(물뿌리개 물)
  player/     Player
  buildings/  Interactable(공통), House, ShopStall, Well(우물, 물 공급원)
  ui/         HUD, Hotbar, InventoryPanel, ShopPanel, ItemSlot
  tests/      smoke_test(자동 점검), screenshot(화면 캡처)
```

## 그래픽
모든 그림은 외부 에셋 없이 `tools/make_art.py`가 픽셀 단위로 그립니다 (Python만 있으면 됨).
스타일: 둥글고 따뜻한 톤. 외곽선은 검정 대신 갈색(`INK`), 모서리는 둥글게, 회색 대신 모래·크림색. 색은 파일 위쪽 `P` 팔레트에서 한 번에 바꿀 수 있습니다.
```
python tools/make_art.py
```
- `tiles.png` 지형(잔디 4종 + 따뜻한 풀밭 4종·꽃·흙·둥근 돌길 4종·상점 앞 돌바닥 2종·물 2프레임·밭·젖은 밭·울타리·선택 표시)
- `edges.png` 길·물·흙 가장자리를 잔디가 살짝 덮는 경계 타일 (이웃에 따라 자동 배치)
- `ui_icons.png` 해·달·동전·말풍선
- `details.png` 잔디 위 작은 장식(풀·꽃·클로버·조약돌·버섯), 맵에 드문드문 자동 배치
- `barrel/crate/flowerpot/sign.png` 상점 앞 소품, `shadow.png` 캐릭터 그림자
- `player.png` 16x24, 아래/위/옆 x 걷기 4프레임 (왼쪽은 좌우 반전)
- `crops.png` 작물별 5단계, `items.png` 아이콘, `tree/rock/house/shop.png`, `ui_*.png` (3배 확대된 UI 테두리)

나무·집·플레이어는 Y 정렬돼서 뒤로 지나가면 가려집니다. 시간에 따라 아침·노을·밤 빛깔이 바뀝니다 (`FarmWorld.DAYLIGHT`).

## 맵
64x44칸, 두 구역으로 나뉩니다. 처음 배치는 `tools/make_map.py`가 도형(곡선 길, 개울, 연못, 들쭉날쭉한 숲)으로 그려
`MapLayout.ROWS` 글자 지도로 저장합니다. 그 뒤로는 글자 지도를 직접 고쳐도 됩니다 (스크립트를 다시 돌리면 덮어씀).

| 구역 | 역할 | 구성 |
|---|---|---|
| 개인 농장 (서쪽, 시작 지점) | 생산·농사·건설·자동화·꾸미기 | 집, 우물(`W`, 집 오른쪽), 집 앞 흙밭(`d`), 넓은 경작지(`g`, 잔디처럼 보이지만 괭이로 갈 수 있음), 작은 연못. 울타리 없음, 장식 최소 |
| 메인 광장 (동쪽) | 거래·NPC·상점·시설 | 분수 중심 돌광장, 씨앗 상점(`M`), 작물 판매처(`S`), 퀘스트 게시판, 벤치·가로등, 새 시설 터(`x`) 3곳 |
| 경계 | | 넓은 개울과 양쪽 숲띠가 두 구역을 갈라놓음. 숲 사이 오솔길 + 나무다리 한 곳으로만 오감. 바깥은 숲 |
| 확장 출구 | 새 지역 | 광장 북쪽·동쪽 길 끝 간판 |

- 새 시설: `Interactable`을 상속한 씬을 만들어 `MapLayout.BUILDINGS`에 글자로 등록하고, 광장의 `x` 터에 글자를 놓으면 됩니다.
- 상점은 `ShopStall` 하나로 모드만 바꿔 씁니다 (`shop_mode`: `buy` 씨앗, `sell` 판매, `all` 둘 다).
- 울타리 타일(`=`, `!`, `+`)은 남아 있어서 나중에 플레이어 건설 요소로 쓸 수 있습니다.
- 맵 밖으로는 보이지 않는 벽이 막습니다.

## 개간 시스템 (BUILD_FARM_PLAN §2, §46, §47, §103, §105)
시작 농장은 버려진 땅입니다. 집에서 가까운 순서로 바로 쓸 땅(약 30%) / 기본 도구로 치울 땅(약 50%) / 강화 도구가 필요한 땅(약 20%)으로 나뉩니다.

| 장애물 | 도구 | 등급 | 타격 | 자원 | 지나가기 |
|---|---|---|---|---|---|
| 잡초 | 괭이·도끼·곡괭이 | 1 | 1 | 식물 섬유 1 | 가능 |
| 나뭇가지 | 도끼 | 1 | 1 | 나무 1 | 가능 |
| 작은 돌 | 곡괭이 | 1 | 2 | 돌 1~2 | 막힘 |
| 그루터기 | 도끼 | 1 | 3 | 나무 2~3 | 막힘 |
| 큰 바위 | 곡괭이 | 2 | 6 | 돌 5~8 | 막힘 |
| 큰 그루터기 | 도끼 | 2 | 6 | 나무 5~8 | 막힘 |

- 도구 등급(`items.json`의 `tier`)이 모자라면 "더 좋은 곡괭이가 필요해요" 안내. 대장간 강화는 아직 없음 (등급 2 도구를 만들면 바로 동작).
- 가방에 자리가 없으면 장애물은 부서지지 않고 남습니다 (아이템이 사라지지 않음).
- 장애물이 있는 칸은 괭이질·건설 불가.
- 매일 아침 잡초·나뭇가지·작은 돌이 빈 농장 땅에 조금 다시 생깁니다. 밭·시설·장애물·플레이어 자리는 피하고, 큰 장애물은 다시 생기지 않습니다.
- 모든 수치(분포 비율·밀도·종류 가중치·타격 수·자원 개수·재생 확률)는 `data/obstacles.json`.
- 코드: `scripts/clearing/` (`ObstacleDef`, `ObstacleDB`, `Obstacle`, `ObstacleGrid`). 저장용 `to_data/load_data` 포함.

## 건설 시스템
농장 땅(`MapLayout.BUILDABLE`) 위에 시설을 격자 단위로 놓습니다.

- **B** → 건설 창에서 시설 고르기 → 초록(가능)/빨강(불가) 미리보기 → 클릭 설치, 우클릭·Esc로 끝내기
- 건설 모드인 동안 농장 땅에 격자가 보이고, 시설·장애물·작물이 있는 칸은 어둡게 표시됩니다 (`BuildGridOverlay`).
- **R** → 시계 방향 90° 회전(설치·옮기기 중). 직사각형은 가로·세로가 바뀝니다(3x4 → 4x3). 정사각형 장식은 돌리지 않습니다.
- 같은 창의 **옮기기**(시설 클릭 → 새 자리 클릭, 무료) / **철거하기**(전액 환불)
- 설치 불가: 농장 땅이 아닌 곳, 다른 시설, 장애물(잡초·돌·나뭇가지·그루터기 등, 자동으로 치우지 않음), 작물이 자라는 밭, 플레이어가 서 있는 자리. 시설이 있는 칸은 괭이질도 안 됩니다.
- 갈아 둔 빈 밭 위에는 지을 수 있고, 지으면 그 칸은 보통 땅이 됩니다(§53). 철거해도 보통 땅으로 남습니다.
- 설치·옮기기·철거 모드인 동안은 시간이 멈춥니다.
- 마우스를 움직이면 마우스 칸, 키보드로 걸으면 플레이어 앞 칸 기준으로 놓입니다.

| 파일 | 역할 |
|---|---|
| `data/placeables.json` | 시설 정의 (이름·크기·그림·가격·통과 여부·전용 스크립트) |
| `scripts/build/placeable_def.gd`, `placeable_db.gd` | 정의와 저장소 |
| `scripts/build/placeable.gd` | 설치된 시설의 공통 부모. `turns`(회전 0~3), `facing()`, `rotate_dir()`(포트 방향용). 훅: `on_placed` / `on_removed` / `on_moved` / `on_day_started` |
| `scripts/build/build_grid_overlay.gd` | 건설 모드 격자 (밭 위·나무 아래에 그림) |
| `scripts/build/build_grid.gd` | 칸 점유 관리, `check`·`place`·`move`·`remove`, 저장용 `to_data/load_data` |
| `scripts/build/build_mode.gd` | 미리보기와 입력, 돈 계산 |
| `scripts/ui/build_panel.gd` | 건설 창 (JSON 에서 목록 자동 생성) |

**새 시설 추가**
1. 그림을 만든다 (`make_art.py`의 `make_placeables`). 그림 아래쪽 `size` 칸이 바닥이고 그 위는 솟는 부분.
2. `data/placeables.json`에 항목 추가 → 건설 창·설치·이동·철거가 바로 동작.
   회전 관련: `"directional": true`(방향 있는 시설, 미리보기에 화살표), `"rotatable"`(생략하면 방향이 있거나 직사각형일 때 회전 가능),
   `"rotated_textures": [아래, 왼쪽, 위, 오른쪽]`(방향별 그림, 없으면 `texture`를 그대로 씀). 저장 데이터에는 `turns`가 들어갑니다.
3. 동작이 필요하면 `Placeable`을 상속한 스크립트를 만들어 `"script"`에 적는다. 예) 자동 물주기:
```gdscript
extends Placeable
func on_day_started(world: FarmWorld) -> void:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			world.farm.water(cell + Vector2i(dx, dy))
```
울타리처럼 지나갈 수 없는 1x1 시설, 장식 깔개처럼 `"solid": false` 인 시설도 같은 방식입니다.

## 확장 방법
- **새 작물**: `make_art.py`의 `CROPS`·아이콘 순서에 그림을 추가하고, `data/items.json`에 씨앗(`kind: seed`, `grows`, `grow_days`, `regrow_days`, `yield_min/max`, `seasons`, `buy_price`, `icon`, `crop_row`)과 작물(`kind: crop`, `sell_price`, `icon`)을 넣으면 상점·성장·품질·판매에 자동 반영됩니다. 작물이 아닌데 품질이 필요하면 `"has_quality": true`.
- **새 도구**: items.json에 `kind: tool`, `tool: "이름"`을 추가하고 `FarmGrid.use_item()`에 처리 한 줄을 추가합니다.
- **맵 확장·꾸미기**: `MapLayout.ROWS`의 글자를 바꾸거나 늘립니다. 새 소품은 `Prop` 씬을 만들어 `MapLayout.PROPS`에, 새 건물은 `Interactable`을 상속한 스크립트 + 씬을 만들어 `MapLayout.BUILDINGS`에 글자로 등록합니다.
- **자동화(스프링클러 등)**: `Events.day_started`를 받아 `FarmGrid.water()` / `harvest()`를 호출하는 노드를 만들면 됩니다. `harvest()`는 `{"id", "count", "quality"}`를 돌려줍니다. 받을 곳이 찰 수 있으면 `roll_harvest()`로 먼저 확인하고 `finish_harvest()`로 확정하세요.
- **저장/불러오기**: `GameState`의 돈·날짜, `Inventory.to_data()/load_data()`, `FarmGrid.to_data()/load_data()`가 이미 준비돼 있어 JSON으로 묶기만 하면 됩니다.

## 자동 점검
```
Godot --headless --path . res://scenes/tests/smoke_test.tscn
```
땅 갈기 → 심기 → 물 주기 → 성장 → 수확 → 판매·구매 → 잠자기 → 상점 창 → 충돌, 건설(설치·불가 판정·밭 위 건설·충돌·이동·철거·환불·시간 정지·격자·회전·불러오기), 개간(분포·도구·등급·자원·가방 가득·재생), 작물 데이터·품질 스택·판매 가격·다시 열리는 작물·수확량·물뿌리개, 시간(15분·경고·멈춤 규칙), 하루 마감(자동 종료·집에서 잠·집 앞 07:00 시작·창 정리·순서·단계 등록·저장 자리), 우물(위치·[E] 충전·클릭 충전·여러 물뿌리개·물가 충전 없음), 저장/불러오기(자동·수동·재개·손상 파일·일부 손상·버전·이어하기·새 게임)까지 210개 항목을 확인합니다.
점검은 진짜 저장 파일을 건드리지 않도록 `user://smoke_test_save.json`을 쓰고 끝나면 지웁니다.
새 `class_name` 스크립트를 추가한 뒤에는 한 번 `Godot --headless --path . --import`로 클래스 목록을 갱신해야 점검이 돌아갑니다. (맵 좌표는 맵에서 찾아 쓰므로 맵을 바꿔도 그대로 동작)

## 물 공급원 (우물 → 펌프 → 물탱크 → 자동 관개, §14)
물뿌리개는 `WateringCan.WATER_SOURCES`(`"water_sources"`) 그룹의 노드에서만 물을 채웁니다. 공급원은 세 함수만 있으면 됩니다.
- `covers_cell(cell) -> bool` 물뿌리개로 이 칸을 클릭하면 채우는가
- `provide_water(amount) -> int` 달라는 만큼 주고 실제로 준 양을 돌려줌 (우물은 무한, 물탱크는 남은 양만큼)
- `water_source_name() -> String` 안내 문구용 이름

지금은 `scripts/buildings/well.gd`(`Well`) 하나입니다. 펌프·물탱크를 설치 시설로 만들 때 `Placeable`을 상속한 스크립트에 이 세 함수를 넣고 그룹에 넣으면 물뿌리개가 그대로 씁니다.
