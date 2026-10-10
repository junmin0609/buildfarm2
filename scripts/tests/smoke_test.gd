extends Node
## 자동 점검: 메인 씬을 띄워 핵심 플레이 흐름을 한 바퀴 돌려 본다.
## 실행: Godot --headless --path . res://scenes/tests/smoke_test.tscn

var _failures := 0
## 시작 직후(하루도 지나기 전) 집 근처 장애물 수. 날이 지나면 작은 장애물이 무작위로 다시 자라서 나중에 세면 안 된다.
var _near_home_at_start := -1


const TEST_SAVE := "user://smoke_test_save.json"
## 점검이 이 시간(실제 초) 안에 끝나지 않으면 중간에 멈춘 것으로 보고 FAIL로 끝낸다. 평소 약 50초.
const WATCHDOG_SEC := 300.0

var _errors := ErrorCounter.new()


## 점검 중 엔진이 낸 오류(스크립트 실행 오류·컴파일 오류·push_error)를 모은다.
## 점검 함수 안에서 실행 오류가 나면 그 함수의 남은 _check가 조용히 건너뛰어지므로, _failures만으로는 잡을 수 없다.
## 경고(push_warning)는 세지 않는다 — 손상된 저장 파일 점검이 일부러 낸다.
class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_lock.lock()
		errors.append("%s:%d %s" % [file, line, rationale if rationale else code])
		_lock.unlock()


func _ready() -> void:
	OS.add_logger(_errors)
	# 점검 도중 실행 오류로 _ready 자체가 멈추면 끝 줄에 닿지 못해 영원히 기다리게 된다 → 시간 제한
	get_tree().create_timer(WATCHDOG_SEC, true, false, true).timeout.connect(_on_watchdog)
	# 점검은 새 게임으로 시작하고, 플레이어의 진짜 저장 파일은 건드리지 않는다
	SaveManager.load_on_start = false
	SaveManager.slot_path = TEST_SAVE
	# 날씨는 무작위라 다른 점검이 흔들리지 않게 맑음으로 고정한다 (날씨 점검에서만 바꾼다)
	Weather.forced = "sunny"
	_remove_test_save()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame

	var world: FarmWorld = main.get_node("FarmWorld")
	var farm := world.farm
	var player := world.player
	var hud: HUD = main.get_node("HUD")
	var inv := GameState.inventory
	# 스토리 이전부터 있던 점검은 '모든 기술이 열린' 상태에서 돈다 (기존 저장과 같음). 시대 제한은 스토리 점검이 새 게임으로 따로 확인
	world.quests.legacy = true

	_check(farm.farmable_cells.size() >= 100, "밭 칸 (실제 %d)" % farm.farmable_cells.size())
	_check(world.buildings.size() == 8, "건물 8개 배치 (집·잡화점·우물·출하함·대장간·기계상점·레시피 상점·비행선 정류장)")
	_check(world.fences.get_used_cells().all(func(c: Vector2i) -> bool: return c.x >= 53) and not world.fences.get_used_cells().is_empty(), "농장에 울타리 없음 (울타리는 광장 길가에만)")
	# 광장 주민·동물은 자기 점검(_test_townsfolk) 전까지 제자리에 둔다 (다른 점검의 [E] 대상과 겹치지 않게)
	for t: Townsfolk in world.townsfolk:
		t.process_mode = Node.PROCESS_MODE_DISABLED
	_check(world.objects.get_children().filter(func(n: Node) -> bool: return n is Prop).size() > 100, "나무·바위 소품 배치")
	var home_cell := world.world_to_cell(world.cell_center(_find_char("@")))
	_near_home_at_start = world.obstacles.all().filter(func(ob: Obstacle) -> bool: return Vector2(ob.cell).distance_to(Vector2(home_cell)) < 6).size()

	# 밭 위쪽 칸에 서서 아래를 보고 작업
	var cell := _open_farm_cell(farm)
	player.global_position = world.cell_center(cell + Vector2i.UP)
	player.facing = Vector2i.DOWN
	_check(player.target_cell() == cell, "앞 칸을 목표로 삼음 (실제 %s)" % player.target_cell())
	var me := Vector2i(10, 10)
	_check(player.reach == 2, "손 닿는 거리 2칸 (player.json)")
	_check(player.pick_target(me, me + Vector2i(2, -2)) == me + Vector2i(2, -2) and player.pick_target(me, me + Vector2i(0, 2)) == me + Vector2i(0, 2), "마우스가 2칸 안이면 그 칸")
	_check(player.pick_target(me, me + Vector2i(3, 0)) == me + Vector2i.DOWN and player.pick_target(me, me) == me + Vector2i.DOWN, "2칸 밖이거나 내 칸이면 앞 칸")

	GameState.select_slot(2)
	player._use_selected()
	_check(not farm.tiles.has(cell) or not farm.tiles[cell].has_crop(), "갈지 않은 땅에는 못 심음")

	GameState.select_slot(0)
	player._use_selected()
	_check(farm.tiles.has(cell), "괭이로 땅 갈기")

	GameState.select_slot(2)
	player._use_selected()
	_check(farm.get_tile(cell).seed_id == "carrot_seed", "당근 씨앗 심기")
	_check(inv.count_of("carrot_seed") == 11, "씨앗 1개 줄어듦 (실제 %d)" % inv.count_of("carrot_seed"))

	GameState.sleep()
	_check(farm.get_tile(cell).days_grown == 0, "물 안 주면 안 자람")
	_check(player.global_position == world.home_position, "자고 나면 집 앞에서 깨어남")

	_check(WateringCan.water_left(inv, 1) == 12, "물뿌리개는 가득 찬 채로 시작 (12)")
	var carrot_days := ItemDB.get_item("carrot_seed").grow_days
	for d in carrot_days:
		# 매일 아침 집에서 깨어나므로 밭으로 다시 간다
		player.global_position = world.cell_center(cell + Vector2i.UP)
		player.facing = Vector2i.DOWN
		GameState.select_slot(1)
		player._use_selected()
		_check(farm.get_tile(cell).watered, "%d일째 물 주기" % (d + 1))
		GameState.sleep()
	_check(WateringCan.water_left(inv, 1) == 12 - carrot_days, "물 줄 때마다 1씩 줄어듦 (남은 물 %d)" % WateringCan.water_left(inv, 1))
	_check(farm.get_tile(cell).is_mature(), "%d일 물 주고 당근 다 자람" % carrot_days)
	_check(GameState.day == 2 + carrot_days, "%d일차 (실제 %d)" % [2 + carrot_days, GameState.day])

	player.global_position = world.cell_center(cell + Vector2i.UP)
	player.facing = Vector2i.DOWN
	GameState.select_slot(0)
	player._use_selected()
	_check(inv.count_of("carrot") >= ItemDB.get_item("carrot_seed").yield_min and inv.count_of("carrot") <= ItemDB.get_item("carrot_seed").yield_max, "당근 %d개 수확" % inv.count_of("carrot"))
	_check(not farm.get_tile(cell).has_crop(), "수확 후 빈 밭")
	var carrot_q := ""
	for st in inv.stacks():
		if st.id == "carrot":
			carrot_q = st.quality
	_check(carrot_q in Quality.ids(), "수확한 당근에 품질이 붙음 (%s)" % carrot_q)

	var money := GameState.money
	var carrot_price := Pricing.unit_price(ItemDB.get_item("carrot"), carrot_q, Pricing.PLAZA)
	hud._shop._sell("carrot", 1, carrot_q)
	_check(GameState.money == money + carrot_price, "광장에서 당근 판매 +%d G (실제 %d)" % [carrot_price, GameState.money - money])
	var potato_seed_price := ItemDB.get_item("potato_seed").buy_price
	hud._shop._buy("potato_seed", 2)
	_check(GameState.money == money + carrot_price - potato_seed_price * 2 and inv.count_of("potato_seed") == 2, "감자 씨앗 2개 구매 (%dG × 2)" % potato_seed_price)
	hud._shop._buy("strawberry_seed", 99)
	_check(inv.count_of("strawberry_seed") == 0, "돈 부족하면 못 삼")

	# 집 앞 상호작용
	var house: Interactable = world.buildings.filter(func(b: Interactable) -> bool: return b is House)[0]
	player.global_position = house.interact_point()
	_check(player._nearest_interactable() == house, "집 앞에서 잠자기 안내")
	house.interact(player)
	_check(GameState.day == 3 + carrot_days, "집에서 자면 다음 날")

	# 상점 창 열기/닫기
	Events.shop_requested.emit("buy")
	_check(hud._shop.visible and get_tree().paused, "상점 열면 일시정지")
	_check(hud._shop._buy_col.visible and not hud._shop._sell_list.get_parent().visible, "씨앗 상점은 사기만")
	hud._close_panels()
	Events.shop_requested.emit("sell")
	_check(hud._shop._sell_list.get_parent().visible and not hud._shop._buy_col.visible, "판매처는 팔기만")
	var stores := world.buildings.filter(func(b: Interactable) -> bool: return b is ShopBuilding)
	_check(stores.size() == 2 and stores.any(func(b: ShopBuilding) -> bool: return b.room_id == "store") and stores.any(func(b: ShopBuilding) -> bool: return b.room_id == "machine") and not world.buildings.any(func(b: Interactable) -> bool: return b is ShopStall), "광장에 잡화점·기계상점 (작물 판매처는 잡화점으로 합침)")
	hud._close_panels()
	_check(not get_tree().paused, "닫으면 재개")

	# 걷기: 물로는 못 들어감
	var shore_cell := _shore_cell()
	player.global_position = world.cell_center(shore_cell)
	for i in 40:
		player.velocity = Vector2(0, 240)
		player.move_and_slide()
	_check(MapLayout.char_at(world.world_to_cell(player.global_position)) != "~", "물에 막힘")

	# ---------- 건설
	await _test_build(world, hud)
	await _test_build_grid_and_rotation(world)

	# ---------- 개간
	await _test_clearing(world)

	# ---------- 작물 데이터·품질·판매 가격·물뿌리개
	await _test_crops_and_quality(world, hud)

	# ---------- 시간 (15분 하루, 1분 전 경고, 멈춤 규칙)
	_test_time(world, hud)

	# ---------- 하루 마감 흐름 (§96)
	await _test_day_end(world, hud)

	# ---------- 저장 / 불러오기 (§102)
	await _test_save(world)

	# 맵 밖으로는 못 나감
	player.global_position = world.cell_center(Vector2i(1, 1))
	for i in 60:
		player.velocity = Vector2(-240, -240)
		player.move_and_slide()
	_check(player.global_position.x >= 0 and player.global_position.y >= 0, "맵 밖으로 못 나감")

	# ---------- 출하함 + 판매 수익 요약 (§83, §99)
	await _test_shipping(world, hud)

	# ---------- 비료 (§25~§27)
	await _test_fertilizer(world)

	# ---------- 날짜 / 계절 (§30, §34, §12)
	await _test_seasons(world, hud)

	# ---------- 날씨 / 비 (§32, §33, §16, §100)
	await _test_weather(world, hud)

	# ---------- 대장간 / 도구 강화 (§43, §47)
	await _test_blacksmith(world, hud)

	# ---------- 여름·가을 작물, 제철 씨앗만 심기·판매 (§36~§38)
	await _test_seasonal_crops(world, hud)

	# ---------- 가방 드래그 / 아이템 툴팁 (§44, §45)
	await _test_drag_and_tooltip(hud)

	# ---------- 일일 특별 상품 (§101)
	await _test_daily_special(world, hud)

	# ---------- 온실 + 겨울 작물 (§35, §40)
	await _test_greenhouse(world, hud)

	# ---------- 퇴비통 (§28)
	await _test_compost(world, hud)

	# ---------- 창고 + 필터 (§67, §68)
	await _test_warehouse(world, hud)

	# ---------- 수동 가공기 + 레시피 (§70~§74)
	await _test_processor(world, hud)

	# ---------- 연료 발전기 + 지역 전기 통 + 전기 가공기 (§75~§77, §97)
	await _test_power_and_electric(world, hud)

	# ---------- 컨베이어 + 입출력 포트 (§54~§61, §65)
	await _test_conveyor(world, hud)

	# ---------- 레시피 상점 (셰프, §71)
	await _test_recipe_shop(world, hud)

	# ---------- 스프링클러 + 자동 수확기 (§14, §66)
	await _test_farm_machines(world, hud)

	# ---------- 분배기 · 합류기 · 필터 분배기 (§62)
	await _test_routers(world, hud)

	# ---------- 하늘시장 + 비행선 정류장 + 하늘섬 (§84~§90)
	await _test_sky_market(world, hud)

	# ---------- 펌프 + 물탱크 + 스프링클러 물 (§14)
	await _test_water(world, hud)

	# ---------- 도구 딜레이 0.5초 (사용자 결정)
	await _test_tool_cooldown(world)

	# ---------- 가게 실내 + NPC 대화 (사용자 요청)
	await _test_interiors(world, hud)
	_test_plaza(world)
	await _test_fixtures(world)
	_test_tank_refill(world)
	_test_mid_processor(world)
	await _test_townsfolk(world, hud)
	_test_mine(world, hud)
	await _test_mine_exit_fade(world, hud)
	_test_furnace_tools(world)
	await _test_story(world)
	await _test_story_ui(world, hud)
	await _test_story_tech(world, hud)
	await _test_story_play(world, hud)
	await _test_story_support(world, hud)
	await _test_story_winter_mq20(world)
	await _test_story_stabilize(world, hud)

	# ---------- 게임을 켤 때 이어하기 / 새 게임
	await _test_continue_on_start(main)

	# ---------- 시작 화면 (이어하기 / 새 게임 / 설정)
	await _test_title()

	_remove_test_save()
	_finish()


## 엔진 오류를 실패에 더하고 결과를 찍은 뒤 끝낸다.
func _finish() -> void:
	OS.remove_logger(_errors)
	for e in _errors.errors:
		print("  FAIL 엔진 오류: " + e)
	_failures += _errors.errors.size()
	print("SMOKE TEST %s (%d 실패, 엔진 오류 %d)" % ["PASS" if _failures == 0 else "FAIL", _failures, _errors.errors.size()])
	get_tree().quit(1 if _failures else 0)


func _on_watchdog() -> void:
	print("  FAIL 점검이 %d초 안에 끝나지 않음 (중간에 멈춤)" % int(WATCHDOG_SEC))
	_failures += 1
	_finish()


func _test_build(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var bm := world.build_mode
	var shed := PlaceableDB.get_def("shed")
	var scarecrow := PlaceableDB.get_def("scarecrow")
	_check(shed != null and shed.size == Vector2i(2, 2) and scarecrow != null, "시설 정의 읽기")

	Events.build_requested.emit("place", "shed")
	_check(bm.is_active() and bm.place_def == shed and hud._build_hint.visible, "건설 모드 시작 + 안내")
	_check(GameState.is_time_paused(), "설치 모드 동안 시간 멈춤")

	var o := _free_origin(world, shed, Vector2i(-1, -1))
	GameState.add_money(1000)
	var money := GameState.money
	_check(bm.try_place(o), "창고 설치")
	_check(GameState.money == money - shed.price, "설치비 %d G" % shed.price)
	var obj := grid.object_at(o)
	_check(obj != null and grid.object_at(o + Vector2i(1, 1)) == obj, "2x2 칸 모두 차지")
	_check(not bm.try_place(o) and not grid.check(scarecrow, o + Vector2i(1, 0)).ok, "겹치는 자리 설치 불가")

	var road := _find_char("s")
	_check(not grid.check(scarecrow, road).ok, "길 위 설치 불가")
	_check(not grid.check(scarecrow, _find_char("~")).ok, "물 위 설치 불가")
	_check(not world.farm.till(o), "시설 자리는 괭이질 불가")

	var soil := _free_origin(world, scarecrow, o)
	world.farm.till(soil)
	_check(grid.check(scarecrow, soil).ok, "갈아 둔 밭 위 설치 가능")
	world.farm.plant(soil, ItemDB.get_item("carrot_seed"))
	_check(not grid.check(scarecrow, soil).ok, "작물이 자라는 밭 위 설치 불가")
	world.farm.get_tile(soil).seed_id = ""
	_check(not grid.check(scarecrow, world.world_to_cell(world.player.global_position)).ok, "서 있는 자리 설치 불가")

	# 창고는 못 지나간다: 아래에서 위로 걸어 올라가 본다
	var bottom_y := (o.y + 2) * Art.TILE
	world.player.global_position = Vector2(o.x * Art.TILE + Art.TILE, bottom_y + 10)
	for i in 30:
		world.player.velocity = Vector2(0, -240)
		world.player.move_and_slide()
	_check(world.player.global_position.y >= bottom_y, "설치한 시설은 충돌")
	world.player.global_position = world.cell_center(road)

	bm.start(BuildMode.Mode.MOVE)
	_check(GameState.is_time_paused(), "옮기기 모드 동안 시간 멈춤")
	_check(bm.pick(o + Vector2i(1, 0)), "옮길 시설 집기")
	var o2 := _free_origin(world, shed, o)
	_check(bm.try_drop(o2) and grid.object_at(o) == null and grid.object_at(o2) == obj, "다른 자리로 옮기기")

	bm.start(BuildMode.Mode.REMOVE)
	_check(GameState.is_time_paused(), "철거 모드 동안 시간 멈춤")
	money = GameState.money
	_check(bm.try_remove(o2) and grid.object_at(o2) == null, "철거")
	_check(GameState.money == money + shed.price, "철거하면 전액 환불")

	bm.start_place("scarecrow")
	var saved := GameState.money
	GameState.money = 0
	_check(not bm.try_place(_free_origin(world, scarecrow, o)), "돈이 부족하면 설치 불가")
	GameState.money = saved
	_check(bm.try_place(soil) and grid.objects().filter(func(x: Placeable) -> bool: return not x is Fixture).size() == 1, "갈아 둔 밭 위에 허수아비 설치")
	_check(not world.farm.tiles.has(soil), "시설 밑의 밭은 보통 땅이 됨")
	bm.stop()
	_check(not bm.is_active() and not hud._build_hint.visible, "건설 모드 끝")
	_check(not GameState.is_time_paused(), "건설 모드 끝나면 시간 다시 흐름")
	await get_tree().process_frame


func _test_build_grid_and_rotation(world: FarmWorld) -> void:
	var grid := world.build
	var bm := world.build_mode
	var shed := PlaceableDB.get_def("shed")
	var scarecrow := PlaceableDB.get_def("scarecrow")

	# 격자 (§49)
	bm.start_place("shed")
	var ov := bm.grid_overlay
	_check(ov != null and ov.visible, "건설 모드에서 격자 표시")
	_check(ov.get_index() == world.farm.get_index() + 1 and ov.get_index() < world.objects.get_index(), "격자는 밭 위·나무와 시설 아래에 그림")
	var all_cells := ov.grid_cells(Rect2i(Vector2i.ZERO, MapLayout.size()))
	_check(all_cells.size() == world.farm.farmable_cells.size() + grid.extra_buildable.size() and grid.extra_buildable.size() == 18 and all_cells.all(grid.is_buildable_ground), "격자는 농장 땅 + 집·출하함·우물 처음 자리에만 (%d칸)" % all_cells.size())
	var taken := all_cells.filter(grid.is_cell_taken)
	_check(not taken.is_empty() and taken.all(func(c: Vector2i) -> bool: return grid.is_occupied(c) or world.obstacles.is_blocked(c) or world.farm.get_tile(c) != null), "시설·장애물·작물 칸은 어둡게 표시 (%d칸)" % taken.size())
	_check(not shed.rotatable and not scarecrow.rotatable, "정사각형 시설은 회전 대상 아님")
	_check(not bm.rotate_preview() and bm.turns == 0, "정사각형은 R 을 눌러도 그대로")
	bm.stop()
	_check(not ov.visible, "건설 모드 끝나면 격자 숨김")

	# 직사각형 회전 (§54): 점검 전용 3x2 정의
	var wide := PlaceableDef.from_dict("test_wide", {"name": "점검용 3x2", "size": [3, 2], "texture": "res://assets/art/shed.png", "price": 0})
	_check(wide.rotatable and wide.size_for(1) == Vector2i(2, 3) and wide.size_for(2) == Vector2i(3, 2), "직사각형은 회전 가능 (3x2 → 2x3 → 3x2)")
	bm.place_def = wide
	bm.turns = 0
	bm.start(BuildMode.Mode.PLACE)
	_check(bm.rotate_preview() and bm.turns == 1, "R 로 시계 방향 90°")
	_check(GameState.is_time_paused(), "회전 중에도 시간 멈춤")
	var o := _free_origin_turned(world, wide, 1, null)
	_check(bm.try_place(o), "돌린 채로 설치")
	var obj := grid.object_at(o)
	_check(obj != null and obj.turns == 1 and obj.size() == Vector2i(2, 3), "설치된 시설이 방향을 기억 (2x3)")
	_check(grid.object_at(o + Vector2i(1, 2)) == obj and grid.object_at(o + Vector2i(2, 0)) != obj, "돌린 모양대로 칸을 차지")
	bm.stop()

	bm.start(BuildMode.Mode.MOVE)
	_check(bm.pick(o) and bm.turns == 1, "집으면 그 시설의 방향에서 시작")
	bm.rotate_preview()
	var o2 := _free_origin_turned(world, wide, 2, obj)
	_check(bm.try_drop(o2) and obj.turns == 2 and obj.size() == Vector2i(3, 2) and grid.object_at(o2 + Vector2i(2, 1)) == obj, "옮기면서 돌리기 (3x2)")
	var owned := grid._cells.values().filter(func(v: Placeable) -> bool: return v == obj)
	_check(owned.size() == 6 and obj.footprint().all(func(c: Vector2i) -> bool: return grid.object_at(c) == obj), "옮긴 뒤 칸 정보가 정확함")
	bm.stop()

	# 방향이 있는 시설: 화살표 방향, 그림 없는 정의도 멈추지 않음
	var arrow := PlaceableDef.from_dict("test_dir", {"name": "점검용 방향", "size": [1, 1], "directional": true, "price": 0})
	_check(arrow.rotatable and arrow.texture == null, "방향 있는 1x1 은 회전 가능")
	var dirs_ok := true
	for t in 4:
		dirs_ok = dirs_ok and Placeable.rotate_dir(Vector2i.DOWN, t) == Placeable.DIRS[t]
	_check(dirs_ok and Placeable.rotate_dir(Vector2i.RIGHT, 1) == Vector2i.DOWN, "포트 방향 회전 계산 (아래→왼쪽→위→오른쪽)")
	var dir_obj := grid.place(arrow, _free_origin_turned(world, arrow, 3, null), 3)
	await get_tree().process_frame
	_check(dir_obj != null and dir_obj.facing() == Vector2i.RIGHT, "그림 없는 시설도 설치됨, 오른쪽을 봄")
	grid.remove(obj)
	grid.remove(dir_obj)

	# 저장·불러오기: 플레이어가 시설 위에 서 있어도 사라지지 않음
	var placed := grid.place(shed, _free_origin_turned(world, shed, 0, null))
	var placed_cell := placed.cell
	world.player.global_position = world.cell_center(placed_cell)
	var data := grid.to_data()
	var failed := grid.load_data(data)
	_check(failed.is_empty() and grid.to_data() == data, "불러와도 시설·위치·방향 그대로 (%d개)" % data.size())
	_check(not grid._fits_space(shed, _find_char("s"), 0), "땅이 아닌 곳은 불러오기에서도 거부")
	grid.remove(grid.object_at(placed_cell))
	world.player.global_position = world.cell_center(_find_char("s"))
	await get_tree().process_frame


## def 를 turns 방향으로 놓을 수 있는 경작지 칸
func _free_origin_turned(world: FarmWorld, def: PlaceableDef, turns: int, ignore: Placeable) -> Vector2i:
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		if world.build.check(def, c, ignore, turns).ok:
			return c
	return cells[0]


func _test_clearing(world: FarmWorld) -> void:
	var obs := world.obstacles
	var inv := GameState.inventory
	var farm_n := world.farm.farmable_cells.size()
	var kinds := {}
	for ob: Obstacle in obs.all():
		kinds[ob.def.id] = kinds.get(ob.def.id, 0) + 1
	var big := int(kinds.get("big_rock", 0)) + int(kinds.get("big_stump", 0))
	print("    장애물 %d / 농장 %d칸  %s" % [obs.count(), farm_n, kinds])
	_check(obs.count() > farm_n * 0.4 and obs.count() < farm_n * 0.8, "시작 농장 장애물 분포 (약 %d%%)" % roundi(obs.count() * 100.0 / farm_n))
	_check(big > farm_n * 0.1 and big < farm_n * 0.3, "강화 도구가 필요한 땅 약 20%% (실제 %d%%)" % roundi(big * 100.0 / farm_n))
	_check(kinds.has("weed") and kinds.has("branch") and kinds.has("small_rock") and kinds.has("stump"), "작은 장애물 종류 모두 있음")
	_check(_near_home_at_start == 0, "집 근처는 바로 쓸 수 있는 땅 (시작 시점)")
	_check(inv.count_of("axe") == 1 and inv.count_of("pickaxe") == 1, "도끼·곡괭이 지급")

	var axe := ItemDB.get_item("axe")
	var pick := ItemDB.get_item("pickaxe")
	var hoe := ItemDB.get_item("hoe")
	var can := ItemDB.get_item("watering_can")
	var spot := _free_clear_cell(world)
	world.player.global_position = world.cell_center(_find_char("s"))

	# 잡초: 괭이로 한 번, 섬유
	obs.spawn(spot, "weed")
	_check(not world.farm.till(spot), "장애물 칸은 괭이질 안 됨")
	_check(not world.build.check(PlaceableDB.get_def("scarecrow"), spot).ok, "장애물 칸은 건설 안 됨")
	var fiber := inv.count_of("fiber")
	_check(obs.try_clear(spot, hoe) and not obs.is_blocked(spot) and inv.count_of("fiber") == fiber + 1, "잡초 → 괭이로 제거, 섬유 +1")
	await get_tree().process_frame
	_check(world.farm.till(spot), "치운 자리는 다시 괭이질 가능")
	world.farm.tiles.erase(spot)

	# 작은 돌: 도끼로는 안 되고 곡괭이로 두 번
	obs.spawn(spot, "small_rock")
	obs.try_clear(spot, axe)
	_check(obs.is_blocked(spot) and obs.obstacle_at(spot).hp == 2, "작은 돌은 도끼로 안 깨짐")
	obs.try_clear(spot, can)
	_check(obs.is_blocked(spot), "물뿌리개로도 안 깨짐")
	var stone := inv.count_of("stone")
	obs.try_clear(spot, pick)
	_check(obs.is_blocked(spot) and obs.obstacle_at(spot).hp == 1, "곡괭이 1번: 아직 남음")
	obs.try_clear(spot, pick)
	_check(not obs.is_blocked(spot) and inv.count_of("stone") > stone, "곡괭이 2번: 돌 획득")
	await get_tree().process_frame

	# 그루터기: 도끼로 세 번, 나무
	obs.spawn(spot, "stump")
	var wood := inv.count_of("wood")
	for i in 3:
		obs.try_clear(spot, axe)
	_check(not obs.is_blocked(spot) and inv.count_of("wood") >= wood + 2, "그루터기 → 도끼 3번, 나무 +2~3")
	await get_tree().process_frame

	# 큰 바위: 돌 곡괭이로도 깨지만 여러 번 (사용자 결정: 강화는 속도·범위만)
	obs.spawn(spot, "big_rock")
	for i in 5:
		obs.try_clear(spot, pick)
	_check(obs.is_blocked(spot) and obs.obstacle_at(spot).hp == 1, "큰 바위: 돌 곡괭이 5번엔 아직")
	obs.try_clear(spot, pick)
	_check(not obs.is_blocked(spot), "큰 바위: 돌 곡괭이 6번에 깸")
	await get_tree().process_frame

	# 가방이 가득 차면 깨지지 않고 남는다
	var saved := inv.to_data()
	for i in inv.size():
		if inv.get_slot(i) == null:
			inv.slots[i] = {"id": "carrot_seed", "count": 99}
	for i in inv.size():
		if inv.get_slot(i)["id"] == "fiber":
			inv.slots[i]["count"] = 99
	obs.spawn(spot, "weed")
	obs.try_clear(spot, hoe)
	_check(obs.is_blocked(spot), "가방이 가득 차면 장애물이 남음 (아이템 보존)")
	inv.load_data(saved)
	obs.try_clear(spot, hoe)
	_check(not obs.is_blocked(spot), "자리가 생기면 다시 치울 수 있음")
	await get_tree().process_frame

	# 다시 자라기: 밭·시설 위에는 안 생김
	var tilled := _free_clear_cell(world)
	world.farm.till(tilled)
	var before := obs.count()
	var old_rng := obs.rng
	obs.rng = RandomNumberGenerator.new()
	obs.rng.seed = 7
	var grown := 0
	for d in 20:
		grown += obs.regrow()
	obs.rng = old_rng
	_check(grown > 0 and obs.count() == before + grown, "작은 장애물이 다시 자람 (+%d)" % grown)
	var bad := 0
	for ob: Obstacle in obs.all():
		if world.farm.tiles.has(ob.cell) or world.build.is_occupied(ob.cell):
			bad += 1
	_check(bad == 0 and not obs.can_grow_at(tilled), "밭·시설 위에는 안 자람")


func _test_crops_and_quality(world: FarmWorld, hud: HUD) -> void:
	var inv := GameState.inventory
	var farm := world.farm
	var saved := inv.to_data()

	# 작물 데이터 (BUILD_FARM_PLAN §36)
	_check(ItemDB.get_item("turnip_seed") == null and ItemDB.get_item("turnip") == null, "순무 제거됨")
	var cs := ItemDB.get_item("carrot_seed")
	var ps := ItemDB.get_item("potato_seed")
	var ss := ItemDB.get_item("strawberry_seed")
	var crop_bad := []
	var econ_crops: Dictionary = _econ().get("crops", {})
	for id: String in econ_crops:
		var e: Dictionary = econ_crops[id]
		var sd := ItemDB.get_item(id + "_seed")
		if sd == null or [sd.buy_price, ItemDB.get_item(id).sell_price, sd.grow_days, sd.regrow_days, sd.yield_min, sd.yield_max] != [int(e.seed), int(e.sell), int(e.grow_days), int(e.regrow_days), int(e["yield"][0]), int(e["yield"][1])]:
			crop_bad.append(id)
	_check(econ_crops.size() == 17 and crop_bad.is_empty(), "작물 17종 = 경제 기준 v1.0 (씨앗·판매가·성장일·재수확·수확량) %s" % [crop_bad])
	# 양배추·양상추 (사용자 결정: cabbage 는 양배추 그대로, 양상추는 새 id lettuce)
	var lettuce := ItemDB.get_item("lettuce_seed")
	_check(ItemDB.get_item("cabbage").name == "양배추" and lettuce != null and lettuce.grows == "lettuce" and ItemDB.get_item("lettuce").name == "양상추" and lettuce.seasons == ["spring"] 		and RecipeDB.get_recipe("pickled_cabbage").inputs.has("cabbage") and not RecipeDB.get_recipe("pickled_cabbage").inputs.has("lettuce"), "양배추(cabbage)·양상추(lettuce) 별개 작물, 양배추 절임은 양배추")
	_check(not cs.regrows() and ss.regrows() and ss.regrow_days == int(econ_crops.strawberry.regrow_days), "당근은 한 번, 딸기는 다시 열림")

	# 품질 가격 = 기준가 × 품질 배율 (경제 기준 1.0 / 1.3 / 1.7) + 판매 방식 배율 (광장 80% · 출하함 100%, 사용자 결정)
	var mult: Dictionary = _econ().quality.multipliers
	_check(Quality.ids().all(func(q: String) -> bool: return is_equal_approx(Quality.multiplier(q), float(mult[q]))), "품질 배율 = 경제 기준 %s" % [mult])
	# 품질 가격은 배율을 곱한 뒤 소수점 버림 (사용자 결정): 감자 골드 28 × 1.7 = 47.6 → 47, 딱 떨어지는 값은 그대로 (30 × 1.3 = 39)
	var fake := ItemDef.from_dict("t", {"kind": "crop", "sell_price": 30})
	_check(Pricing.quality_price(ItemDB.get_item("potato"), "gold") == 47 and Pricing.price_from(30, fake, "silver") == 39 and Pricing.price_from(10, fake, "silver") == 13, "품질 가격 소수점 버림 (감자 골드 47, 30×1.3 = 39)")
	for id: String in ["carrot", "potato", "strawberry"]:
		var it := ItemDB.get_item(id)
		var want := Quality.ids().map(func(q: String) -> int: return floori(it.sell_price * float(mult[q]) + 0.0001))
		var prices := Quality.ids().map(func(q: String) -> int: return Pricing.quality_price(it, q))
		_check(prices == want, "%s 브론즈·실버·골드 %s (실제 %s)" % [it.name, want, prices])
	var carrot := ItemDB.get_item("carrot")
	_check(Pricing.unit_price(carrot, "bronze", Pricing.PLAZA) == roundi(Pricing.quality_price(carrot, "bronze") * 0.8) and Pricing.unit_price(carrot, "gold", Pricing.PLAZA) == roundi(Pricing.quality_price(carrot, "gold") * 0.8), "광장 즉시 판매 = 품질가의 80%")
	_check(Pricing.unit_price(carrot, "silver", Pricing.SHIPPING_BIN) == Pricing.quality_price(carrot, "silver"), "출하함 = 품질가의 100%")
	_check(Pricing.unit_price(ItemDB.get_item("hoe"), "", Pricing.PLAZA) == 0, "판매가 없는 아이템(도구)은 0")
	# 목재·돌·섬유 판매 (사용자 결정): 출하함 100% · 광장 80%
	var raw_ok := true
	for id: String in ["wood", "stone", "fiber"]:
		var it := ItemDB.get_item(id)
		raw_ok = raw_ok and it.sell_price == int(_econ().materials[id]) and Pricing.unit_price(it, "", Pricing.SHIPPING_BIN) == it.sell_price and Pricing.unit_price(it, "", Pricing.PLAZA) == roundi(it.sell_price * 0.8)
	_check(raw_ok, "목재 8 · 돌 10 · 섬유 5 G 판매 (광장 80%)")

	# 품질별 스택
	inv.load_data([])
	inv.add("potato", 2, "bronze")
	inv.add("potato", 3, "silver")
	inv.add("potato", 1, "gold")
	inv.add("potato", 1, "bronze")
	var potato_slots := inv.slots.filter(func(sl: Variant) -> bool: return sl != null and sl["id"] == "potato")
	_check(potato_slots.size() == 3, "같은 감자도 품질이 다르면 다른 칸 (%d칸)" % potato_slots.size())
	_check(inv.count_of("potato") == 7 and inv.count_of("potato", "bronze") == 3 and inv.count_of("potato", "silver") == 3, "품질별 개수 / 전체 개수")
	inv.add("carrot", 1)
	_check(inv.count_of("carrot", "bronze") == 1, "품질 없이 넣으면 기본(브론즈)")
	inv.add("wood", 2, "gold")
	_check(inv.count_of("wood", "") == 2, "재료는 품질 없음")
	_check(inv.remove("potato", 2, "silver") and inv.count_of("potato", "silver") == 1 and inv.count_of("potato", "bronze") == 3, "그 품질에서만 빼기")
	_check(not inv.remove("potato", 5, "gold") and inv.count_of("potato", "gold") == 1, "모자라면 빼지 않음")
	inv.load_data(JSON.parse_string(JSON.stringify(inv.to_data())))
	_check(inv.count_of("potato", "gold") == 1 and inv.count_of("potato", "silver") == 1 and inv.count_of("wood") == 2, "저장 후 불러와도 품질 유지")
	var money := GameState.money
	hud._shop._sell("potato", 1, "gold")
	_check(GameState.money == money + 38 and inv.count_of("potato", "gold") == 0, "광장에서 골드 감자 판매 +38G (48 × 80%%)")

	# 수확 품질 확률 (quality.json 의 비료 없음 표)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var counts := {"bronze": 0, "silver": 0, "gold": 0}
	for i in 2000:
		counts[Quality.roll(rng)] += 1
	_check(counts.bronze > counts.silver and counts.silver > counts.gold and counts.gold > 0, "수확 품질 확률 %s" % counts)

	# 딸기: 다시 열림
	inv.load_data(saved)
	var c := _free_clear_cell(world)
	farm.till(c)
	farm.plant(c, ss)
	for d in 7:
		farm.water(c)
		GameState.sleep()
	_check(farm.get_tile(c).is_mature(), "딸기 7일 만에 열림")
	var got := farm.harvest(c)
	_check(got.get("id") == "strawberry" and got.count >= 1 and got.count <= 3, "딸기 수확 %d개" % got.get("count", 0))
	_check(farm.get_tile(c).has_crop() and farm.get_tile(c).regrowing and not farm.get_tile(c).is_mature(), "수확 뒤에도 딸기 포기가 남음")
	for d in ss.regrow_days:
		farm.water(c)
		GameState.sleep()
	_check(farm.get_tile(c).is_mature(), "%d일 뒤 다시 열림" % ss.regrow_days)

	# 가방이 가득 차면 수확 실패, 작물은 남음
	var player := world.player
	player.global_position = world.cell_center(c + Vector2i.UP)
	player.facing = Vector2i.DOWN
	for i in inv.size():
		if inv.get_slot(i) == null:
			inv.slots[i] = {"id": "stone", "count": 99, "quality": ""}
	_check(player._try_harvest(c) and farm.get_tile(c).is_mature(), "가방이 가득 차면 작물이 남음")
	inv.load_data(saved)
	_check(player._try_harvest(c) and inv.count_of("strawberry") >= 1, "자리가 생기면 수확")

	# 감자: 1~3개
	farm.get_tile(c).seed_id = ""
	farm.plant(c, ps)
	farm.get_tile(c).days_grown = ps.grow_days
	var lo := 99
	var hi := 0
	for i in 60:
		var n: int = farm.roll_harvest(c).count
		lo = mini(lo, n)
		hi = maxi(hi, n)
	_check(lo == 1 and hi == 3, "감자 수확량 1~3개 (%d~%d)" % [lo, hi])
	farm.get_tile(c).seed_id = ""

	# 작물 정보 (§19)
	farm.plant(c, cs)
	farm.get_tile(c).days_grown = 1
	farm.get_tile(c).watered = true
	var info := farm.crop_info(c)
	var need := cs.grow_days
	_check(info.name == "당근" and not info.mature and info.days == 1 and info.need == need and info.days_left == need - 1 and info.watered, "작물 정보: 당근 1/%d일, 물 줌, %d일 남음" % [need, need - 1])
	var texts := CropInfoPopup.lines(info).map(func(l: Array) -> String: return l[0])
	_check(texts == ["자라는 중", "1 / %d일" % need, "오늘 물: 줬어요", "수확까지 %d일" % (need - 1)], "정보 문구 %s" % [texts])
	farm.get_tile(c).watered = false
	texts = CropInfoPopup.lines(farm.crop_info(c)).map(func(l: Array) -> String: return l[0])
	_check(texts.has("오늘 물: 안 줬어요") and texts.has("오늘은 자라지 않아요"), "물 안 주면 '오늘은 자라지 않아요'")
	farm.get_tile(c).days_grown = need
	texts = CropInfoPopup.lines(farm.crop_info(c)).map(func(l: Array) -> String: return l[0])
	_check(texts == ["수확할 수 있어요"], "다 자라면 '수확할 수 있어요'")
	_check(farm.crop_info(c + Vector2i(40, 40)).is_empty(), "작물 없는 칸은 정보 없음")
	var popup: CropInfoPopup = hud._crop_info
	popup.show_info(farm.crop_info(c))
	_check(popup.visible, "작물 정보 창 표시")
	hud.open_inventory()
	_check(not popup.visible, "가방을 열면 작물 정보 숨김")
	hud._close_panels()
	_check(popup.visible, "닫으면 다시 표시")
	popup.show_info({})
	_check(not popup.visible, "작물에서 벗어나면 숨김")
	farm.remove_crop(c)

	# 작물 뽑기 (§29): 괭이·곡괭이로만. 씨앗은 안 돌아오고 밭은 남는다
	farm.plant(c, cs)
	farm.water(c)
	var seeds_before := inv.count_of("carrot_seed")
	for tool_id in ["watering_can", "axe"]:
		farm.use_item(c, ItemDB.get_item(tool_id))
	_check(farm.get_tile(c).has_crop(), "물뿌리개·도끼로는 작물이 안 뽑힘")
	_check(farm.use_item(c, ItemDB.get_item("hoe")) and not farm.get_tile(c).has_crop() and farm.get_tile(c).watered, "괭이로 뽑기 (밭·물은 그대로)")
	_check(inv.count_of("carrot_seed") == seeds_before, "뽑아도 씨앗은 안 돌아옴")
	farm.plant(c, ss)
	farm.get_tile(c).regrowing = true
	_check(farm.use_item(c, ItemDB.get_item("pickaxe")) and not farm.get_tile(c).has_crop() and not farm.get_tile(c).regrowing, "곡괭이로 다시 열리는 포기도 뽑기")
	_check(farm.tiles.has(c), "뽑은 자리는 갈린 밭으로 남음")
	farm.plant(c, cs)
	farm.get_tile(c).days_grown = cs.grow_days
	player.global_position = world.cell_center(c + Vector2i.UP)
	player.facing = Vector2i.DOWN
	GameState.select_slot(0)
	var carrots := inv.count_of("carrot")
	player._use_selected()
	_check(inv.count_of("carrot") > carrots and not farm.get_tile(c).has_crop(), "다 자란 작물은 괭이로 쳐도 수확이 먼저")
	farm.get_tile(c).watered = false

	# 물뿌리개 용량 (items.json capacity)
	var can_slot := -1
	for i in inv.size():
		if inv.get_slot(i) != null and inv.get_slot(i)["id"] == "watering_can":
			can_slot = i
	_check(ItemDB.get_item("watering_can").capacity == 12, "물뿌리개 용량 12 (데이터)")
	inv.set_slot_value(can_slot, "water", 1)
	var c2 := _free_clear_cell(world)
	farm.till(c2)
	farm.get_tile(c).watered = false
	_check(WateringCan.use(world, c, inv, can_slot) and WateringCan.water_left(inv, can_slot) == 0, "마지막 물 한 번")
	_check(not WateringCan.use(world, c2, inv, can_slot) and not farm.get_tile(c2).watered, "물이 없으면 못 줌")
	_check(not WateringCan.use(world, _find_char("~"), inv, can_slot) and WateringCan.water_left(inv, can_slot) == 0, "개울·연못에서는 더 이상 안 채워짐")

	# 우물 (§14)
	var cap := ItemDB.get_item("watering_can").capacity
	var well: Well = world.buildings.filter(func(b: Interactable) -> bool: return b is Well)[0]
	_check(well.is_in_group(WateringCan.WATER_SOURCES), "우물은 물 공급원")
	_check(_find_char("W") in well.footprint() and well.footprint().size() == 4, "우물 위치 = 맵의 W 칸 (2x2)")
	_check(well.interact_point().distance_to(world.home_position) < 8 * Art.TILE, "우물은 집 가까이 (%.1f칸)" % (well.interact_point().distance_to(world.home_position) / Art.TILE))
	world.player.global_position = well.interact_point()
	_check(world.player._nearest_interactable() == well, "우물 앞에서 [E] 안내")
	well.interact(world.player)
	_check(WateringCan.water_left(inv, can_slot) == cap, "우물에서 [E] → 최대 용량까지 (%d/%d)" % [WateringCan.water_left(inv, can_slot), cap])
	_check(WateringCan.refill_all(inv, well).added == 0, "가득 차 있으면 그대로")
	inv.set_slot_value(can_slot, "water", 3)
	var well_cell: Vector2i = well.footprint()[0]
	_check(WateringCan.use(world, well_cell, inv, can_slot) and WateringCan.water_left(inv, can_slot) == cap, "물뿌리개로 우물 칸을 클릭해도 채워짐")
	_check(not well.covers_cell(well_cell + Vector2i(4, 0)), "우물 밖 칸은 공급원 아님")
	inv.add("watering_can")
	for i in inv.size():
		if WateringCan.is_can(inv, i):
			inv.set_slot_value(i, "water", 0)
	var res := WateringCan.refill_all(inv, well)
	_check(res.cans == 2 and res.added == cap * 2, "물뿌리개가 여러 개면 모두 채움")
	for i in range(inv.size() - 1, -1, -1):
		if WateringCan.is_can(inv, i) and i != can_slot:
			inv.remove_at(i)
			break
	_check(inv.count_of("watering_can") == 1, "점검용 물뿌리개 정리")
	farm.tiles.erase(c2)
	await get_tree().process_frame


func _test_time(world: FarmWorld, hud: HUD) -> void:
	GameState.set_clock(GameState.day_start)
	_check(GameState.day_length == 900.0 and GameState.warning_seconds == 60.0, "하루 15분, 1분 전 경고 (time.json)")
	_check(GameState.minutes == 7 * 60, "오전 7시 시작 (%s)" % GameState.format_clock(GameState.minutes))
	var warned := [false]
	var on_warn := func(_s: float) -> void: warned[0] = true
	Events.day_ending_soon.connect(on_warn)

	hud.open_inventory()
	var before := GameState.day_seconds
	GameState.advance_time(10.0)
	_check(GameState.day_seconds == before + 10.0 and GameState.is_input_locked(), "가방을 열어도 시간은 흐름 (조작만 막힘)")
	hud._close_panels()
	_check(not GameState.is_input_locked(), "가방 닫으면 조작 가능")

	Events.shop_requested.emit("buy")
	before = GameState.day_seconds
	GameState.advance_time(10.0)
	_check(GameState.day_seconds == before, "상점 창에서는 시간 멈춤")
	hud._close_panels()
	hud.open_build_panel()
	GameState.advance_time(10.0)
	_check(GameState.day_seconds == before, "건설 창에서는 시간 멈춤")
	hud._close_panels()
	world.build_mode.start(BuildMode.Mode.REMOVE)
	GameState.advance_time(10.0)
	_check(GameState.day_seconds == before, "철거 모드에서는 시간 멈춤")
	world.build_mode.stop()

	var day := GameState.day
	GameState.advance_time(839.0 - GameState.day_seconds)
	_check(not warned[0], "14분 전에는 경고 없음")
	GameState.advance_time(1.0)
	_check(warned[0] and GameState.day == day, "14분이 지나면 1분 남았다는 경고")
	GameState.advance_time(60.0)
	_check(GameState.day == day + 1 and GameState.day_seconds == 0.0 and GameState.minutes == 7 * 60, "15분이 지나면 다음 날 오전 7시")
	Events.day_ending_soon.disconnect(on_warn)


func _test_day_end(world: FarmWorld, hud: HUD) -> void:
	var dc := world.day_cycle
	var player := world.player
	var home := world.home_position
	var house: Interactable = world.buildings.filter(func(b: Interactable) -> bool: return b is House)[0]
	var started := [0]
	var on_start := func(_d: int) -> void: started[0] += 1
	Events.day_started.connect(on_start)
	_check(dc != null and dc.get_parent() == world, "하루 마감 흐름(DayCycle) 준비됨")
	_check(home == world.cell_center(_find_char("@")), "집 앞 시작 위치")

	# 1) 15분 자동 종료: 광장에서 가방을 연 채로
	GameState.set_clock(GameState.day_start)
	player.global_position = world.cell_center(_find_char("p"))
	player.facing = Vector2i.UP
	player.velocity = Vector2(30, 0)
	hud.open_inventory()
	var day := GameState.day
	var money := GameState.money
	var item_count := GameState.inventory.to_data().filter(func(sl: Variant) -> bool: return sl != null).size()
	GameState.advance_time(GameState.day_length + 1.0)
	var r: Dictionary = dc.last_report
	_check(r.reason == "time_up" and r.from_day == day and GameState.day == day + 1, "15분이 지나면 하루 마감 (time_up, %d일 → %d일)" % [day, GameState.day])
	_check(player.global_position == home and player.facing == Vector2i.DOWN and player.velocity == Vector2.ZERO, "멀리 있어도 다음 날은 집 앞에서 시작")
	_check(GameState.minutes == 7 * 60 and GameState.day_seconds == 0.0 and not GameState.is_day_ending_soon(), "다음 날 오전 7시 (%s)" % GameState.format_clock(GameState.minutes))
	_check(not hud._inventory.visible and not GameState.is_input_locked() and not GameState.is_time_paused() and not get_tree().paused, "열린 가방 닫힘, 입력·시간 정상")
	_check(r.phases == DayCycle.PHASES, "정해진 순서대로 처리")
	_check(started[0] == 1, "아침 신호는 한 번만")
	var item_after := GameState.inventory.to_data().filter(func(sl: Variant) -> bool: return sl != null).size()
	_check(GameState.money == money and item_after == item_count, "강제 종료 패널티 없음 (돈·아이템 그대로)")

	# 2) 집에서 직접 잠자기: 건설 모드를 켠 채로
	world.build_mode.start_place("scarecrow")
	player.global_position = house.interact_point()
	GameState.set_clock(12 * 60)
	day = GameState.day
	house.interact(player)
	r = dc.last_report
	_check(r.reason == "sleep" and GameState.day == day + 1, "집에서 자면 같은 마감 흐름 (sleep)")
	_check(player.global_position == home and GameState.minutes == 7 * 60 and GameState.day_seconds == 0.0, "집에서 오전 7시 시작")
	_check(not world.build_mode.is_active() and not world.build_mode.grid_overlay.visible and not GameState.is_time_paused(), "건설 모드·격자 정리, 시간 다시 흐름")
	_check(r.phases == DayCycle.PHASES and started[0] == 2, "같은 순서, 아침 신호 한 번")

	# 3) 상점 창이 열린 채로 잠들어도 창이 닫힘
	Events.shop_requested.emit("buy")
	GameState.sleep()
	_check(not hud._shop.visible and not get_tree().paused and not GameState.is_time_paused(), "상점 창 닫힘, 게임 재개")

	# 4) 작물은 하루에 한 번만 자람 (처리가 한 곳에서만 일어남)
	var farm := world.farm
	var c := _free_clear_cell(world)
	farm.till(c)
	farm.plant(c, ItemDB.get_item("carrot_seed"))
	farm.water(c)
	GameState.sleep()
	_check(farm.get_tile(c).days_grown == 1 and not farm.get_tile(c).watered, "작물은 하루에 한 번 자라고 밭이 마름")
	farm.remove_crop(c)
	farm.tiles.erase(c)

	# 5) 새 시스템은 단계에 등록만 하면 된다
	var calls := []
	var on_sales := func(_rep: Dictionary) -> void: calls.append(["sales", GameState.day])
	var on_night := func(rep: Dictionary) -> void:
		calls.append(["night", GameState.day])
		rep["night_production"] = {"flour": 3}
	var at_save := []
	var on_save := func(_rep: Dictionary) -> void: at_save.append([world.player.global_position, GameState.minutes, GameState.day])
	dc.add_step(DayCycle.SETTLE_SALES, on_sales)
	dc.add_step(DayCycle.NIGHT_PRODUCTION, on_night)
	dc.add_step(DayCycle.SAVE, on_save)
	player.global_position = world.cell_center(_find_char("p"))
	day = GameState.day
	var got := [{}]
	var on_ended := func(rep: Dictionary) -> void: got[0] = rep
	Events.day_ended.connect(on_ended)
	GameState.sleep()
	_check(calls == [["sales", day], ["night", day + 1]], "판매 정산은 날짜 넘기기 전, 야간 생산은 후 %s" % [calls])
	_check(got[0].get("night_production") == {"flour": 3}, "단계 결과가 하루 마감 보고(day_ended)에 담김")
	_check(DayCycle.PHASES[-1] == DayCycle.SAVE and at_save.size() == 1 and at_save[0] == [world.home_position, 7 * 60, day + 1], "자동 저장 자리는 맨 끝 (날짜·07:00·집 위치 반영 뒤)")
	dc.remove_step(DayCycle.SETTLE_SALES, on_sales)
	dc.remove_step(DayCycle.NIGHT_PRODUCTION, on_night)
	dc.remove_step(DayCycle.SAVE, on_save)
	Events.day_ended.disconnect(on_ended)

	# 6) 마감 도중 다시 불러도 한 번만
	var again := func(_rep: Dictionary) -> void: GameState.sleep()
	dc.add_step(DayCycle.SAVE, again)
	day = GameState.day
	GameState.sleep()
	dc.remove_step(DayCycle.SAVE, again)
	_check(GameState.day == day + 1, "마감 중 다시 요청해도 하루만 넘어감")
	Events.day_started.disconnect(on_start)
	await get_tree().process_frame


func _test_save(world: FarmWorld) -> void:
	var sm := world.save_manager
	var farm := world.farm
	var player := world.player
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	_check(sm != null and SaveManager.slot_path == TEST_SAVE, "저장 관리자 준비 (점검용 파일 사용)")

	# 하루 전환 자동 저장: 날짜 → 07:00 → 집 앞 → 저장
	player.global_position = world.cell_center(_find_char("p"))
	GameState.sleep()
	var auto := sm.read_save()
	_check(not auto.has("error") and auto.get("kind") == "auto" and int(auto.get("version", 0)) == SaveManager.VERSION, "하루 전환 자동 저장 (버전 %d)" % SaveManager.VERSION)
	if auto.has("sections"):
		var a_game: Dictionary = auto.sections.game
		_check(DataFile.to_vector2(auto.sections.player.position) == world.home_position and float(a_game.day_seconds) == 0.0 and int(a_game.day) == GameState.day, "자동 저장은 다음 날 07:00 집 앞 상태")

	# 수동 저장할 상태 만들기: 밭·작물·비료 전 품질 상태·가방(품질·물)·핫바·시설(회전)·해금·시각·위치
	var c := _free_clear_cell(world)
	farm.till(c)
	farm.plant(c, ItemDB.get_item("strawberry_seed"))
	farm.get_tile(c).days_grown = 2
	farm.get_tile(c).regrowing = true
	farm.water(c)
	inv.add("potato", 2, "gold")
	inv.add("carrot", 3, "silver")
	var can_slot := -1
	for i in inv.size():
		if WateringCan.is_can(inv, i):
			can_slot = i
	inv.set_slot_value(can_slot, "water", 5)
	GameState.select_slot(3)
	GameState.unlocks["test_region"] = true
	GameState.add_money(77)
	var shed := PlaceableDB.get_def("shed")
	var shed_at := _free_origin(world, shed, Vector2i(-1, -1))
	world.build.place(shed, shed_at)
	var gone_cell: Vector2i = world.obstacles.all()[0].cell
	world.obstacles.remove(gone_cell)
	await get_tree().process_frame
	GameState.set_clock(13 * 60 + 20)
	player.global_position = world.cell_center(c + Vector2i.UP) + Vector2(3, 2)
	player.facing = Vector2i.LEFT
	var snap := _snapshot(world)
	_check(sm.save_game("manual") and sm.has_save(), "수동 저장")

	# 다 바꿔 놓은 뒤 불러오기
	GameState.try_spend(50)
	GameState.set_clock(20 * 60)
	GameState.unlocks.clear()
	GameState.select_slot(0)
	inv.load_data([])
	farm.load_data({})
	world.build.load_data([])
	world.obstacles.spawn(gone_cell, "weed")
	player.global_position = world.home_position
	player.facing = Vector2i.DOWN
	_check(sm.load_game() and sm.last_load.failed.is_empty() and sm.last_load.missing.is_empty(), "불러오기 (손상·누락 없음)")
	# 프레임이 지나면 시간이 흐르고 물리가 위치를 조금 움직이므로 바로 비교한다
	var after := _snapshot(world)
	for key: String in snap:
		_check(after[key] == snap[key], "불러온 뒤 %s 상태 같음" % key)
	_check(GameState.minutes == 13 * 60 + 20 and player.global_position == snap.player_pos and player.facing == Vector2i.LEFT, "저장 당시 위치·시각에서 재개 (%s)" % GameState.format_clock(GameState.minutes))
	_check(inv.count_of("potato", "gold") >= 2 and inv.count_of("carrot", "silver") >= 3 and WateringCan.water_left(inv, can_slot) == 5 and GameState.selected_slot == 3, "가방 품질·물뿌리개 물·핫바 선택 유지")
	var t := farm.get_tile(c)
	_check(t != null and t.seed_id == "strawberry_seed" and t.days_grown == 2 and t.regrowing and t.watered, "밭·수분·작물·성장·다시 열림 상태 유지")
	_check(world.build.object_at(shed_at) != null and not world.obstacles.is_blocked(gone_cell), "시설·치운 장애물 유지")
	_check(GameState.unlocks.get("test_region") == true, "해금 상태 유지")
	await get_tree().process_frame

	# 손상된 파일: 불러오지 않고 지금 상태 그대로
	var money := GameState.money
	_write_test_save("{ 망가진 저장")
	_check(not sm.load_game() and GameState.money == money and sm.last_load.error != "", "손상된 파일은 안 불러옴 (%s)" % sm.last_load.error)
	_write_test_save(JSON.stringify({"version": 99, "sections": {}}))
	_check(not sm.load_game() and str(sm.last_load.error).contains("새로운 버전"), "더 새 버전 저장은 거부")
	_write_test_save(JSON.stringify({"sections": {}}))
	_check(not sm.load_game(), "버전 없는 저장은 거부")

	# 일부 섹션만 손상: 그 섹션은 지금 상태 유지, 나머지는 불러옴
	sm.save_game("manual")
	var d := sm.read_save()
	d.sections.farm = 5
	d.sections.build = "oops"
	d.sections.game.money = 4321
	d.sections.erase("player")
	_write_test_save(JSON.stringify(d))
	var farm_before := farm.to_data()
	var build_before := world.build.to_data()
	var pos_before := player.global_position
	_check(sm.load_game() and "farm" in sm.last_load.failed and "build" in sm.last_load.failed and "player" in sm.last_load.missing, "손상된 섹션만 건너뜀 %s / 없음 %s" % [sm.last_load.failed, sm.last_load.missing])
	_check(farm.to_data() == farm_before and world.build.to_data() == build_before and player.global_position == pos_before, "손상된 섹션은 지금 상태 유지")
	_check(GameState.money == 4321, "멀쩡한 섹션은 불러옴")

	# 저장이 없을 때
	_remove_test_save()
	_check(not sm.has_save() and not sm.load_game() and SaveManager.describe_save() == "", "저장이 없으면 안전하게 실패")

	# 정리
	world.build.remove(world.build.object_at(shed_at))
	farm.remove_crop(c)
	farm.tiles.erase(c)
	inv.load_data(saved_inv)
	GameState.unlocks.clear()
	GameState.select_slot(0)
	await get_tree().process_frame


func _test_shipping(world: FarmWorld, hud: HUD) -> void:
	var bin := world.shipping_bin
	var inv := GameState.inventory
	var player := world.player
	var saved_inv := inv.to_data()
	var bin_cell := Vector2i(floori(bin.global_position.x / Art.TILE), floori(bin.global_position.y / Art.TILE) - 1)
	_check(bin != null and bin_cell == _find_char("O"), "출하함 위치 = 맵의 O 칸 (2x1)")
	_check(bin.interact_point().distance_to(world.home_position) < 8 * Art.TILE, "출하함은 집 가까이")
	player.global_position = bin.interact_point()
	_check(player._nearest_interactable() == bin, "출하함 앞에서 [E] 안내")

	# 창: 상점처럼 게임·시간 정지
	bin.interact(player)
	var before := GameState.day_seconds
	GameState.advance_time(5.0)
	_check(hud._bin_panel.visible and GameState.is_time_paused() and get_tree().paused and GameState.day_seconds == before, "출하함 창을 열면 시간 정지")
	hud._close_panels()
	_check(not hud._bin_panel.visible and not GameState.is_time_paused() and not get_tree().paused, "출하함 창 닫으면 다시 흐름")

	# 넣기 / 꺼내기 (아이템이 사라지지 않음)
	inv.load_data([])
	inv.add("carrot", 5, "silver")
	inv.add("potato", 2, "gold")
	inv.add("hoe")
	_check(bin.deposit(inv, "carrot", "silver", 3) == 3 and inv.count_of("carrot", "silver") == 2 and bin.count_of("carrot", "silver") == 3, "당근(실버) 3개 넣기")
	_check(bin.deposit(inv, "potato", "gold", 9) == 2 and inv.count_of("potato") == 0 and bin.count_of("potato", "gold") == 2, "가진 것보다 많이 넣으면 가진 만큼만")
	_check(bin.deposit(inv, "hoe", "", 1) == 0 and inv.count_of("hoe") == 1, "판매가 없는 물건(도구)은 안 들어감")
	_check(bin.withdraw(inv, "carrot", "silver", 1) == 1 and inv.count_of("carrot", "silver") == 3 and bin.count_of("carrot", "silver") == 2, "하루가 끝나기 전에는 다시 꺼낼 수 있음")
	var expect := 2 * Pricing.unit_price(ItemDB.get_item("carrot"), "silver", Pricing.SHIPPING_BIN) + 2 * Pricing.unit_price(ItemDB.get_item("potato"), "gold", Pricing.SHIPPING_BIN)
	_check(bin.pending_value() == expect, "오늘 밤 받을 돈 = 품질가 100%% (%d G)" % bin.pending_value())
	var keep := inv.to_data()
	for i in inv.size():
		if inv.get_slot(i) == null:
			inv.slots[i] = {"id": "stone", "count": 99, "quality": ""}
	_check(bin.withdraw(inv, "potato", "gold", 1) == 0 and bin.count_of("potato", "gold") == 2, "가방이 가득 차면 꺼내지 않음 (출하함에 그대로)")
	inv.load_data(keep)
	bin.interact(player)
	_check(hud._bin_panel._bin_list.get_child_count() == 2 and hud._bin_panel._pending.text.contains(str(expect)), "출하함 창에 내용·받을 돈 표시")
	hud._close_panels()

	# 저장에 들어감
	world.save_manager.save_game("manual")
	bin.contents.clear()
	world.save_manager.load_game()
	_check(bin.count_of("carrot", "silver") == 2 and bin.count_of("potato", "gold") == 2, "출하함 내용 저장·불러오기")

	# 광장 즉시 판매는 80%, 오늘 장부에 적힘
	var money := GameState.money
	var plaza_silver := Pricing.unit_price(ItemDB.get_item("carrot"), "silver", Pricing.PLAZA)
	hud._shop._sell("carrot", 1, "silver")
	_check(GameState.money == money + plaza_silver and int(GameState.today_sales.get(Pricing.PLAZA, 0)) >= plaza_silver, "광장 즉시 판매는 80%% (실버 당근 %d G), 오늘 장부에 기록" % plaza_silver)

	# 하루 마감: 출하함 정산 + 판매 수익 요약
	money = GameState.money
	var plaza_today := int(GameState.today_sales.get(Pricing.PLAZA, 0))
	GameState.sleep()
	var r: Dictionary = world.day_cycle.last_report
	_check(GameState.money == money + expect and bin.is_empty(), "하루가 끝나면 출하함 물건이 팔림 (+%d G)" % expect)
	_check(int(r.sales.by_channel.get(Pricing.SHIPPING_BIN, 0)) == expect and int(r.sales.by_channel.get(Pricing.PLAZA, 0)) == plaza_today and int(r.sales.total) == expect + plaza_today, "판매 요약: 출하함 %d + 광장 %d" % [expect, plaza_today])
	_check(r.shipping.items.size() == 2 and GameState.today_sales.is_empty(), "정산 내역, 오늘 장부 비움")
	_check(hud._summary.visible and get_tree().paused and GameState.is_time_paused(), "판매 수익 요약 창 (게임·시간 멈춤)")
	_check(hud._summary._total.text.contains(SalesSummaryPanel.format_gold(expect + plaza_today)) and hud._summary._lines.get_child_count() == 2, "요약에 판매 방식별 금액·합계")
	hud._close_panels()
	_check(not hud._summary.visible and not get_tree().paused and not GameState.is_time_paused(), "확인하면 게임 재개")
	GameState.sleep()
	_check(not hud._summary.visible and int(world.day_cycle.last_report.sales.total) == 0, "판 게 없는 날은 요약을 띄우지 않음")
	_check(SalesSummaryPanel.format_gold(2400) == "2,400" and SalesSummaryPanel.format_gold(1234567) == "1,234,567" and SalesSummaryPanel.format_gold(35) == "35", "금액 쉼표 표시")
	inv.load_data(saved_inv)
	await get_tree().process_frame


func _test_fertilizer(world: FarmWorld) -> void:
	var farm := world.farm
	var inv := GameState.inventory
	var player := world.player
	var saved_inv := inv.to_data()
	var ids := ["basic_fertilizer", "advanced_fertilizer", "premium_fertilizer"]

	# 데이터: 상점 무한 구매, 확률표 = 기획서 §25
	var shop_ids := ItemDB.shop_items().map(func(it: ItemDef) -> String: return it.id)
	_check(ids.all(func(id: String) -> bool: return ItemDB.get_item(id) != null and ItemDB.get_item(id).kind == ItemDef.Kind.FERTILIZER and ItemDB.get_item(id).buy_price > 0 and id in shop_ids), "비료 3종, 상점에서 구매 가능")
	var plan: Dictionary = _econ().quality.harvest_chances
	var chances: Dictionary = DataFile.load_dict(Quality.DATA_PATH).get("harvest_chances", {})
	var same := plan.size() == 4
	for t: String in plan:
		var row: Dictionary = chances.get(t, {})
		for q: String in ["bronze", "silver", "gold"]:
			same = same and int(row.get(q, -1)) == int(plan[t][q])
	_check(same, "품질 확률표 = 경제 기준 v1.0 (무비료·기본·고급·최상급)")
	_check(ids.map(func(id: String) -> String: return ItemDB.get_item(id).quality_table) == ["basic", "advanced", "premium"], "비료 → 확률표 연결")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var counts := {"bronze": 0, "silver": 0, "gold": 0}
	for i in 4000:
		counts[Quality.roll(rng, "premium")] += 1
	_check(absf(counts.gold / 4000.0 - plan.premium.gold / 100.0) < 0.03 and absf(counts.bronze / 4000.0 - plan.premium.bronze / 100.0) < 0.03, "최상급 비료 품질 분포 %s" % counts)

	# 뿌리기 규칙: 갈아 둔 빈 밭에, 심기 전에만
	var c := _free_clear_cell(world)
	var basic := ItemDB.get_item("basic_fertilizer")
	var premium := ItemDB.get_item("premium_fertilizer")
	# 지금 계절에 밖에 심을 수 있는 씨앗 (앞 점검들이 날짜를 얼마나 넘겼는지와 상관없이)
	var season := Calendar.season_of(GameState.day)
	var carrot_seed: ItemDef = ItemDB.get_item("carrot_seed")
	for it: ItemDef in ItemDB.shop_items():
		if it.kind == ItemDef.Kind.SEED and Calendar.crop_allowed(it, season) and not it.regrows():
			carrot_seed = it
			break
	_check(not farm.fertilize(c, basic), "갈지 않은 땅에는 못 뿌림")
	farm.till(c)
	_check(farm.fertilize(c, basic) and farm.get_tile(c).fertilizer == "basic_fertilizer", "갈아 둔 빈 밭에 비료")
	_check(not farm.fertilize(c, premium) and farm.get_tile(c).fertilizer == "basic_fertilizer", "이미 뿌린 밭은 덮어쓰지 않음")
	farm.get_tile(c).fertilizer = ""
	farm.plant(c, carrot_seed)
	_check(not farm.fertilize(c, basic) and farm.get_tile(c).fertilizer == "", "씨앗을 심은 뒤에는 못 뿌림")
	farm.remove_crop(c)

	# 플레이어가 뿌리면 1개 쓰고, 못 뿌리면 그대로
	inv.slots[8] = {"id": "premium_fertilizer", "count": 3, "quality": ""}
	GameState.select_slot(8)
	player.global_position = world.cell_center(c + Vector2i.UP)
	player.facing = Vector2i.DOWN
	player._use_selected()
	_check(farm.get_tile(c).fertilizer == "premium_fertilizer" and inv.count_of("premium_fertilizer") == 2, "플레이어가 뿌리면 비료 1개 사용")
	player._use_selected()
	_check(inv.count_of("premium_fertilizer") == 2, "못 뿌리면 비료가 줄지 않음")
	GameState.select_slot(0)

	# 수확 품질에 반영
	farm.plant(c, carrot_seed)
	farm.get_tile(c).days_grown = carrot_seed.grow_days
	_check(farm.get_tile(c).quality_table() == "premium", "수확 때 최상급 비료 확률표 사용")
	farm.rng.seed = 11
	var gold := 0
	for i in 400:
		if farm.roll_harvest(c).quality == "gold":
			gold += 1
	_check(gold > 400 * 0.3, "최상급 비료 밭은 골드가 잘 나옴 (%d/400)" % gold)
	_check(CropInfoPopup.lines(farm.crop_info(c)).any(func(l: Array) -> bool: return l[0] == "비료: 최상급 비료"), "작물 정보에 비료 표시")

	# 저장
	world.save_manager.save_game("manual")
	farm.get_tile(c).fertilizer = ""
	world.save_manager.load_game()
	_check(farm.get_tile(c) != null and farm.get_tile(c).fertilizer == "premium_fertilizer", "비료 상태 저장·불러오기")

	# 한 번 거두는 작물: 수확하면 비료 끝 (밭은 남음)
	farm.harvest(c)
	_check(farm.tiles.has(c) and farm.get_tile(c).fertilizer == "" and not farm.get_tile(c).has_crop(), "한 번 거두는 작물은 수확하면 비료 효과 끝")

	# 다시 열리는 작물: 포기가 살아 있는 동안 유지
	var strawberry: ItemDef = ItemDB.get_item("strawberry_seed")
	for it: ItemDef in ItemDB.shop_items():
		if it.kind == ItemDef.Kind.SEED and it.regrows() and Calendar.crop_allowed(it, season):
			strawberry = it  # 지금 계절에 심을 수 있는 다시 열리는 작물
			break
	farm.fertilize(c, basic)
	farm.plant(c, strawberry)
	farm.get_tile(c).days_grown = strawberry.grow_days
	farm.harvest(c)
	_check(farm.get_tile(c).has_crop() and farm.get_tile(c).fertilizer == "basic_fertilizer", "다시 열리는 작물은 수확 뒤에도 비료 유지")
	farm.get_tile(c).days_grown = strawberry.regrow_days
	farm.harvest(c)
	_check(farm.get_tile(c).fertilizer == "basic_fertilizer", "두 번째 수확 뒤에도 유지")
	farm.remove_crop(c)
	_check(farm.get_tile(c).fertilizer == "" and farm.tiles.has(c), "작물을 뽑으면 비료 효과 끝 (밭은 남음)")

	farm.tiles.erase(c)
	inv.load_data(saved_inv)
	GameState.select_slot(0)
	await get_tree().process_frame


func _test_seasons(world: FarmWorld, hud: HUD) -> void:
	var farm := world.farm
	var start_day := GameState.day
	# 날짜 계산 (계절 28일, 봄 → 여름 → 가을 → 겨울 → 봄)
	_check(Calendar.days_per_season() == 28 and Calendar.seasons() == ["spring", "summer", "autumn", "winter"], "계절 4개, 28일씩 (calendar.json)")
	var table := [[1, "spring", 1, 1], [28, "spring", 28, 1], [29, "summer", 1, 1], [57, "autumn", 1, 1], [85, "winter", 1, 1], [112, "winter", 28, 1], [113, "spring", 1, 2]]
	var calc_ok := true
	for row: Array in table:
		calc_ok = calc_ok and Calendar.season_of(row[0]) == row[1] and Calendar.day_in_season(row[0]) == row[2] and Calendar.year_of(row[0]) == row[3]
	_check(calc_ok, "날짜 → 계절·날·연차 계산 (113일 = 2년차 봄 1일)")
	_check(Calendar.date_text(30) == "여름 2일" and Calendar.date_text(113) == "2년차 봄 1일", "날짜 글자")
	_check(ItemDB.get_item("carrot_seed").seasons == ["spring"], "작물 계절 데이터 사용 (당근 = 봄)")

	# 점검용 여러 계절 작물 (봄·여름)
	ItemDB._items["test_multi_seed"] = ItemDef.from_dict("test_multi_seed", {"kind": "seed", "grows": "carrot", "grow_days": 9, "seasons": ["spring", "summer"], "crop_row": 0})

	# 봄 마지막 날에 밭을 꾸린다
	GameState.day = 28
	var cells := []
	for c: Vector2i in farm.farmable_cells.keys():
		if cells.size() >= 5:
			break
		if not world.obstacles.is_blocked(c) and not world.build.is_occupied(c) and not farm.tiles.has(c):
			cells.append(c)
	var spring_c: Vector2i = cells[0]   # 봄 작물 (비료)
	var multi_c: Vector2i = cells[1]    # 봄·여름 작물
	var dry_c: Vector2i = cells[2]      # 빈 마른 밭
	var wet_c: Vector2i = cells[3]      # 빈 젖은 밭
	for c: Vector2i in cells.slice(0, 4):
		farm.till(c)
	farm.fertilize(spring_c, ItemDB.get_item("basic_fertilizer"))
	farm.plant(spring_c, ItemDB.get_item("carrot_seed"))
	farm.plant(multi_c, ItemDB._items["test_multi_seed"])
	farm.water(wet_c)
	farm.water(spring_c)
	farm.rng.seed = 5
	GameState.sleep()
	hud._close_panels()
	var r: Dictionary = world.day_cycle.last_report
	_check(Calendar.season_of(GameState.day) == "summer" and r.has("season") and r.season.from == "spring" and r.season.to == "summer", "28일이 끝나면 여름 (%s)" % Calendar.date_text(GameState.day))
	var t := farm.get_tile(spring_c)
	_check(t.withered and t.has_crop() and not t.is_mature() and t.fertilizer == "", "봄 작물은 여름이 되면 시듦, 비료 효과 끝")
	_check(not farm.get_tile(multi_c).withered, "봄·여름 작물은 여름에도 살아 있음")
	_check(farm.tiles.has(wet_c), "젖은 빈 밭은 그대로")
	_check(hud._day_label.text.begins_with("여름 1일"), "날짜 표시에 계절 (%s)" % hud._day_label.text)

	# 시든 작물: 자라지 않고, 거둘 수 없고, 물로 살아나지 않고, 뽑아야 함
	var grown := t.days_grown
	farm.water(spring_c)
	GameState.sleep()
	hud._close_panels()
	t = farm.get_tile(spring_c)
	_check(t.withered and t.days_grown == grown and farm.roll_harvest(spring_c).is_empty(), "시든 작물은 물을 줘도 안 자라고 거둘 수 없음")
	_check(CropInfoPopup.lines(farm.crop_info(spring_c))[0][0] == "시들었어요", "작물 정보: 시들었어요")
	world.save_manager.save_game("manual")
	t.withered = false
	world.save_manager.load_game()
	_check(farm.get_tile(spring_c).withered, "시든 상태 저장·불러오기")
	_check(farm.use_item(spring_c, ItemDB.get_item("hoe")) and not farm.get_tile(spring_c).has_crop() and not farm.get_tile(spring_c).withered, "시든 작물은 괭이로 뽑음 (밭은 남음)")

	# 빈 마른 밭 약 35% 되돌림 (많은 칸으로 확인)
	var empty_cells := []
	for c: Vector2i in farm.farmable_cells.keys():
		if not farm.tiles.has(c) and not world.obstacles.is_blocked(c) and not world.build.is_occupied(c):
			empty_cells.append(c)
		if empty_cells.size() >= 300:
			break
	for c: Vector2i in empty_cells:
		farm.tiles[c] = SoilTile.new()
	var wet_keep: Vector2i = empty_cells[0]
	farm.tiles[wet_keep].last_watered = true
	farm.rng.seed = 21
	var res := farm.change_season("autumn")
	var ratio := float(res.reverted) / (empty_cells.size() - 1)
	_check(absf(ratio - 0.35) < 0.08 and farm.tiles.has(wet_keep), "빈 마른 밭 약 35%% 되돌림 (%d%%), 젖은 밭은 유지" % roundi(ratio * 100))
	_check(farm.get_tile(multi_c).withered, "여러 계절 작물도 허용 안 되는 계절(가을)이 되면 시듦")
	for c: Vector2i in empty_cells:
		farm.tiles.erase(c)

	# 겨울: 바깥 밭에 새 작물을 심을 수 없음
	GameState.day = 85
	farm.till(dry_c)
	_check(Calendar.season_of(GameState.day) == "winter" and not farm.plant(dry_c, ItemDB.get_item("carrot_seed")), "겨울에는 바깥 밭에 심을 수 없음")
	GameState.day = 113
	_check(farm.plant(dry_c, ItemDB.get_item("carrot_seed")), "다시 봄이 오면 심을 수 있음")

	# 정리
	for c: Vector2i in cells:
		farm.tiles.erase(c)
	ItemDB._items.erase("test_multi_seed")
	GameState.day = start_day
	await get_tree().process_frame


func _test_weather(world: FarmWorld, hud: HUD) -> void:
	var farm := world.farm
	var start_day := GameState.day
	# 데이터
	var types: Dictionary = DataFile.load_dict(Weather.DATA_PATH).get("types", {})
	_check(types.has_all(["sunny", "cloudy", "rain", "snow"]) and Weather.first_day() == "sunny", "날씨 4종 (맑음·흐림·비·눈), 첫날 맑음")
	_check(Weather.waters_soil("rain") and not Weather.waters_soil("snow") and not Weather.waters_soil("cloudy"), "비만 밭을 적심 (눈은 날씨 상태만)")
	_check(Weather.weights_for(85).has("snow") and not Weather.weights_for(85).has("rain") and not Weather.weights_for(1).has("snow"), "겨울에는 비 대신 눈")
	var share := func(day: int) -> float:
		var w := Weather.weights_for(day)
		var total := 0.0
		for v: Variant in w.values():
			total += float(v)
		return float(w.get("rain", 0)) / total
	var avg := func(first: int) -> float:
		var sum := 0.0
		for d in 28:
			sum += share.call(first + d)
		return sum / 28.0
	_check(avg.call(29) > avg.call(1) and avg.call(29) > avg.call(57), "여름 비가 가장 많음 (봄 %d%% 여름 %d%% 가을 %d%%)" % [roundi(avg.call(1) * 100), roundi(avg.call(29) * 100), roundi(avg.call(57) * 100)])
	_check(share.call(28 + 15) > share.call(28 + 3) and share.call(28 + 15) > share.call(28 + 25), "여름 중간(장마)에 비가 몰림")
	Weather.forced = ""
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var rain := 0
	for i in 2000:
		if Weather.roll(28 + 15, rng) == "rain":
			rain += 1
	_check(absf(rain / 2000.0 - share.call(28 + 15)) < 0.05, "날씨 뽑기 확률 = 데이터 (장마 비 %d%%)" % roundi(rain / 20.0))

	# 비 오는 날: 07:00부터 바깥 밭 전체가 젖고, 작물은 물 없이 자람
	GameState.day = 3
	var cells := []
	for c: Vector2i in farm.farmable_cells.keys():
		if cells.size() >= 3:
			break
		if not world.obstacles.is_blocked(c) and not world.build.is_occupied(c) and not farm.tiles.has(c):
			cells.append(c)
	var crop_c: Vector2i = cells[0]
	var empty_c: Vector2i = cells[1]
	farm.till(crop_c)
	farm.till(empty_c)
	farm.plant(crop_c, ItemDB.get_item("carrot_seed"))
	Weather.forced = "rain"
	GameState.sleep()
	hud._close_panels()
	var r: Dictionary = world.day_cycle.last_report
	_check(GameState.weather == "rain" and r.weather.id == "rain" and r.weather.watered >= 2, "아침에 비 결정 (밭 %d칸 젖음)" % r.weather.watered)
	_check(farm.get_tile(crop_c).watered and farm.get_tile(empty_c).watered, "비 오는 날은 07:00부터 바깥 밭이 모두 젖어 있음")
	_check(hud._day_label.text.ends_with("비") and hud._weather_fx.visible and hud._weather_fx.weather == "rain", "날짜 옆에 날씨, 비 화면 효과 (%s)" % hud._day_label.text)
	# 밤사이 장애물이 다시 날 수 있어 새로 갈 칸은 아침에 고른다
	var new_c: Vector2i = cells[2]
	for c: Vector2i in farm.farmable_cells.keys():
		if not world.obstacles.is_blocked(c) and not world.build.is_occupied(c) and not farm.tiles.has(c):
			new_c = c
			break
	_check(farm.till(new_c) and farm.get_tile(new_c).watered, "비 오는 날 새로 간 밭도 젖음")
	var inv := GameState.inventory
	var can_slot := -1
	for i in inv.size():
		if WateringCan.is_can(inv, i):
			can_slot = i
	var water_before := WateringCan.water_left(inv, can_slot)
	WateringCan.use(world, crop_c, inv, can_slot)
	_check(WateringCan.water_left(inv, can_slot) == water_before, "이미 젖은 밭에는 물뿌리개 물이 줄지 않음")
	GameState.advance_time(300.0)
	_check(GameState.weather == "rain", "하루 중에는 날씨가 바뀌지 않음")
	world.save_manager.save_game("manual")
	GameState.set_weather("sunny")
	world.save_manager.load_game()
	_check(GameState.weather == "rain", "날씨 저장·불러오기")
	var grown := farm.get_tile(crop_c).days_grown
	Weather.forced = "sunny"
	GameState.sleep()
	hud._close_panels()
	_check(farm.get_tile(crop_c).days_grown == grown + 1 and not farm.get_tile(crop_c).watered, "비 온 날 작물은 물을 안 줘도 자람, 다음 날(맑음)은 마름")
	_check(not hud._weather_fx.visible and hud._day_label.text.ends_with("맑음"), "맑은 날은 비 효과 없음")

	# 겨울 눈: 밭을 적시지 않음 (상태·화면 효과만)
	GameState.day = 84
	Weather.forced = "snow"
	GameState.sleep()
	hud._close_panels()
	r = world.day_cycle.last_report
	_check(Calendar.season_of(GameState.day) == "winter" and GameState.weather == "snow" and r.weather.watered == 0, "겨울 눈은 밭을 적시지 않음")
	_check(hud._weather_fx.visible and hud._weather_fx.weather == "snow", "눈 화면 효과")

	# 정리
	for c: Vector2i in cells:
		farm.tiles.erase(c)
	Weather.forced = "sunny"
	GameState.set_weather("sunny")
	GameState.day = start_day
	await get_tree().process_frame


func _test_blacksmith(world: FarmWorld, hud: HUD) -> void:
	var inv := GameState.inventory
	var farm := world.farm
	var obs := world.obstacles
	var player := world.player
	var saved_inv := inv.to_data()
	var money0 := GameState.money
	var smith: Blacksmith = world.buildings.filter(func(b: Interactable) -> bool: return b is Blacksmith)[0]
	var smith_cell := Vector2i(floori(smith.global_position.x / Art.TILE), floori(smith.global_position.y / Art.TILE) - 3)
	_check(smith_cell == _find_char("K") and smith_cell.x > _find_char("#").x, "대장간은 메인 광장 (맵의 K, 4x3)")
	player.global_position = smith.interact_point()
	_check(player._nearest_interactable() == smith, "대장간 앞에서 [E] 안내")
	smith.interact(player)
	_check(world.area == "smith", "대장간 [E] → 안으로 들어감")
	var smith_npc: Npc = (world.interiors["smith"] as Interior).npc
	player.global_position = smith_npc.interact_point()
	await get_tree().physics_frame
	player._interact()
	_check(hud._dialog.visible and hud._dialog._name.text == "대장장이 철수", "대장장이에게 말 걸기 → 대화 창")
	hud._dialog.choose("smith")
	_check(hud._smith.visible and GameState.is_time_paused() and get_tree().paused, "[도구 강화] → 강화 창 (시간 정지)")

	# 데이터: 네 도구 모두 강화 경로 (돈 + 자원)
	var paths_ok := true
	for id: String in ["hoe", "watering_can", "axe", "pickaxe"]:
		var item := ItemDB.get_item(id)
		var next := ToolUpgrade.next_of(item)
		paths_ok = paths_ok and next != null and next.tier == item.tier + 1 and next.tool_type == item.tool_type 				and ToolUpgrade.price_of(item) > 0 and not ToolUpgrade.materials_of(item).is_empty()
	_check(paths_ok, "괭이·물뿌리개·도끼·곡괭이 강화 경로 (돈 + 자원, items.json)")
	var all_tier1 := ["big_rock", "big_stump", "mine_iron", "mine_gold"].all(func(id: String) -> bool: return ObstacleDB.get_def(id).tier <= ItemDB.get_item("pickaxe").tier)
	_check(all_tier1, "돌 도구로도 모든 장애물을 치움 (강화는 속도·범위만)")

	# 돈·재료가 모자라면 안 됨
	inv.load_data([])
	for id: String in ["hoe", "watering_can", "axe", "pickaxe"]:
		inv.add(id)
	var slot_of := func(id: String) -> int:
		for i in inv.size():
			if inv.get_slot(i) != null and inv.get_slot(i)["id"] == id:
				return i
		return -1
	var hoe_slot: int = slot_of.call("hoe")
	GameState.money = 0
	_check(not ToolUpgrade.apply(inv, hoe_slot) and inv.item_at(hoe_slot).id == "hoe", "돈이 모자라면 강화 안 됨")
	GameState.money = 10000
	_check(not ToolUpgrade.apply(inv, hoe_slot) and inv.item_at(hoe_slot).id == "hoe" and GameState.money == 10000, "재료가 모자라면 강화 안 됨 (돈도 그대로)")
	inv.add("copper_bar", 99)
	hud._smith.refresh()
	_check(hud._smith._list.get_child_count() == 4, "대장간 창에 도구 4개")

	# 괭이 강화: 즉시, 같은 칸
	var hoe := ItemDB.get_item("hoe")
	var price := ToolUpgrade.price_of(hoe)
	var mats := ToolUpgrade.materials_of(hoe)
	_check(ToolUpgrade.apply(inv, hoe_slot) and inv.item_at(hoe_slot).id == "hoe_2" and inv.item_at(hoe_slot).name == "구리 괭이", "강화하면 바로 구리 괭이 (같은 칸)")
	_check(GameState.money == 10000 - price and mats.keys() == ["copper_bar"] and inv.count_of("copper_bar") == 99 - int(mats.copper_bar), "강화 비용: %d G + 구리 주괴 %d" % [price, int(mats.copper_bar)])
	_check(ToolUpgrade.next_of(inv.item_at(hoe_slot)).id == "hoe_3" and not ToolUpgrade.check(inv, hoe_slot).ok and ToolUpgrade.check(inv, hoe_slot).reason.contains("철 주괴"), "구리 → 철은 철 주괴가 있어야 (%s)" % ToolUpgrade.check(inv, hoe_slot).reason)

	# 물뿌리개: 물은 그대로, 용량 증가
	var can_slot: int = slot_of.call("watering_can")
	inv.set_slot_value(can_slot, "water", 7)
	ToolUpgrade.apply(inv, can_slot)
	var can2 := inv.item_at(can_slot)
	_check(can2.id == "watering_can_2" and can2.capacity > ItemDB.get_item("watering_can").capacity and WateringCan.water_left(inv, can_slot) == 7, "강화 물뿌리개: 용량 %d → %d, 물은 그대로" % [ItemDB.get_item("watering_can").capacity, can2.capacity])
	var well: Well = world.buildings.filter(func(b: Interactable) -> bool: return b is Well)[0]
	WateringCan.refill_all(inv, well)
	_check(WateringCan.water_left(inv, can_slot) == can2.capacity, "우물에서 새 용량까지 채움")

	# 도끼·곡괭이
	var axe_slot: int = slot_of.call("axe")
	var pick_slot: int = slot_of.call("pickaxe")
	ToolUpgrade.apply(inv, axe_slot)
	ToolUpgrade.apply(inv, pick_slot)
	_check(inv.item_at(axe_slot).id == "axe_2" and inv.item_at(pick_slot).id == "pickaxe_2", "도끼·곡괭이 강화")
	hud._close_panels()

	# 강화 괭이: 앞으로 3칸
	var start := Vector2i(-1, -1)
	var cells: Array = farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var free := true
		for k in 3:
			var cc: Vector2i = c + Vector2i.DOWN * k
			free = free and farm.is_farmable(cc) and not obs.is_blocked(cc) and not farm.tiles.has(cc) and not world.build.is_occupied(cc)
		if free:
			start = c
			break
	_check(farm.use_item(start, inv.item_at(hoe_slot), Vector2i.DOWN) and farm.tiles.has(start) and not farm.tiles.has(start + Vector2i.DOWN), "구리 괭이: 그냥 누르면 1칸")
	farm.tiles.erase(start)
	_check(farm.use_item(start, inv.item_at(hoe_slot), Vector2i.DOWN, 2) and farm.tiles.has(start) and farm.tiles.has(start + Vector2i.DOWN) and farm.tiles.has(start + Vector2i.DOWN * 2), "구리 괭이: 1초 꾹 누르면 바라보는 방향으로 3칸")
	player.global_position = world.cell_center(start + Vector2i(1, 0))
	_check(player.work_dir(start + Vector2i(3, 0)) == Vector2i.RIGHT and player.work_dir(start + Vector2i(1, -2)) == Vector2i.UP, "일하는 방향 = 대상 칸 쪽")

	# 강화 곡괭이·도끼: 빨라지고 큰 장애물도
	var spot := _free_clear_cell(world)
	obs.spawn(spot, "big_rock")
	var hits := 0
	while obs.is_blocked(spot) and hits < 10:
		obs.try_clear(spot, inv.item_at(pick_slot))
		hits += 1
	_check(not obs.is_blocked(spot) and hits == 3, "강화 곡괭이는 큰 바위를 %d번에 (기본 6번)" % hits)
	await get_tree().process_frame
	obs.spawn(spot, "big_stump")
	hits = 0
	while obs.is_blocked(spot) and hits < 10:
		obs.try_clear(spot, inv.item_at(axe_slot))
		hits += 1
	_check(not obs.is_blocked(spot) and hits == 3, "강화 도끼는 큰 그루터기를 %d번에" % hits)
	await get_tree().process_frame
	obs.spawn(spot, "stump")
	obs.try_clear(spot, inv.item_at(axe_slot))
	obs.try_clear(spot, inv.item_at(axe_slot))
	_check(not obs.is_blocked(spot), "작은 그루터기도 더 빨리 (2번)")
	await get_tree().process_frame

	# 저장
	world.save_manager.save_game("manual")
	inv.load_data([])
	world.save_manager.load_game()
	_check(inv.count_of("hoe_2") == 1 and inv.count_of("pickaxe_2") == 1 and WateringCan.water_left(inv, can_slot) == can2.capacity, "강화 도구 저장·불러오기")

	# 정리
	for k in 3:
		farm.tiles.erase(start + Vector2i.DOWN * k)
	inv.load_data(saved_inv)
	GameState.money = money0
	GameState.select_slot(0)
	world.player.global_position = world.home_position
	world._apply_camera_area()  # 대장간 안에서 시작한 점검이라 농장 범위로 돌려놓는다
	await get_tree().process_frame


func _test_seasonal_crops(world: FarmWorld, hud: HUD) -> void:
	var farm := world.farm
	var start_day := GameState.day
	# 계절은 기획서 그대로 (경제 기준의 계절 변경은 다음 단계), 숫자는 경제 기준 v1.0 (작물 점검에서 확인)
	var plan := {
		"wheat": ["spring", "summer"], "tomato": ["summer"], "blueberry": ["summer"], "corn": ["summer", "autumn"], "watermelon": ["summer"],
		"sweet_potato": ["autumn"], "eggplant": ["autumn"], "pumpkin": ["autumn"], "radish": ["autumn"],
	}
	var bad := []
	for id: String in plan:
		var sd := ItemDB.get_item(id + "_seed")
		var crop := ItemDB.get_item(id)
		if sd == null or crop == null or sd.grows != id or sd.seasons != plan[id] or crop.sell_price <= 0 or sd.buy_price <= 0:
			bad.append(id)
	_check(bad.is_empty(), "여름·가을 작물 9종 (계절·값) %s" % [bad])
	var mult: Dictionary = _econ().quality.multipliers
	var q_ok := true
	for id: String in ["tomato", "blueberry", "watermelon", "pumpkin"]:
		var it := ItemDB.get_item(id)
		q_ok = q_ok and Quality.ids().map(func(q: String) -> int: return Pricing.quality_price(it, q)) == Quality.ids().map(func(q: String) -> int: return floori(it.sell_price * float(mult[q]) + 0.0001))
	_check(q_ok, "품질 가격 = 기준가 × 품질 배율 (토마토·블루베리·수박·호박)")
	_check(ItemDB.get_item("golden_pumpkin") == null and ItemDB.get_item("golden_pumpkin_seed") == null, "황금호박 같은 특수작물은 아직 없음")
	var rows := {}
	var art_ok := true
	for id: String in plan:
		var sd := ItemDB.get_item(id + "_seed")
		art_ok = art_ok and not rows.has(sd.crop_row) and (sd.crop_row + 1) * Art.TILE <= Art.CROPS.get_height() 				and (ItemDB.get_item(id).icon + 1) * Art.ICON <= Art.ITEMS.get_width()
		rows[sd.crop_row] = true
	_check(art_ok, "작물 그림 줄·아이콘이 그림 파일 안에 있음")

	# 상점: 지금 계절에 심을 수 있는 씨앗만
	var shop_seeds := func(day: int) -> Array:
		var ids := []
		for it: ItemDef in ItemDB.shop_items():
			if it.kind == ItemDef.Kind.SEED and Calendar.in_season_for_shop(it, day):
				ids.append(it.grows)
		ids.sort()
		return ids
	_check(shop_seeds.call(1) == ["cabbage", "carrot", "lettuce", "potato", "strawberry", "wheat"], "봄 상점 씨앗 (양배추·양상추 포함) %s" % [shop_seeds.call(1)])
	_check(shop_seeds.call(29) == ["blueberry", "corn", "tomato", "watermelon", "wheat"], "여름 상점 씨앗 %s" % [shop_seeds.call(29)])
	_check(shop_seeds.call(57) == ["corn", "eggplant", "pumpkin", "radish", "sweet_potato"], "가을 상점 씨앗 %s" % [shop_seeds.call(57)])
	_check(shop_seeds.call(85) == ["broccoli", "spinach", "sugar_beet"] and ItemDB.shop_items().any(func(it: ItemDef) -> bool: return it.kind == ItemDef.Kind.FERTILIZER and Calendar.in_season_for_shop(it, 85)), "겨울 상점은 겨울 작물 씨앗만 %s (비료는 판매)" % [shop_seeds.call(85)])
	GameState.day = 29
	Events.shop_requested.emit("buy")
	var names := hud._shop._buy_list.get_children().map(func(r: Node) -> String: return r.get_child(1).text)
	_check("토마토 씨앗" in names and not "당근 씨앗" in names and "기본 비료" in names, "상점 창도 여름 씨앗만 진열")
	hud._close_panels()

	# 심기: 제철이 아닌 씨앗은 막고, 여러 계절 작물은 허용된 계절 모두
	var cells := []
	for c: Vector2i in farm.farmable_cells.keys():
		if cells.size() >= 3:
			break
		if not world.obstacles.is_blocked(c) and not world.build.is_occupied(c) and not farm.tiles.has(c):
			cells.append(c)
	for c: Vector2i in cells:
		farm.till(c)
	var a: Vector2i = cells[0]
	var b: Vector2i = cells[1]
	var corn_c: Vector2i = cells[2]
	_check(not farm.plant(a, ItemDB.get_item("carrot_seed")) and not farm.get_tile(a).has_crop(), "여름에는 봄 씨앗(당근)을 심을 수 없음")
	_check(farm.plant(a, ItemDB.get_item("tomato_seed")) and farm.plant(b, ItemDB.get_item("wheat_seed")) and farm.plant(corn_c, ItemDB.get_item("corn_seed")), "여름 씨앗·밀(봄여름)·옥수수(여름가을) 심기")

	# 토마토: 다 자라면 열리고, 재수확 주기마다 다시
	var ts := ItemDB.get_item("tomato_seed")
	farm.get_tile(a).days_grown = ts.grow_days
	var got := farm.harvest(a)
	_check(got.get("id") == "tomato" and got.count >= 1 and got.count <= 3 and farm.get_tile(a).regrowing, "토마토 수확 (%d개), 포기 남음" % got.get("count", 0))
	farm.get_tile(a).days_grown = ts.regrow_days
	_check(farm.get_tile(a).is_mature(), "%d일 뒤 다시 열림" % ts.regrow_days)

	# 옥수수는 여름 → 가을 살아남고, 가을 → 겨울에 시듦. 밀은 가을에 시듦
	farm.change_season("autumn")
	_check(not farm.get_tile(corn_c).withered and farm.get_tile(b).withered and farm.get_tile(a).withered, "가을: 옥수수는 살아 있고, 밀·토마토는 시듦")
	GameState.day = 57
	_check(farm.plant(cells[0], ItemDB.get_item("corn_seed")) == false, "시든 작물이 있는 칸에는 못 심음")
	farm.change_season("winter")
	_check(farm.get_tile(corn_c).withered, "겨울: 옥수수도 시듦")

	for c: Vector2i in cells:
		farm.tiles.erase(c)
	GameState.day = start_day
	await get_tree().process_frame


func _test_drag_and_tooltip(hud: HUD) -> void:
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	inv.load_data([])
	inv.slots[9] = {"id": "potato", "count": 3, "quality": "gold"}
	inv.slots[10] = {"id": "potato", "count": 4, "quality": "gold"}
	inv.slots[11] = {"id": "potato", "count": 2, "quality": "silver"}
	inv.slots[12] = {"id": "hoe", "count": 1, "quality": ""}
	inv.slots[13] = {"id": "potato", "count": 98, "quality": "gold"}
	inv.move(9, 10)
	_check(inv.get_slot(9) == null and inv.get_slot(10).count == 7, "같은 물건·같은 품질은 합쳐짐")
	inv.move(11, 10)
	_check(inv.get_slot(10).quality == "silver" and inv.get_slot(11).quality == "gold" and inv.get_slot(11).count == 7, "품질이 다르면 합치지 않고 자리 바꿈")
	inv.move(11, 13)
	_check(inv.get_slot(13).count == 99 and inv.get_slot(11).count == 6, "가득 차면 넘치는 만큼은 원래 칸에 남음")
	inv.move(12, 0)
	_check(inv.get_slot(0) != null and inv.get_slot(0).id == "hoe" and inv.get_slot(12) == null, "가방 → 핫바로 옮기기")
	inv.move(0, 20)
	_check(inv.get_slot(20).id == "hoe" and inv.get_slot(0) == null, "핫바 → 가방으로 옮기기")

	# 칸의 끌어다 놓기 (가방 창 ↔ 화면 아래 핫바)
	hud.open_inventory()
	await get_tree().process_frame
	var bag: Array[ItemSlot] = hud._inventory._slots
	var bar: Array[ItemSlot] = hud._hotbar._slots
	_check(bag[20].drag_data() == {"from": 20} and bag[5].drag_data() == null, "물건 칸만 끌 수 있음")
	_check(bar[3]._can_drop_data(Vector2.ZERO, bag[20].drag_data()), "핫바 칸에 놓을 수 있음")
	bar[3]._drop_data(Vector2.ZERO, bag[20].drag_data())
	_check(inv.get_slot(3) != null and inv.get_slot(3).id == "hoe" and inv.get_slot(20) == null, "가방 창의 칸을 화면 핫바에 놓기")
	bag[25]._drop_data(Vector2.ZERO, bar[3].drag_data())
	_check(inv.get_slot(25) != null and inv.get_slot(25).id == "hoe" and inv.get_slot(3) == null, "핫바 칸을 가방 창에 놓기")
	_check(hud._inventory.get("_info") == null, "가방 창 아래 고정 설명 칸 없음")

	# 실제 마우스로 끌기: 누르기 → 움직이기 → 놓기
	var from_c := bag[13].get_global_rect().get_center()
	var to_c := bag[22].get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from_c
	press.global_position = from_c
	get_viewport().push_input(press, true)
	for k in range(1, 9):
		var motion := InputEventMouseMotion.new()
		motion.position = from_c.lerp(to_c, k / 8.0)
		motion.global_position = motion.position
		motion.relative = (to_c - from_c) / 8.0
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(motion, true)
		await get_tree().process_frame
	var release := press.duplicate()
	release.pressed = false
	release.position = to_c
	release.global_position = to_c
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	_check(inv.get_slot(22) != null and inv.get_slot(22).count == 99 and inv.get_slot(13) == null, "마우스로 끌어다 놓기 (실제 입력)")

	# 툴팁
	inv.slots[2] = {"id": "tomato_seed", "count": 5, "quality": ""}
	inv.slots[4] = {"id": "watering_can", "count": 1, "quality": "", "water": 5}
	inv.changed.emit()
	await get_tree().process_frame
	Events.item_hover_changed.emit(bag[2])
	var tip := hud._item_tip
	var texts := tip._body.get_children().map(func(l: Label) -> String: return l.text)
	_check(tip.visible and tip._title.text == "토마토 씨앗", "마우스를 올리면 커서 옆 툴팁")
	var tsd := ItemDB.get_item("tomato_seed")
	var need := ["성장 %d일" % tsd.grow_days, "다시 열림: %d일마다" % tsd.regrow_days, "수확량 %d~%d개" % [tsd.yield_min, tsd.yield_max], "계절: 여름", "씨앗 가격 %d G" % tsd.buy_price, "토마토 기본 판매가 %d G" % ItemDB.get_item("tomato").sell_price]
	_check(need.all(func(t: String) -> bool: return t in texts), "씨앗 툴팁: 성장·다시 열림·수확량·계절·씨앗 가격·판매가 %s" % [texts])
	var can_lines := ItemTooltip.lines(ItemDB.get_item("watering_can"), "", 5).map(func(l: Array) -> String: return l[0])
	_check("등급 1" in can_lines and "물 5 / 12" in can_lines and "대장간에서 강화할 수 있어요" in can_lines, "도구 툴팁: 등급·물·강화 가능")
	var hoe2_lines := ItemTooltip.lines(ItemDB.get_item("hoe_2")).map(func(l: Array) -> String: return l[0])
	_check("등급 2" in hoe2_lines and "꾹 누르기: 3칸 (1초마다)" in hoe2_lines, "구리 도구 툴팁: 등급·꾹 누르기 범위")
	var crop_lines := ItemTooltip.lines(ItemDB.get_item("potato"), "gold").map(func(l: Array) -> String: return l[0])
	var pg := Pricing.quality_price(ItemDB.get_item("potato"), "gold")
	_check("기준가 %d G" % pg in crop_lines and "출하함 %d G · 광장 %d G" % [pg, Pricing.unit_price(ItemDB.get_item("potato"), "gold", Pricing.PLAZA)] in crop_lines, "작물 툴팁: 품질 기준가·판매 방식별 가격 (골드 감자 %d G)" % pg)
	var fert_lines := ItemTooltip.lines(ItemDB.get_item("premium_fertilizer")).map(func(l: Array) -> String: return l[0])
	var pc: Dictionary = _econ().quality.harvest_chances.premium
	_check("수확 품질: 브론즈 %d%% · 실버 %d%% · 골드 %d%%" % [int(pc.bronze), int(pc.silver), int(pc.gold)] in fert_lines, "비료 툴팁: 품질 확률")
	Events.item_hover_changed.emit(null)
	_check(not tip.visible, "칸에서 벗어나면 툴팁 숨김")
	_check(CursorTooltip.position_for(Vector2(100, 100), Vector2(200, 80), Vector2(1280, 720)) == Vector2(122, 122) 			and CursorTooltip.position_for(Vector2(1260, 700), Vector2(200, 80), Vector2(1280, 720)) == Vector2(1038, 598), "화면 밖으로 나가면 반대쪽으로 뒤집기")
	Events.item_hover_changed.emit(bag[2])
	hud._close_panels()
	await get_tree().process_frame
	_check(not tip.visible, "가방을 닫으면 툴팁도 숨김")

	inv.load_data(saved_inv)
	await get_tree().process_frame


func _test_daily_special(world: FarmWorld, hud: HUD) -> void:
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var money0 := GameState.money
	var ids: Array = DailySpecial._candidates().keys()
	_check(ids.size() >= 3 and ids.all(func(id: String) -> bool: return DailySpecial.price_of(id) > 0 and not DailySpecial.items_of(id).is_empty()), "특별 상품 후보 %d개 (shop_specials.json)" % ids.size())
	var spring := DailySpecial.available_on(1)
	var winter := DailySpecial.available_on(85)
	_check("spring_seed_pack" in spring and not "summer_seed_pack" in spring and "basic_fertilizer_bundle" in spring, "계절 후보: 봄에는 봄 씨앗 꾸러미")
	_check(not winter.any(func(id: String) -> bool: return id.ends_with("_seed_pack")) and not winter.is_empty(), "겨울에는 씨앗 꾸러미 없음")
	_check(DailySpecial.exists(GameState.daily_special), "지금 특별 상품이 있음 (%s)" % DailySpecial.name_of(GameState.daily_special))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var same := 0
	for i in 50:
		if DailySpecial.pick(1, rng, "basic_fertilizer_bundle") == "basic_fertilizer_bundle":
			same += 1
	_check(same == 0, "어제와 같은 상품은 고르지 않음")

	# 하루가 지나면 새 상품 (하루 마감 shop_refresh 단계)
	var before := GameState.daily_special
	GameState.sleep()
	hud._close_panels()
	var r: Dictionary = world.day_cycle.last_report
	_check(r.get("shop_special") == GameState.daily_special and GameState.daily_special != before and DailySpecial.exists(GameState.daily_special), "하루가 지나면 새 특별 상품 (%s → %s)" % [DailySpecial.name_of(before), DailySpecial.name_of(GameState.daily_special)])

	# 상점에 한 줄 (씨앗 상점에서만)
	GameState.daily_special = "basic_fertilizer_bundle"
	Events.shop_requested.emit("buy")
	var special_texts := []
	for row in hud._shop._special_box.get_children():
		if row is Label:
			special_texts.append(row.text)
		else:
			for c in row.get_children():
				if c is VBoxContainer:
					special_texts.append(c.get_child(0).text)
	_check(hud._shop._special_box.visible and "기본 비료 묶음" in special_texts, "씨앗 상점에 오늘의 특별 상품 표시")
	hud._close_panels()
	Events.shop_requested.emit("sell")
	_check(not hud._shop._special_box.visible, "작물 판매처에는 특별 상품 없음")
	hud._close_panels()

	# 사기: 수량 제한 없음, 돈·가방 확인
	inv.load_data([])
	GameState.money = 1000
	_check(DailySpecial.regular_price("basic_fertilizer_bundle") == 250 and DailySpecial.price_of("basic_fertilizer_bundle") < 250, "묶음이 따로 사는 것보다 쌈 (250 G → %d G)" % DailySpecial.price_of("basic_fertilizer_bundle"))
	var ok1: bool = DailySpecial.buy("basic_fertilizer_bundle", inv).ok
	var ok2: bool = DailySpecial.buy("basic_fertilizer_bundle", inv).ok
	_check(ok1 and ok2 and GameState.money == 1000 - 2 * DailySpecial.price_of("basic_fertilizer_bundle") and inv.count_of("basic_fertilizer") == 10, "여러 번 살 수 있음 (수량 제한 없음)")
	GameState.money = 50
	_check(not DailySpecial.buy("basic_fertilizer_bundle", inv).ok and GameState.money == 50 and inv.count_of("basic_fertilizer") == 10, "돈이 모자라면 못 삼")
	GameState.money = 1000
	for i in inv.size():
		if inv.get_slot(i) == null:
			inv.slots[i] = {"id": "carrot", "count": 99, "quality": "gold"}
	_check(not DailySpecial.buy("building_material_bundle", inv).ok and GameState.money == 1000, "가방에 다 안 들어가면 사지 않음 (돈 그대로)")

	# 저장
	GameState.daily_special = "advanced_fertilizer_deal"
	inv.load_data(saved_inv)
	world.save_manager.save_game("manual")
	GameState.daily_special = "basic_fertilizer_bundle"
	world.save_manager.load_game()
	_check(GameState.daily_special == "advanced_fertilizer_deal", "오늘의 특별 상품 저장·불러오기")

	inv.load_data(saved_inv)
	GameState.money = money0
	await get_tree().process_frame


func _test_greenhouse(world: FarmWorld, hud: HUD) -> void:
	var farm := world.farm
	var grid := world.build
	var bm := world.build_mode
	var inv := GameState.inventory
	var start_day := GameState.day
	var saved_inv := inv.to_data()
	var def := PlaceableDB.get_def("greenhouse")
	_check(def != null and def.size == Vector2i(8, 7) and not def.rotatable and def.materials == {"wood": 100, "stone": 100} and def.price == 3000, "온실 정의 (8x7, 3000 G + 나무 100 + 돌 100, 회전 없음)")
	_check(def.cost_text() == "3000 G + 나무 100 + 돌 100", "건설비 글자 (%s)" % def.cost_text())

	# 온실 자리: 장애물만 치우면 지을 수 있는 농장 땅
	var origin := Vector2i(-1, -1)
	var cells: Array = farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for fc in Placeable.footprint_of(def, c):
			if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or (farm.get_tile(fc) != null and farm.get_tile(fc).has_crop()):
				ok = false
				break
		if ok:
			origin = c
			break
	_check(origin.x >= 0, "온실 지을 자리 찾음 %s" % origin)
	for fc in Placeable.footprint_of(def, origin):
		world.obstacles.remove(fc)
	world.player.global_position = world.cell_center(_find_char("s"))

	# 재료가 모자라면 못 지음 (돈도 그대로)
	inv.remove("wood", inv.count_of("wood"))
	inv.remove("stone", inv.count_of("stone"))
	GameState.add_money(5000)
	var money := GameState.money
	bm.start_place("greenhouse")
	_check(not bm.try_place(origin) and GameState.money == money and grid.object_at(origin) == null, "재료가 모자라면 온실을 못 지음")
	inv.add("wood", 100)
	inv.add("stone", 120)
	_check(bm.try_place(origin), "온실 짓기")
	bm.stop()
	var gh := grid.object_at(origin) as Greenhouse
	_check(gh != null and GameState.money == money - 3000 and inv.count_of("wood") == 0 and inv.count_of("stone") == 20, "돈·재료를 냄 (남은 돌 %d)" % inv.count_of("stone"))
	_check(gh.indoor_cells().size() == 30 and farm.indoor_cells.size() == 30, "안쪽 밭 6x5 = 30칸")
	var inside: Vector2i = origin + Vector2i(1, 1)
	var corner: Vector2i = origin + Vector2i(6, 5)
	var wall: Vector2i = origin + Vector2i(0, 3)
	var door: Vector2i = gh.door_cells()[0]
	_check(gh.door_cells() == [origin + Vector2i(3, 6), origin + Vector2i(4, 6)], "앞벽 가운데 문 2칸")
	_check(farm.till(inside) and farm.till(corner), "온실 안쪽은 괭이로 갈 수 있음")
	_check(not farm.till(wall) and not farm.till(door), "벽·문 칸은 못 갊")
	_check(not grid.check(PlaceableDB.get_def("scarecrow"), origin + Vector2i(2, 2)).ok, "온실 안에는 다른 시설을 못 놓음")
	_check(gh.y_sort_enabled and gh._pieces.size() == 4 and not gh._sprite.visible, "벽 그림을 4조각으로 나눠 Y 정렬")

	# 겨울: 바깥에는 못 심지만 온실 안에는 어떤 계절 작물이든 심음
	GameState.day = 85
	var out_c := _free_clear_cell(world)
	farm.till(out_c)
	_check(not farm.plant(out_c, ItemDB.get_item("spinach_seed")), "겨울 작물도 바깥 밭에는 못 심음")
	_check(farm.plant(inside, ItemDB.get_item("spinach_seed")), "겨울에 온실에서 시금치 심기")
	_check(farm.plant(corner, ItemDB.get_item("carrot_seed")), "겨울에 온실에서 봄 작물(당근)도 심기")
	_check(Calendar.greenhouse_only(ItemDB.get_item("spinach_seed")) and not Calendar.greenhouse_only(ItemDB.get_item("carrot_seed")), "온실 전용 씨앗 구분")
	var tip := ItemTooltip.lines(ItemDB.get_item("broccoli_seed"))
	_check(tip.any(func(l: Array) -> bool: return str(l[0]) == "계절: 겨울 (온실 전용)"), "툴팁: 겨울 (온실 전용)")

	# 비는 온실 안을 적시지 않음
	var r := farm.water_outdoor()
	_check(r >= 1 and farm.get_tile(out_c).watered and not farm.get_tile(inside).watered, "비는 바깥 밭만 적심 (온실 안은 그대로)")
	farm.tiles.erase(out_c)
	farm.till(out_c)
	GameState.weather = "rain"
	var in_empty: Vector2i = origin + Vector2i(3, 3)
	farm.till(in_empty)
	_check(farm.get_tile(out_c) != null and not farm.get_tile(in_empty).watered, "비 오는 날 새로 간 온실 밭은 마른 채")
	GameState.weather = "sunny"
	farm.tiles.erase(out_c)

	# 물 주면 자람 (4일이면 시금치 수확)
	for d in 4:
		farm.water(inside)
		farm.water(corner)
		farm.process_day()
	_check(farm.get_tile(inside).is_mature(), "온실 시금치 4일 만에 다 자람")
	farm.rng.seed = 3
	var got := farm.harvest(inside)
	_check(got.get("id") == "spinach" and int(got.get("count", 0)) == 1, "시금치 수확 %s" % got)

	# 계절이 바뀌어도 온실 작물은 시들지 않고, 빈 마른 밭도 되돌아가지 않음
	var saved_chance: Variant = Calendar._cfg().get("soil_revert_chance")
	Calendar._data["soil_revert_chance"] = 1.0
	farm.change_season("spring")
	farm.change_season("summer")
	_check(not farm.get_tile(corner).withered, "계절이 바뀌어도 온실 작물은 안 시듦")
	_check(farm.tiles.has(inside) and farm.tiles.has(in_empty), "온실 빈 밭은 계절이 바뀌어도 그대로")
	Calendar._data["soil_revert_chance"] = saved_chance

	# 벽은 못 지나가고, 문으로는 들어감
	var player := world.player
	var left_of_wall := world.cell_center(origin + Vector2i(-1, 3))
	player.global_position = left_of_wall
	for i in 30:
		player.velocity = Vector2(240, 0)
		player.move_and_slide()
	_check(world.world_to_cell(player.global_position).x < origin.x, "온실 옆벽에 막힘")
	# 문 앞 칸에 장애물이 다시 자라 있으면 그 안에서 시작해 옆으로 밀려나므로 치우고, 문 칸 가운데에서 출발한다
	for d in gh.door_cells():
		world.obstacles.remove(d + Vector2i.DOWN)
	# 치운 장애물 노드(충돌체)는 프레임이 끝나야 사라진다
	await get_tree().process_frame
	await get_tree().physics_frame
	player.global_position = world.cell_center(door + Vector2i.DOWN)
	for i in 30:
		player.velocity = Vector2(0, -240)
		player.move_and_slide()
	var in_cell := world.world_to_cell(player.global_position)
	_check(farm.is_indoor(in_cell) and in_cell.y == origin.y + 1, "문으로 들어가 뒷벽 앞까지 걸어감 (%s)" % in_cell)

	# 저장 / 불러오기: 온실과 안의 작물이 그대로
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	gh = grid.object_at(origin) as Greenhouse
	_check(gh != null and farm.indoor_cells.size() == 30 and farm.get_tile(corner) != null and farm.get_tile(corner).seed_id == "carrot_seed", "온실·안의 작물 저장·불러오기")

	# 안에 작물이 있으면 옮기기·철거 불가
	bm.start(BuildMode.Mode.REMOVE)
	money = GameState.money
	_check(not bm.try_remove(origin) and grid.object_at(origin) == gh and GameState.money == money, "작물이 있으면 철거 불가")
	bm.start(BuildMode.Mode.MOVE)
	_check(not bm.pick(origin + Vector2i(2, 2)), "작물이 있으면 옮기기 불가")
	farm.remove_crop(corner)
	bm.start(BuildMode.Mode.REMOVE)
	var stone := inv.count_of("stone")
	_check(bm.try_remove(origin + Vector2i(2, 2)) and grid.object_at(origin) == null, "작물을 뽑으면 철거 가능")
	_check(GameState.money == money + 3000 and inv.count_of("wood") == 100 and inv.count_of("stone") == stone + 100, "철거하면 돈·재료 돌려받음")
	_check(farm.indoor_cells.is_empty() and not farm.tiles.has(corner) and not farm.tiles.has(inside), "철거하면 온실 밭은 보통 땅")
	bm.stop()

	# 정리
	GameState.day = start_day
	inv.load_data(saved_inv)
	hud._close_panels()
	await get_tree().process_frame


func _test_compost(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var bm := world.build_mode
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var player := world.player
	var def := PlaceableDB.get_def("compost_bin")
	_check(def != null and def.size == Vector2i(2, 1) and def.cost_text() == "200 G + 나무 30", "퇴비통 정의 (2x1, %s)" % (def.cost_text() if def else ""))

	# 짓기 (기존 건설 규칙: 돈 + 재료)
	var origin := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for fc in Placeable.footprint_of(def, c) + [c + Vector2i(0, 1), c + Vector2i(1, 1), c + Vector2i(0, 2)]:
			if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or world.farm.tiles.has(fc):
				ok = false
		if ok:
			origin = c
			break
	for fc in [origin, origin + Vector2i(1, 0), origin + Vector2i(0, 1), origin + Vector2i(1, 1), origin + Vector2i(0, 2), origin + Vector2i(1, 2)]:
		world.obstacles.remove(fc)
	player.global_position = world.cell_center(_find_char("s"))
	inv.remove("wood", inv.count_of("wood"))
	inv.add("wood", 30)
	GameState.add_money(500)
	bm.start_place("compost_bin")
	_check(bm.try_place(origin) and inv.count_of("wood") == 0, "퇴비통 짓기 (나무 30 사용)")
	bm.stop()
	var bin := grid.object_at(origin) as CompostBin
	_check(bin != null and bin.is_empty() and bin.days_needed() == 3 and bin.batch_points_needed() == 10, "퇴비통: 10점 → 3일 → 기본 비료 1개 (데이터)")

	# [E] 로 창 열기 (시간 정지)
	player.global_position = bin.interact_point()
	await get_tree().physics_frame
	_check(player._nearest_interactable() == bin, "퇴비통 앞에서 [E] 안내")
	player._interact()
	_check(hud._compost.visible and get_tree().paused and GameState.is_time_paused(), "퇴비통 창 열면 게임·시간 멈춤")
	_check(hud._compost._bag_list.get_child_count() >= 1, "창에 가방 재료 목록")
	hud._close_panels()
	_check(not get_tree().paused, "닫으면 재개")

	# 넣기: 받는 재료만, 점수 한도까지
	inv.remove("fiber", inv.count_of("fiber"))
	inv.add("fiber", 80)
	inv.add("carrot", 3, "silver")
	inv.add("pumpkin", 1, "gold")
	_check(bin.deposit(inv, "pumpkin", "gold", 1) == 0 and inv.count_of("pumpkin", "gold") == 1, "값비싼 작물(호박)은 안 받음")
	_check(bin.deposit(inv, "fiber", "", 7) == 7 and inv.count_of("fiber") == 73 and not bin.is_working(), "섬유 7개(7점) 넣기 → 아직 시작 안 함")
	_check(bin.withdraw(inv, "fiber", "", 2) == 2 and bin.waiting_points() == 5 and inv.count_of("fiber") == 75, "익기 전 재료는 다시 꺼냄")
	bin.deposit(inv, "fiber", "", 2)
	_check(bin.deposit(inv, "carrot", "silver", 2) == 2 and bin.is_working() and bin.waiting.is_empty(), "당근(실버) 2개(4점) 더해 11점 → 한 번 분량 익히기 시작")
	_check(bin.batch.any(func(st: Dictionary) -> bool: return st.id == "carrot" and st.quality == "silver"), "익히는 재료에 품질 그대로")
	_check(bin.deposit(inv, "fiber", "", 80) == 50 and bin.waiting_points() == 50, "대기 재료는 최대 50점까지만 (나머지는 가방에)")
	_check(bin.withdraw(inv, "fiber", "", 40) == 40, "대기 재료 40개 꺼냄 (10점 남김)")

	# 하루 단위로 익음 (하루 마감 farm_daily 단계)
	var fert_start := inv.count_of("basic_fertilizer")
	GameState.sleep()
	hud._close_panels()
	bin = grid.object_at(origin) as CompostBin
	_check(bin.batch_days == 1 and bin.output == 0, "하루 지나면 1/3일")
	GameState.sleep()
	hud._close_panels()
	GameState.sleep()
	hud._close_panels()
	var report: Dictionary = world.day_cycle.last_report
	_check(bin.output == 1 and int(report.get("compost", 0)) == 1, "3일 뒤 기본 비료 1개가 퇴비통 안에 생김 (report.compost)")
	_check(int(report.get("night_production", {}).get("items", {}).get("basic_fertilizer", 0)) == 1, "야간 생산 결과에 기본 비료 +1")
	_check(bin.is_working() and bin.batch_days == 0 and bin.waiting.is_empty(), "대기 재료 10점으로 다음 분량 바로 시작")
	_check(inv.count_of("basic_fertilizer") == fert_start, "결과물은 저절로 가방에 들어가지 않음 (직접 꺼냄)")
	var fert_before := inv.count_of("basic_fertilizer")

	# 저장 / 불러오기: 대기 재료·진행 일수·결과물
	bin.deposit(inv, "fiber", "", 4)
	GameState.sleep()
	hud._close_panels()
	bin = grid.object_at(origin) as CompostBin
	var state := bin.save_state()
	world.save_manager.save_game("manual")
	bin.take_contents()
	world.save_manager.load_game()
	bin = grid.object_at(origin) as CompostBin
	_check(bin != null and bin.save_state() == state and bin.output == 1 and bin.batch_days == 1 and bin.waiting_points() == 4, "퇴비통 상태 저장·불러오기 %s" % state)

	# 가방이 꽉 차면 결과물은 퇴비통에 그대로
	_check(bin.take_output(Inventory.new(0)) == 0 and bin.output == 1, "가방에 자리가 없으면 결과물이 그대로 남음")
	_check(bin.take_output(inv) == 1 and bin.output == 0 and inv.count_of("basic_fertilizer") == fert_before + 1, "결과물 직접 꺼내기")

	# 결과물 칸이 가득 차면 다 익은 퇴비는 기다림 (사라지지 않음)
	bin.output = bin.max_output()
	bin.batch_days = bin.days_needed() - 1
	bin.on_day_end(world, {})
	_check(bin.is_done() and bin.output == bin.max_output(), "결과물 칸이 가득 차면 다 익은 퇴비는 대기")
	var taken := bin.take_output(inv)
	_check(taken == bin.max_output() and bin.output == bin.output_per_batch() and not bin.is_done(), "꺼내면 기다리던 퇴비가 바로 채워짐")
	bin.take_output(inv)

	# 옮겨도 내용물 유지
	bin.deposit(inv, "fiber", "", 3)
	state = bin.save_state()
	# 밤새 다시 자란 장애물이 있을 수 있어 옮길 자리를 치운다
	world.obstacles.remove(origin + Vector2i(0, 1))
	world.obstacles.remove(origin + Vector2i(1, 1))
	bm.start(BuildMode.Mode.MOVE)
	_check(bm.pick(origin), "퇴비통 집기")
	_check(bm.try_drop(origin + Vector2i(0, 1)) and grid.object_at(origin + Vector2i(0, 1)) == bin and bin.save_state() == state, "옮겨도 안의 재료·진행 유지")
	origin += Vector2i(0, 1)

	# 철거: 가방에 자리가 없으면 막고, 있으면 안의 물건 + 재료 모두 돌려받음
	bm.start(BuildMode.Mode.REMOVE)
	var filler := 99 * inv.size()
	var left := inv.add("stone", filler)
	var added := filler - left
	_check(not bm.try_remove(origin) and grid.object_at(origin) == bin, "가방이 꽉 차면 철거 불가 (내용물 보호)")
	inv.remove("stone", added)
	var expect := {}
	for st: Dictionary in bin.contents():
		expect[st.id + "|" + st.quality] = inv.count_of(st.id, st.quality) + int(st.count)
	var money := GameState.money
	_check(bm.try_remove(origin) and grid.object_at(origin) == null, "퇴비통 철거")
	var all_back := true
	for key: String in expect:
		var parts := key.split("|")
		all_back = all_back and inv.count_of(parts[0], parts[1]) == expect[key]
	_check(all_back and inv.count_of("wood") == 30 and GameState.money == money + 200, "철거하면 안의 재료·익히던 재료·결과물·건설비 모두 돌려받음")
	bm.stop()

	inv.load_data(saved_inv)
	hud._close_panels()
	await get_tree().process_frame


func _test_warehouse(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var bm := world.build_mode
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var player := world.player
	var def := PlaceableDB.get_def("warehouse")
	var wh_item := ItemDB.get_item("warehouse")
	_check(def != null and def.size == Vector2i(4, 4) and def.machine_item() == wh_item and wh_item.buy_price == int(_econ().machines.warehouse) and wh_item.buy_materials == {"wood": 80, "stone": 40}, "창고 정의 (4x4, 기계상점 %d G + 나무 80 + 돌 40)" % wh_item.buy_price)

	# 짓기: 4x4 + 앞에 설 한 줄이 비어 있는 자리
	var origin := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 5:
			for x in 4:
				var fc := c + Vector2i(x, y)
				if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or world.farm.tiles.has(fc):
					ok = false
		if ok:
			origin = c
			break
	_check(origin.x >= 0, "창고 지을 자리 찾음 %s" % origin)
	for y in 5:
		for x in 4:
			world.obstacles.remove(origin + Vector2i(x, y))
	await get_tree().process_frame
	player.global_position = world.cell_center(_find_char("s"))
	inv.remove("wood", inv.count_of("wood"))
	inv.remove("stone", inv.count_of("stone"))
	bm.start_place("warehouse")
	_check(not bm.try_place(origin), "가방에 창고가 없으면 못 놓음")
	_buy_machine(hud, "warehouse")
	_check(inv.count_of("wood") == 0 and inv.count_of("stone") == 0 and inv.count_of("warehouse") == 1, "기계상점에서 창고 사기 (나무 80 + 돌 40 사용)")
	_check(bm.try_place(origin) and inv.count_of("warehouse") == 0, "가방의 창고를 설치")
	bm.stop()
	var wh := grid.object_at(origin) as Warehouse
	_check(wh != null and wh.is_empty() and wh.slot_count() == 36 and wh.storage.size() == 36 and wh.filter_mode == "all", "창고: 처음 36칸, 필터 전체")

	# [E] 로 창 열기 (시간 정지)
	player.global_position = wh.interact_point()
	await get_tree().physics_frame
	_check(player._nearest_interactable() == wh, "창고 앞에서 [E] 안내")
	player._interact()
	var panel := hud._warehouse
	_check(panel.visible and get_tree().paused and GameState.is_time_paused(), "창고 창 열면 게임·시간 멈춤")
	_check(panel._store_slots.size() == 36 and panel._bag_slots.size() == inv.size(), "창에 창고 36칸 + 가방 칸")

	# 앞 점검의 수확 품질은 무작위라 개수를 세는 묶음은 비우고 시작한다
	for st: Array in [["carrot", "silver"], ["potato", "gold"], ["tomato", "silver"]]:
		inv.remove(st[0], inv.count_of(st[0], st[1]), st[1])

	# 창에서 클릭으로 옮기기: 클릭 = 한 묶음, 우클릭 = 1개
	inv.add("carrot", 5, "silver")
	panel._on_bag_right_clicked(_slot_index(inv, "carrot", "silver"))
	_check(wh.storage.count_of("carrot", "silver") == 1 and inv.count_of("carrot", "silver") == 4, "가방 칸 우클릭 → 1개만 창고로 (품질 유지)")
	panel._on_bag_clicked(_slot_index(inv, "carrot", "silver"))
	_check(wh.storage.count_of("carrot", "silver") == 5 and inv.count_of("carrot", "silver") == 0, "가방 칸 클릭 → 한 묶음 창고로")
	panel._on_store_right_clicked(_slot_index(wh.storage, "carrot", "silver"))
	_check(wh.storage.count_of("carrot", "silver") == 4 and inv.count_of("carrot", "silver") == 1, "창고 칸 우클릭 → 1개 꺼내기")
	_check(panel._title.text.contains("1/36"), "창 제목에 사용 칸 표시 (%s)" % panel._title.text)

	# 물뿌리개 같은 상태 있는 물건은 상태 그대로 보관
	var can_i := _slot_index(inv, "watering_can", "")
	if can_i < 0:
		inv.add("watering_can")
		can_i = _slot_index(inv, "watering_can", "")
	inv.set_slot_value(can_i, "water", 3)
	_check(wh.deposit_slot(inv, can_i) == 1 and int(wh.storage.slot_value(_slot_index(wh.storage, "watering_can", ""), "water", -1)) == 3, "물뿌리개는 남은 물 그대로 보관")
	_check(wh.withdraw_slot(inv, _slot_index(wh.storage, "watering_can", "")) == 1 and int(inv.slot_value(_slot_index(inv, "watering_can", ""), "water", -1)) == 3, "꺼내도 남은 물 그대로")

	# 필터: 작물만 → 재료는 안 받음. 이미 든 물건은 그대로 두고 꺼낼 수 있다
	inv.add("wood", 10)
	wh.deposit_slot(inv, _slot_index(inv, "wood", ""))
	_check(wh.storage.count_of("wood") == 10, "필터 전체: 나무도 받음")
	panel._on_filter_selected(1)
	_check(wh.filter_mode == "crop" and panel._filter.selected == 1, "필터 선택 → 작물만")
	inv.add("stone", 5)
	_check(wh.deposit_slot(inv, _slot_index(inv, "stone", "")) == 0 and inv.count_of("stone") == 5, "작물만: 돌은 안 받음 (가방에 그대로)")
	_check(panel._bag_slots[_slot_index(inv, "stone", "")].modulate.a < 1.0, "받지 않는 가방 물건은 흐리게")
	inv.add("potato", 2, "gold")
	_check(wh.deposit_slot(inv, _slot_index(inv, "potato", "gold")) == 2, "작물만: 감자(골드)는 받음")
	_check(wh.storage.count_of("wood") == 10 and wh.withdraw_slot(inv, _slot_index(wh.storage, "wood", "")) == 10, "필터를 바꿔도 이미 든 나무는 남아 있고 꺼낼 수 있음")
	wh.set_filter_mode("seed")
	_check(not wh.accepts(ItemDB.get_item("carrot")) and wh.accepts(ItemDB.get_item("carrot_seed")), "씨앗만")
	wh.set_filter_mode("material")
	_check(wh.accepts(ItemDB.get_item("stone")) and not wh.accepts(ItemDB.get_item("basic_fertilizer")), "재료만")
	wh.set_filter_mode("processed")
	_check(not wh.accepts(ItemDB.get_item("carrot")) and not wh.accepts(ItemDB.get_item("wood")), "가공품만 (아직 가공품 없음)")

	# 지정 아이템: [가방에서 고르기] → 가방 칸 클릭으로 추가, 아이콘 누르면 빼기
	wh.set_filter_mode("items")
	_check(panel._pick.visible and not wh.accepts(ItemDB.get_item("carrot")), "지정 아이템 (비어 있으면 아무것도 안 받음)")
	panel._pick.button_pressed = true
	inv.add("carrot", 2)
	var carrots := inv.count_of("carrot", "bronze")
	var carrot_i := _slot_index(inv, "carrot", "bronze")
	var carrot_stack: int = inv.get_slot(carrot_i).count
	panel._on_bag_clicked(carrot_i)
	_check(wh.filter_items.size() == 1 and wh.filter_items[0] == "carrot" and inv.count_of("carrot", "bronze") == carrots, "고르는 중: 가방 칸 클릭 → 필터에 추가 (옮기지 않음)")
	_check(panel._chips.get_child_count() == 1, "필터 아이콘 표시")
	panel._pick.button_pressed = false
	panel._on_bag_clicked(carrot_i)
	_check(wh.storage.count_of("carrot", "bronze") == carrot_stack and wh.insert("potato", 3, "bronze") == 3 and wh.insert("carrot", 3, "bronze") == 0, "지정 아이템: 당근만 받음 (자동 투입 insert 도 같은 규칙)")
	for id: String in ["wood", "stone", "fiber", "potato", "tomato", "corn", "wheat", "radish", "spinach"]:
		wh.add_filter_item(id)
	_check(wh.filter_items.size() == 9 and not wh.add_filter_item("eggplant"), "지정 아이템은 최대 9개")
	(panel._chips.get_child(0) as ItemSlot).clicked.emit(0)
	_check("carrot" not in wh.filter_items, "필터 아이콘 누르면 빠짐")
	wh.set_filter_mode("all")

	# 칸 한도: 가득 차면 들어가는 만큼만, 나머지는 가방에 (아이템이 사라지지 않음)
	var free := wh.storage.free_slots()
	wh.storage.add("fiber", 99 * (free - 1))
	inv.remove("stone", inv.count_of("stone"))
	inv.add("stone", 150)
	wh.deposit_slot(inv, _slot_index(inv, "stone", ""))
	wh.deposit_all(inv)
	_check(wh.storage.free_slots() == 0 and wh.storage.count_of("stone") == 99 and inv.count_of("stone") == 51, "꽉 차면 들어가는 만큼만 (나머지 돌 %d개는 가방에)" % inv.count_of("stone"))
	inv.add("tomato", 1, "silver")
	panel._on_bag_clicked(_slot_index(inv, "tomato", "silver"))
	_check(inv.count_of("tomato", "silver") == 1, "자리 없으면 창에서도 안 옮겨짐")

	# 창고는 따로따로 (다른 창고와 합쳐지지 않음): 새 Warehouse 는 비어 있다
	var other := Warehouse.new()
	other.setup(def, Vector2i(-50, -50))
	_check(other.is_empty() and other.storage != wh.storage, "창고마다 따로 보관")
	other.free()

	# 증축: 돈·재료 → 칸 늘어남, 안의 물건 유지. 마지막 단계가 한도
	var keep := wh.contents()
	GameState.try_spend(GameState.money)
	inv.remove("wood", inv.count_of("wood"))
	inv.remove("stone", inv.count_of("stone"))
	_check(not wh.upgrade(inv) and wh.level == 0, "돈·재료가 없으면 증축 불가")
	_check(panel._upgrade.disabled and panel._upgrade.text.contains("54"), "증축 버튼 비활성 (%s)" % panel._upgrade.text)
	GameState.add_money(1000)
	inv.add("wood", 60)
	inv.add("stone", 60)
	panel._on_upgrade()
	_check(wh.level == 1 and wh.slot_count() == 54 and wh.storage.size() == 54 and GameState.money == 0 and inv.count_of("wood") == 0, "증축 → 54칸 (1000 G + 나무 60 + 돌 60)")
	_check(wh.contents() == keep and wh.storage.free_slots() == 18, "증축해도 안의 물건 그대로, 빈 칸 18개 추가")
	_check(panel._store_slots.size() == 54, "창의 창고 칸도 54칸")
	GameState.add_money(2500)
	inv.add("wood", 120)
	inv.add("stone", 120)
	_check(wh.upgrade(inv) and wh.slot_count() == 72 and not wh.can_upgrade_more() and not wh.upgrade(inv), "최대 72칸, 그 이상 증축 불가 (무한히 커지지 않음)")
	_check(panel._upgrade.disabled and panel._upgrade.text == "최대 크기", "최대 크기 표시")
	hud._close_panels()
	_check(not get_tree().paused and not panel.visible, "닫으면 재개")

	# 저장 / 불러오기: 단계·필터·칸
	wh.set_filter_mode("items")
	wh.add_filter_item("carrot")
	var state := wh.save_state()
	world.save_manager.save_game("manual")
	wh.take_contents()
	wh.set_filter_mode("all")
	world.save_manager.load_game()
	wh = grid.object_at(origin) as Warehouse
	_check(wh != null and wh.save_state() == state and wh.level == 2 and wh.storage.size() == 72 and wh.filter_mode == "items", "창고 저장·불러오기 (단계·필터·칸)")
	wh.set_filter_mode("all")

	# 옮겨도 내용물·단계 유지
	state = wh.save_state()
	for x in 4:
		world.obstacles.remove(origin + Vector2i(x, 4))
	await get_tree().process_frame
	player.global_position = world.cell_center(_find_char("s"))
	bm.start(BuildMode.Mode.MOVE)
	_check(bm.pick(origin), "창고 집기")
	_check(bm.try_drop(origin + Vector2i(0, 1)) and grid.object_at(origin + Vector2i(0, 1)) == wh and wh.save_state() == state, "옮겨도 안의 물건·단계 유지")
	origin += Vector2i(0, 1)

	# 철거: 가방에 자리가 없으면 막고, 있으면 안의 물건 + 건설비 + 증축 비용 모두 돌려받음
	bm.start(BuildMode.Mode.REMOVE)
	_check(not bm.try_remove(origin) and grid.object_at(origin) == wh, "안의 물건이 가방에 다 안 들어가면 철거 불가")
	wh.storage.slots.fill(null)
	wh.storage.add("tomato", 4, "gold")
	inv.load_data([])  # 빈 가방에서 돌려받는 양을 센다
	var tomato_before := 0
	var money := GameState.money
	_check(bm.try_remove(origin) and grid.object_at(origin) == null, "창고 철거")
	var mats_back := inv.count_of("wood") == 60 + 120 and inv.count_of("stone") == 60 + 120 and inv.count_of("warehouse") == 1
	_check(inv.count_of("tomato", "gold") == tomato_before + 4 and mats_back and GameState.money == money + 1000 + 2500, "철거하면 안의 물건 + 창고 아이템 + 증축 비용 모두 돌려받음")
	bm.stop()

	inv.load_data(saved_inv)
	hud._close_panels()
	await get_tree().process_frame


func _test_processor(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var bm := world.build_mode
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var player := world.player
	var def := PlaceableDB.get_def("manual_processor")
	var mp_item := ItemDB.get_item("manual_processor")
	_check(def != null and def.size == Vector2i(2, 2) and def.machine_item() == mp_item and mp_item.buy_price == int(_econ().machines.manual_processor) and mp_item.buy_materials == {"wood": 50, "stone": 30}, "수동 가공기 정의 (2x2, 기계상점 %d G + 나무 50 + 돌 30)" % mp_item.buy_price)

	# 레시피 데이터 (§73): 지금 있는 작물로 만들 수 있는 20개, 기초 6개만 처음부터 앎
	var recipes := RecipeDB.all()
	var known := recipes.filter(func(r: Dictionary) -> bool: return RecipeDB.is_known(r.id)).map(func(r: Dictionary) -> String: return r.id)
	var by_tier := [1, 2, 3].map(func(t: int) -> int: return recipes.filter(func(r: Dictionary) -> bool: return int(r.tier) == t).size())
	_check(recipes.size() == 22 and by_tier == [10, 6, 6], "레시피 22개 = 경제 기준 (하급 10 · 중급 6 · 상급 6, %s)" % [by_tier])
	var econ_r: Dictionary = _econ().recipes
	var rbad := []
	for rid: String in econ_r:
		var er: Dictionary = econ_r[rid]
		var rr := RecipeDB.get_recipe(rid)
		var want_in := {}
		for k: String in er.inputs:
			want_in[k] = int(er.inputs[k])
		if rr.is_empty() or rr.inputs != want_in or int(rr.count) != int(er.count) or int(rr.minutes) != int(er.minutes) or int(rr.tier) != int(er.tier) or int(rr.machine_tier) != int(er.get("machine_tier", er.tier)) or not rr.input_quality.is_empty():
			rbad.append(rid)
		elif not rr.unlocked and int(rr.price) != ItemDB.get_item(rr.output).sell_price * int(rr.count) * int(_econ().recipe_shop.price_per_output_value):
			rbad.append(rid + "(값)")
	_check(rbad.is_empty(), "레시피 재료·개수·시간·등급·가공기·상점 값 = 경제 기준 %s" % [rbad])
	var add_ok := true
	for r: Dictionary in recipes:
		var cost := 0
		for k: String in r.inputs:
			cost += ItemDB.get_item(k).sell_price * int(r.inputs[k])
		add_ok = add_ok and ItemDB.get_item(r.output).sell_price * int(r.count) > cost
	_check(add_ok, "모든 레시피가 재료값보다 비싸게 팔림 (손해 없음)")
	_check(known == ["flour", "dough", "bread", "sugar", "tomato_puree", "potato_snack"], "처음 아는 레시피: 기초 6개 %s" % [known])
	var flour := ItemDB.get_item("flour")
	_check(flour != null and flour.kind == ItemDef.Kind.PROCESSED and flour.has_quality and ShippingBin.accepts(flour), "가공품: 품질 있음, 출하함에 팔 수 있음")
	_check(ItemTooltip.lines(flour, "silver").size() >= 2, "가공품 툴팁에 가격")
	_check(Quality.average({"bronze": 1, "gold": 1}) == "silver" and Quality.average({"bronze": 2, "gold": 1}) == "silver" and Quality.average({"bronze": 3, "silver": 1}) == "bronze", "품질 평균 (반올림)")

	# 짓기: 2x2 + 앞에 설 한 줄
	var origin := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 3:
			for x in 2:
				var fc := c + Vector2i(x, y)
				if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or world.farm.tiles.has(fc):
					ok = false
		if ok:
			origin = c
			break
	for y in 4:
		for x in 2:
			world.obstacles.remove(origin + Vector2i(x, y))
	await get_tree().process_frame
	player.global_position = world.cell_center(_find_char("s"))
	inv.remove("wood", inv.count_of("wood"))
	inv.remove("stone", inv.count_of("stone"))
	_buy_machine(hud, "manual_processor")
	bm.start_place("manual_processor")
	_check(inv.count_of("wood") == 0 and bm.try_place(origin) and inv.count_of("manual_processor") == 0, "수동 가공기를 사서 설치 (나무 50 + 돌 30)")
	bm.stop()
	var pr := grid.object_at(origin) as Processor
	_check(pr != null and pr.is_empty() and not pr.is_automatic() and pr.tier() == 1, "수동 가공기: 자동 아님, 1급")

	# [E] 로 창 열기 (시간 정지)
	player.global_position = pr.interact_point()
	await get_tree().physics_frame
	_check(player._nearest_interactable() == pr, "가공기 앞에서 [E] 안내")
	player._interact()
	var panel := hud._processor
	_check(panel.visible and get_tree().paused and GameState.is_time_paused(), "가공기 창 열면 게임·시간 멈춤")
	_check(panel._list.get_child_count() == RecipeDB.all().size() and panel.selected == "flour", "창에 레시피 %d개, 첫 레시피 선택" % RecipeDB.all().size())
	hud._close_panels()

	# 모르는 레시피는 못 씀 → 배우면 영구 (저장됨)
	inv.add("potato", 3)
	_check(pr.recipe_problem("potato_starch") != "" and pr.start(inv, "potato_starch", 1) == 0, "안 배운 레시피(감자 전분)는 못 돌림")
	_check(RecipeDB.learn("potato_starch") and RecipeDB.is_known("potato_starch") and pr.recipe_problem("potato_starch") == "", "레시피 배우기 (영구 해금)")
	_check(RecipeDB.learn("strawberry_jam") and pr.recipe_problem("strawberry_jam") == "더 좋은 가공기가 필요해요.", "중급 레시피(딸기잼)는 배워도 수동 가공기로는 못 만듦")
	GameState.unlocks.erase("recipe:strawberry_jam")
	world.save_manager.save_game("manual")
	GameState.unlocks.erase("recipe:potato_starch")
	world.save_manager.load_game()
	pr = grid.object_at(origin) as Processor
	_check(RecipeDB.is_known("potato_starch"), "배운 레시피는 저장·불러오기 후에도 앎")
	GameState.unlocks.erase("recipe:potato_starch")
	inv.remove("potato", 3)

	# 시작: 정한 횟수만, 재료는 한꺼번에 가져가고 회차마다 품질 평균
	GameState.set_clock(8 * 60)
	inv.remove("wheat", inv.count_of("wheat"))
	inv.add("wheat", 3, "bronze")
	inv.add("wheat", 3, "gold")
	_check(Processor.runs_possible(inv, RecipeDB.get_recipe("flour"), 99) == 3, "밀 6개 → 밀가루 3회 가능")
	_check(pr.start(inv, "flour", 5) == 3 and inv.count_of("wheat") == 0 and pr.queue.size() == 3, "5회를 정해도 재료만큼 3회만 (밀 모두 가져감)")
	var qs: Array = pr.queue.map(func(run: Dictionary) -> String: return run.quality)
	_check(qs == ["bronze", "silver", "gold"], "회차별 품질 = 재료 품질 평균, 낮은 품질부터 사용 %s" % [qs])
	_check(pr.start(inv, "bread", 1) == 0, "돌아가는 중에는 새로 시작 못 함")

	# 게임 시계 기준: 밀가루 1시간
	var per_min := GameState.day_length / float(GameState.day_end - GameState.day_start)
	GameState.advance_time(30 * per_min)
	_check(pr.output.is_empty() and absf(pr.progress - 30.0) < 0.5, "30분 지나면 아직 진행 중 (%.1f분)" % pr.progress)
	GameState.set_time_paused("test", true)
	GameState.advance_time(60 * per_min)
	GameState.set_time_paused("test", false)
	_check(pr.output.is_empty(), "시계가 멈춘 동안은 진행 안 됨")
	GameState.advance_time(31 * per_min)
	_check(pr.output_count() == 1 and pr.output[0].quality == "bronze" and pr.queue.size() == 2 and pr.runs_done == 1, "1시간 뒤 밀가루(브론즈) 1개가 가공기 안에")
	var fl_before := inv.count_of("flour")

	# 하루가 끝나면 진행 중인 1회분은 밤사이 완성, 나머지는 다음 날
	GameState.sleep()
	hud._close_panels()
	pr = grid.object_at(origin) as Processor
	var report: Dictionary = world.day_cycle.last_report
	_check(pr.queue.size() == 1 and pr.output.any(func(st: Dictionary) -> bool: return st.quality == "silver") and int(report.get("processed", 0)) == 1, "밤사이 진행 중이던 1회분 완성 (report.processed)")
	GameState.advance_time(61 * per_min)
	_check(pr.queue.is_empty() and pr.runs_done == 3 and pr.output_count() == 3 and not pr.is_working(), "다음 날 남은 1회 완성 → 정한 3회 끝")
	inv.add("wheat", 4)
	GameState.advance_time(120 * per_min)
	_check(not pr.is_working() and inv.count_of("wheat") == 4, "수동: 끝나면 재료가 있어도 다시 돌지 않음")
	_check(pr.take_output(Inventory.new(0)) == 0 and pr.output_count() == 3, "가방에 자리가 없으면 결과물 그대로")
	_check(pr.take_output(inv) == 3 and inv.count_of("flour") == fl_before + 3 and inv.count_of("flour", "gold") >= 1, "결과물 꺼내기 (품질 그대로)")

	# 높은 품질부터 쓰기
	inv.remove("tomato", inv.count_of("tomato"))
	inv.add("tomato", 3, "bronze")
	inv.add("tomato", 3, "gold")
	_check(pr.start(inv, "tomato_puree", 1, true) == 1 and pr.queue[0].quality == "gold" and inv.count_of("tomato", "bronze") == 3, "높은 품질부터: 골드 토마토 3개 → 골드 퓌레")

	# 취소: 남은 회차 재료를 모두 돌려받음 (가방 자리가 없으면 취소 불가)
	_check(not pr.cancel(Inventory.new(0)) and pr.is_working(), "가방 자리가 없으면 취소 불가")
	_check(pr.cancel(inv) and not pr.is_working() and inv.count_of("tomato", "gold") == 3, "취소하면 재료 그대로 돌려받음")

	# 결과물 칸이 가득 차면 다 된 회차는 기다림 (사라지지 않음)
	pr.output = [{"id": "bread", "count": pr.max_output(), "quality": "bronze"}] as Array[Dictionary]
	pr.start(inv, "tomato_puree", 1)
	GameState.advance_time(100 * per_min)
	_check(pr.is_waiting() and pr.output_count() == pr.max_output(), "결과물 칸이 가득 차면 다 된 회차는 대기")
	pr.take_output(inv)
	_check(not pr.is_working() and pr.output_count() == 1 and pr.output[0].id == "tomato_puree", "꺼내면 기다리던 퓌레가 바로 채워짐")
	pr.take_output(inv)

	# 창에서 고르고 횟수 정해 시작
	inv.remove("tomato", inv.count_of("tomato"))
	inv.add("tomato", 7)
	player.global_position = pr.interact_point()  # 잠을 자서 집 앞에 있으므로 다시 가공기 앞으로
	await get_tree().physics_frame
	player._interact()
	_check(panel.visible and panel.processor == pr, "가공기 창 다시 열기")
	panel._select("tomato_puree")
	_check(panel._max_label.text.contains("2") and not panel._start.disabled, "토마토 7개 → 가능 2회 표시")
	panel._set_runs(99)
	_check(panel.runs == 2, "횟수는 가능한 만큼까지만")
	panel._on_start()
	_check(pr.is_working() and pr.runs_total == 2 and inv.count_of("tomato") == 1 and panel._start.disabled, "창에서 [가공 시작] → 2회")
	_check(panel._status.text.contains("토마토 퓌레") and panel._cancel.visible, "진행 상태 표시 (%s)" % panel._status.text)
	var jam_row := panel._list.get_child(recipes.map(func(r: Dictionary) -> String: return r.id).find("blueberry_jam"))
	_check(jam_row.get_child_count() == 3 and jam_row.modulate.a < 1.0, "잠긴 레시피는 흐리고 고르기 버튼 없음")
	hud._close_panels()

	# 저장 / 불러오기
	GameState.advance_time(20 * per_min)
	var state := pr.save_state()
	world.save_manager.save_game("manual")
	pr.take_contents()
	world.save_manager.load_game()
	pr = grid.object_at(origin) as Processor
	_check(pr != null and pr.save_state() == state and pr.queue.size() == 2 and pr.progress > 10.0, "가공기 상태 저장·불러오기 (회차·진행·결과물)")

	# 옮겨도 진행 유지
	state = pr.save_state()
	for x in 2:
		world.obstacles.remove(origin + Vector2i(x, 2))
	await get_tree().process_frame
	player.global_position = world.cell_center(_find_char("s"))
	bm.start(BuildMode.Mode.MOVE)
	_check(bm.pick(origin) and bm.try_drop(origin + Vector2i(0, 1)) and grid.object_at(origin + Vector2i(0, 1)) == pr and pr.save_state() == state, "옮겨도 진행 중인 가공 유지")
	origin += Vector2i(0, 1)

	# 철거: 가방에 자리가 없으면 막고, 있으면 남은 재료 + 결과물 + 건설비 돌려받음
	bm.start(BuildMode.Mode.REMOVE)
	var filler := 99 * inv.size()
	var added := filler - inv.add("stone", filler)
	_check(not bm.try_remove(origin) and grid.object_at(origin) == pr, "가방이 꽉 차면 철거 불가")
	inv.remove("stone", added)
	inv.load_data([])
	var money := GameState.money
	_check(bm.try_remove(origin) and grid.object_at(origin) == null, "가공기 철거")
	_check(inv.count_of("tomato") == 6 and inv.count_of("manual_processor") == 1 and inv.count_of("wood") == 0 and GameState.money == money, "철거하면 남은 재료(토마토 6) + 수동 가공기 아이템 돌려받음")
	bm.stop()

	inv.load_data(saved_inv)
	hud._close_panels()
	await get_tree().process_frame


func _test_power_and_electric(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var bm := world.build_mode
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var player := world.player
	var gen_def := PlaceableDB.get_def("small_generator")
	var ep_def := PlaceableDB.get_def("electric_processor")
	var wh_def := PlaceableDB.get_def("warehouse")
	var gen_item := ItemDB.get_item("small_generator")
	var ep_item := ItemDB.get_item("electric_processor")
	_check(gen_def != null and gen_def.size == Vector2i(2, 2) and gen_def.machine_item() == gen_item and gen_item.buy_price == int(_econ().machines.small_generator) and gen_item.buy_materials == {"wood": 40, "stone": 60}, "소형 발전기 정의 (2x2, 기계상점 %d G + 나무 40 + 돌 60)" % gen_item.buy_price)
	_check(ep_def != null and ep_def.size == Vector2i(3, 3) and ep_def.machine_item() == ep_item and ep_item.buy_price == int(_econ().machines.electric_processor) and ep_item.buy_materials == {"wood": 60, "stone": 80}, "전기 가공기 정의 (3x3, 기계상점 %d G + 나무 60 + 돌 80)" % ep_item.buy_price)
	var st0 := grid.power_status()
	_check(st0.capacity == 0.0 and st0.demand == 0 and not hud._power_label.visible, "발전기가 없으면 전기 표시 숨김")

	# 자리: 창고(4x4) | 전기 가공기(3x3, 창고에 맞닿음) | 발전기(2x2) | 발전기(2x2) — 12x6칸 빈 땅
	var origin := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 6:
			for x in 12:
				var fc := c + Vector2i(x, y)
				if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or world.farm.tiles.has(fc):
					ok = false
		if ok:
			origin = c
			break
	_check(origin.x >= 0, "전기 점검 자리 찾음 %s" % origin)
	if origin.x < 0:
		return
	for y in 6:
		for x in 12:
			world.obstacles.remove(origin + Vector2i(x, y))
	await get_tree().process_frame
	player.global_position = world.cell_center(_find_char("s"))
	var wh := grid.place(wh_def, origin) as Warehouse
	var ep := grid.place(ep_def, origin + Vector2i(4, 0)) as Processor
	_check(wh != null and ep != null and ep.is_automatic() and ep.warehouses().size() == 1 and ep.warehouses()[0] == wh, "전기 가공기가 맞닿은 창고를 찾음")

	# 발전기: 기계상점에서 사서 설치
	inv.remove("wood", inv.count_of("wood"))
	inv.remove("stone", inv.count_of("stone"))
	_buy_machine(hud, "small_generator")
	bm.start_place("small_generator")
	_check(inv.count_of("stone") == 0 and bm.try_place(origin + Vector2i(7, 0)) and inv.count_of("small_generator") == 0, "소형 발전기를 사서 설치 (나무 40 + 돌 60)")
	bm.stop()
	var gen := grid.object_at(origin + Vector2i(7, 0)) as Generator
	var st := grid.power_status()
	_check(gen != null and st.capacity == 300.0 and st.stored == 0.0 and hud._power_label.visible and hud._power_label.text == "전기 0 / 300 없음!", "전기 통 0 / 300 (%s)" % hud._power_label.text)

	# [E] 로 발전기 창 (시간 정지)
	player.global_position = gen.interact_point()
	await get_tree().physics_frame
	player._interact()
	_check(hud._generator.visible and get_tree().paused and GameState.is_time_paused(), "발전기 창 열면 게임·시간 멈춤")
	hud._close_panels()

	# 연료 넣기: 섬유·나무만, 안 탄 연료는 꺼낼 수 있음
	inv.remove("fiber", inv.count_of("fiber"))
	inv.add("wood", 5)
	inv.add("fiber", 6)
	inv.add("stone", 3)
	_check(gen.deposit(inv, "stone", 3) == 0, "돌은 연료가 아님")
	_check(gen.deposit(inv, "wood", 2) == 2 and gen.deposit(inv, "fiber", 6) == 6 and gen.fuel_count() == 8, "나무 2 + 섬유 6 넣기")
	_check(gen.withdraw(inv, "fiber", 2) == 2 and gen.fuel_count() == 6, "안 탄 연료는 다시 꺼냄")

	# 게임 시계로 발전: 나무 1개 = 60분 동안 시간당 60
	var per_min := GameState.day_length / float(GameState.day_end - GameState.day_start)
	GameState.set_clock(8 * 60)
	GameState.advance_time(30 * per_min)
	_check(absf(gen.energy - 30.0) < 1.0 and gen.burning == "wood" and absf(gen.burn_left - 30.0) < 1.0 and gen.power_output() == 60, "30분 발전 → 전기 %.0f, 나무 타는 중" % gen.energy)
	_check(hud._power_label.text.begins_with("전기 30 / 300") or hud._power_label.text.begins_with("전기 29 / 300"), "HUD 전기 표시 (%s)" % hud._power_label.text)

	# 전기 가공기: 만드는 동안에만 전기를 씀
	_check(ep.set_recipe("flour") and ep.set_enabled(true), "레시피 정하고 켜기")
	_check(ep.power_demand() == 0 and grid.power_status().demand == 0, "재료가 없어 쉬는 동안은 전기를 안 씀")
	var before := gen.energy
	gen.take_contents()  # 남은 연료를 빼서 발전을 멈추고 소비만 본다
	gen.burning = ""
	gen.burn_left = 0.0
	GameState.advance_time(30 * per_min)
	_check(absf(gen.energy - before) < 0.01, "쉬는 동안 전기가 줄지 않음")
	wh.storage.add("wheat", 2, "bronze")
	GameState.advance_time(15 * per_min)
	_check(ep.is_working() and ep.power_demand() == 40 and absf(gen.energy - (before - 10.0)) < 1.0, "만드는 동안 시간당 40 사용 (15분에 10, 남은 %.1f)" % gen.energy)

	# 전기가 떨어지면 멈추고, 다시 차면 이어서
	gen.energy = 0.0
	var p_before := ep.progress
	GameState.advance_time(20 * per_min)
	_check(ep.progress - p_before < 0.5 and ep.starved and ep.auto_status().begins_with("전기가 없어서") and hud._power_label.text.contains("없음"), "전기가 없으면 멈춤 (%s)" % ep.auto_status())
	inv.add("wood", 1)
	gen.deposit(inv, "wood", 1)
	GameState.advance_time(20 * per_min)
	_check(ep.progress - p_before > 15.0 and not ep.starved, "연료를 넣으면 저절로 이어서 (진행 %.0f분)" % ep.progress)
	GameState.advance_time(40 * per_min)
	_check(wh.storage.count_of("flour", "bronze") == 1, "밀가루 완성 → 창고로")

	# 통이 가득 차면 발전기는 쉬며 연료를 아낌
	ep.set_enabled(false)
	gen.energy = gen.storage()
	inv.add("wood", 1)
	gen.deposit(inv, "wood", 1)
	var fuel_before := gen.fuel_minutes_left()
	GameState.advance_time(30 * per_min)
	_check(gen.is_full() and absf(gen.fuel_minutes_left() - fuel_before) < 0.01 and gen.power_output() == 0, "통이 가득 차면 연료를 안 태움")

	# 발전기 두 대: 지역 전기 통에 모아 나눠 씀
	var gen2 := grid.place(gen_def, origin + Vector2i(9, 0)) as Generator
	_check(gen2 != null and grid.power_status().capacity == 600.0, "발전기 2대 → 지역 전기 통 600")
	gen.take_contents()
	gen.burning = ""
	gen.burn_left = 0.0
	gen.energy = 10.0
	gen2.energy = 100.0
	ep.set_enabled(true)
	wh.storage.add("wheat", 2)
	GameState.advance_time(60 * per_min)
	var total: float = grid.power_status().stored
	_check(absf(total - 70.0) < 1.5 and gen.energy < 0.01, "두 발전기의 전기를 이어서 씀 (110 → %.1f, 첫 발전기 먼저 비움)" % total)

	# 창: 전기 가공기 정보
	player.global_position = ep.interact_point()
	await get_tree().physics_frame
	player._interact()
	var panel := hud._processor
	_check(panel.visible and panel.processor == ep and panel._toggle.visible and panel._auto_info.text.contains("지역 전기") and panel._auto_info.text.contains("창고 1개"), "전기 가공기 창 (%s)" % panel._auto_info.text)
	panel._quality.select(1)
	panel._quality.item_selected.emit(1)
	_check(ep.high_first, "재료 품질 순서: 높은 품질부터")
	panel._on_toggle()
	_check(not ep.enabled and grid.power_status().demand == 0, "창에서 끄기")
	panel._on_toggle()
	hud._close_panels()

	# 발전기 창 내용
	player.global_position = gen.interact_point()
	await get_tree().physics_frame
	inv.add("wood", 3)
	player._interact()
	var gp := hud._generator
	_check(gp.visible and gp.generator == gen and gp._bag_list.get_child_count() >= 1 and gp._energy.text.contains("지역 전기 통"), "발전기 창: 연료 목록·전기 통 (%s)" % gp._energy.text)
	gp._put("wood", 3)
	_check(gen.fuel_count() == 3, "창에서 연료 넣기")
	hud._close_panels()

	# 야간 생산 (§97): 밤에 발전기가 연료를 태우고 기계가 그 전기로 5시간 일함
	ep.take_contents()
	ep.progress = 0.0
	gen.energy = 0.0
	gen2.energy = 0.0
	inv.add("wood", 10)
	gen.deposit(inv, "wood", 10)
	wh.storage.add("wheat", 20)
	GameState.record_sale(Pricing.PLAZA, 100)  # 판매 요약 → 야간 생산 요약 순서를 보려고
	GameState.sleep()
	_check(hud._summary.visible and not hud._night.visible, "하루 끝: 판매 요약 먼저 (야간 생산 요약은 아직)")
	hud._summary.close_requested.emit()
	_check(hud._night.visible and get_tree().paused and hud._night._lines.get_child_count() == 1 and hud._night._energy.visible, "판매 요약을 닫으면 아침 야간 생산 요약 (밀가루 + 발전량)")
	var night_row := hud._night._lines.get_child(0)
	_check((night_row.get_child(1) as Label).text == "밀가루" and (night_row.get_child(2) as Label).text.begins_with("+"), "요약 줄: 밀가루 %s" % (night_row.get_child(2) as Label).text)
	hud._night.close_requested.emit()
	_check(not hud._night.visible and not get_tree().paused, "확인 누르면 닫히고 게임 재개")
	var report: Dictionary = world.day_cycle.last_report
	var night: Dictionary = report.get("night_production", {})
	_check(int(night.get("items", {}).get("flour", 0)) == int(night.get("processed", 0)), "report.night_production.items 에 밀가루 개수")
	_check(int(night.get("processed", 0)) >= 4 and int(night.get("processed", 0)) <= 5 and float(night.get("energy", 0.0)) > 250.0, "야간 5시간: 발전 %.0f, 밀가루 %d개" % [float(night.get("energy", 0.0)), int(night.get("processed", 0))])

	# 저장 / 불러오기
	gen = grid.object_at(origin + Vector2i(7, 0)) as Generator
	var gstate := gen.save_state()
	var estate := ep.save_state()
	world.save_manager.save_game("manual")
	gen.take_contents()
	ep.set_enabled(false)
	world.save_manager.load_game()
	gen = grid.object_at(origin + Vector2i(7, 0)) as Generator
	ep = grid.object_at(origin + Vector2i(4, 0)) as Processor
	_check(gen != null and gen.save_state() == gstate, "발전기 저장·불러오기 (연료·타는 중·전기)")
	_check(ep != null and ep.save_state() == estate and ep.enabled and ep.high_first, "전기 가공기 저장·불러오기 (켜짐·레시피·품질 순서)")

	# 철거: 남은 연료를 돌려받음
	inv.load_data([])
	var fuel_left := gen.fuel_count()
	bm.start(BuildMode.Mode.REMOVE)
	_check(bm.try_remove(origin + Vector2i(7, 0)) and inv.count_of("wood") == fuel_left and inv.count_of("small_generator") == 1, "발전기 철거 → 남은 연료 + 발전기 아이템 돌려받음")
	bm.stop()

	# 정리
	for at: Vector2i in [origin, origin + Vector2i(4, 0), origin + Vector2i(9, 0)]:
		var obj := grid.object_at(at)
		if obj:
			obj.take_contents()
			grid.remove(obj)
	await get_tree().process_frame
	_check(grid.power_status().capacity == 0.0 and not hud._power_label.visible, "모두 철거하면 전기 표시 숨김")
	inv.load_data(saved_inv)
	hud._close_panels()
	await get_tree().process_frame


func _test_conveyor(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var bm := world.build_mode
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var player := world.player
	var belt_def := PlaceableDB.get_def("conveyor")
	_check(belt_def != null and belt_def.cost_text() == "컨베이어 1" and BuildMode.is_belt(belt_def) and not belt_def.solid, "컨베이어 정의 (칸마다 컨베이어 1, 지나다닐 수 있음)")
	_check(ItemDB.shop_items().any(func(it: ItemDef) -> bool: return it.id == "conveyor"), "상점에서 컨베이어 판매")

	# 포트 회전 (§54, §55): 창고 입구는 왼쪽 → 시계 방향으로 돌리면 위쪽
	var wh_def := PlaceableDB.get_def("warehouse")
	var p0 := Placeable.ports_of(wh_def, Vector2i(10, 10), 0)
	var p1 := Placeable.ports_of(wh_def, Vector2i(10, 10), 1)
	_check(p0.size() == 2 and p0[0].type == "in" and p0[0].cell == Vector2i(10, 11) and p0[0].outside == Vector2i(9, 11) and p0[1].outside == Vector2i(14, 12), "창고 입구 왼쪽·출구 오른쪽 %s" % [p0.map(func(p: Dictionary) -> Vector2i: return p.outside)])
	_check(p1[0].dir == Vector2i.UP and p1[0].cell == Vector2i(12, 10) and p1[1].dir == Vector2i.DOWN, "돌리면 포트도 같이 돎 (입구 위, 출구 아래)")
	_check(wh_def.rotatable, "포트가 있는 정사각형 시설은 돌릴 수 있음")

	# ㄱ자 길: 멀리 간 쪽 먼저, 칸마다 다음 칸 방향
	var path := BuildMode.belt_path(Vector2i(0, 0), Vector2i(2, 1))
	_check(path.map(func(p: Dictionary) -> Vector2i: return p.cell) == [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)] and path.map(func(p: Dictionary) -> int: return p.turns) == [3, 3, 0, 0], "끌어서 놓을 길 (ㄱ자, 방향)")

	# 자리: 창고A(4x4) → 벨트 2 → 전기 가공기(3x3) → 벨트 2 → 창고B(4x4), 가공기 아래 발전기 — 16x7칸 빈 땅
	var origin := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 7:
			for x in 16:
				var fc := c + Vector2i(x, y)
				if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or world.farm.tiles.has(fc):
					ok = false
		if ok:
			origin = c
			break
	_check(origin.x >= 0, "컨베이어 점검 자리 찾음 %s" % origin)
	if origin.x < 0:
		return
	for y in 7:
		for x in 16:
			world.obstacles.remove(origin + Vector2i(x, y))
	await get_tree().process_frame
	player.global_position = world.cell_center(_find_char("s"))
	var o := origin
	var wa := grid.place(wh_def, o) as Warehouse
	var ep := grid.place(PlaceableDB.get_def("electric_processor"), o + Vector2i(6, 1)) as Processor
	var wb := grid.place(wh_def, o + Vector2i(11, 1)) as Warehouse
	var gen := grid.place(PlaceableDB.get_def("small_generator"), o + Vector2i(6, 4)) as Generator
	_check(wa != null and ep != null and wb != null and gen != null and ep.warehouses().is_empty(), "창고·가공기·발전기 (가공기는 창고와 떨어져 있음)")

	# 상점에서 사서 끌어서 깔기
	inv.remove("conveyor", inv.count_of("conveyor"))
	GameState.add_money(1000)
	var money := GameState.money
	hud._shop._buy("conveyor", 4)
	var belt_price := ItemDB.get_item("conveyor").buy_price
	_check(inv.count_of("conveyor") == 4 and GameState.money == money - belt_price * 4, "컨베이어 4개 구매 (%d G씩)" % belt_price)
	bm.start_place("conveyor")
	_check(bm.place_belts(o + Vector2i(4, 2), o + Vector2i(5, 2)) == 2 and bm.place_belts(o + Vector2i(9, 2), o + Vector2i(10, 2)) == 2 and inv.count_of("conveyor") == 0, "끌어서 2칸씩 깔기 → 칸마다 1개 사용")
	var b1 := grid.object_at(o + Vector2i(4, 2)) as Conveyor
	var b2 := grid.object_at(o + Vector2i(5, 2)) as Conveyor
	var b3 := grid.object_at(o + Vector2i(9, 2)) as Conveyor
	var b4 := grid.object_at(o + Vector2i(10, 2)) as Conveyor
	_check(b1 != null and b2 != null and b3 != null and b4 != null and [b1, b2, b3, b4].all(func(b: Conveyor) -> bool: return b.facing() == Vector2i.RIGHT), "깐 방향 = 끈 방향 (오른쪽)")
	_check(grid.conveyors.next_belt(b1) == b2 and grid.conveyors.target_facility(b2) == ep and grid.conveyors.target_facility(b4) == wb, "벨트 → 가공기 입구, 벨트 → 창고B 입구 연결")
	_check(bm.place_belts(o + Vector2i(0, 5), o + Vector2i(2, 5)) == 0, "컨베이어가 없으면 못 깜")
	inv.add("conveyor", 1)
	_check(bm.place_belts(o + Vector2i(0, 5), o + Vector2i(2, 5)) == 1 and grid.object_at(o + Vector2i(1, 5)) == null, "가진 개수만큼만 깔림 (모자란 칸은 건너뜀)")
	inv.add("conveyor", 3)
	_check(bm.place_belts(o + Vector2i(1, 5), o + Vector2i(2, 6)) == 3, "ㄱ자로 3칸 더")
	_check(bm.place_belts(o + Vector2i(3, 2), o + Vector2i(3, 2)) == 0, "시설이 있는 칸에는 못 깜")
	bm.stop()
	var corner := grid.object_at(o + Vector2i(2, 5)) as Conveyor
	_check(corner != null and corner.facing() == Vector2i.DOWN and corner.shape == Conveyor.Shape.FROM_LEFT and b2.shape == Conveyor.Shape.STRAIGHT, "모서리 그림 저절로 (왼쪽에서 들어와 아래로)")

	# 벨트 위 물건: 모서리를 돌아 끝에서 기다림 (§61)
	var first := grid.object_at(o + Vector2i(0, 5)) as Conveyor
	var last := grid.object_at(o + Vector2i(2, 6)) as Conveyor
	first.put("wheat", "silver")
	grid.conveyors.tick(10.0)
	_check(last.has_item() and last.item.id == "wheat" and last.progress >= 1.0 and not first.has_item(), "물건이 모서리를 돌아 끝 칸에서 기다림")
	var mid := grid.object_at(o + Vector2i(1, 5)) as Conveyor
	mid.put("carrot", "bronze")
	grid.conveyors.tick(10.0)
	_check((grid.object_at(o + Vector2i(2, 5)) as Conveyor).has_item() and last.item.id == "wheat", "앞이 막히면 뒤 칸도 줄 서서 기다림 (사라지지 않음)")

	# 창고A 출구 필터 → 벨트 → 가공기 → 벨트 → 창고B
	_check(wa.provide_item().is_empty(), "출구 필터를 정하지 않으면 안 내보냄")
	wa.storage.add("wheat", 4, "bronze")
	wa.storage.add("carrot", 3, "bronze")
	wa.set_output_mode("items")
	wa.add_output_item("wheat")
	_check(ep.set_recipe("flour") and ep.set_enabled(true), "가공기: 밀가루 레시피 켜기")
	_check(ep.auto_status().begins_with("재료를 기다리는 중"), "창고가 맞닿지 않아도 입구 벨트가 있으면 재료를 기다림 (%s)" % ep.auto_status())
	inv.add("wood", 10)
	gen.deposit(inv, "wood", 10)
	var per_min := GameState.day_length / float(GameState.day_end - GameState.day_start)
	GameState.set_clock(8 * 60)
	for i in 200:
		GameState.advance_time(per_min)
	_check(wb.storage.count_of("flour") == 2 and wa.storage.count_of("wheat") == 0 and wa.storage.count_of("carrot") == 3, "밀 4 → 컨베이어 → 가공기 → 컨베이어 → 창고B 밀가루 2 (당근은 안 나감)")

	# 창고B가 받지 않으면 벨트 위에 쌓이고 가공기 안에서 기다림 (아이템 보존)
	wb.set_filter_mode("seed")
	wa.storage.add("wheat", 6, "bronze")
	for i in 400:
		GameState.advance_time(per_min)
	var flour_total := wb.storage.count_of("flour") + ep.output_count()
	for b in grid.conveyors.belts():
		if b.has_item() and b.item.id == "flour":
			flour_total += 1
	_check(b4.has_item() and b4.item.id == "flour" and b4.progress >= 1.0 and flour_total == 5, "받을 곳이 막히면 벨트 끝에서 기다림, 밀가루 5개 모두 그대로 (%d)" % flour_total)
	wb.set_filter_mode("all")

	# 발전기 입구로 연료 넣기
	inv.add("conveyor", 1)
	bm.start_place("conveyor")
	bm.turns = 3
	_check(bm.try_place(o + Vector2i(5, 5)), "발전기 입구 앞에 벨트 한 칸")
	bm.stop()
	var fuel_belt := grid.object_at(o + Vector2i(5, 5)) as Conveyor
	var fuel_before := gen.fuel_count()
	fuel_belt.put("wood", Quality.NONE)
	grid.conveyors.tick(5.0)
	_check(not fuel_belt.has_item() and gen.fuel_count() == fuel_before + 1, "벨트로 발전기에 연료 넣기")
	fuel_belt.put("stone", Quality.NONE)
	grid.conveyors.tick(5.0)
	_check(fuel_belt.has_item() and fuel_belt.item.id == "stone", "연료가 아니면 안 받고 벨트에서 기다림")

	# 야간 생산 때도 움직임 (§97)
	fuel_belt.clear_item()
	first.put("potato", "gold")
	grid.night_production({}, 10.0)
	_check(not first.has_item(), "야간 생산 동안에도 벨트가 움직임")

	# 창고 창: 내보낼 물건 고르기
	player.global_position = wa.interact_point()
	await get_tree().physics_frame
	player._interact()
	var panel := hud._warehouse
	_check(panel.visible and panel._out_pick.visible and panel._out_chips.get_child_count() == 1, "창고 창: 내보낼 물건 (지정 아이템 1개)")
	inv.add("carrot", 1)
	panel._out_pick.button_pressed = true
	panel._on_bag_clicked(_slot_index(inv, "carrot", ""))
	panel._out_pick.button_pressed = false
	_check(wa.output_items == ["wheat", "carrot"] and wa.filter_mode == "all", "가방에서 골라 내보낼 물건에 추가 (받을 물건 필터는 그대로)")
	panel._out_filter.select(0)
	panel._out_filter.item_selected.emit(0)
	_check(wa.output_mode == "none", "안 내보냄으로 바꾸기")
	hud._close_panels()

	# 저장 / 불러오기: 벨트 위 물건·창고 출구 필터·가공기 입구 재료
	var mid_state := mid.save_state()
	var wa_state := wa.save_state()
	ep.input = [{"id": "wheat", "count": 1, "quality": "bronze"}] as Array[Dictionary]
	var ep_state := ep.save_state()
	world.save_manager.save_game("manual")
	mid.clear_item()
	world.save_manager.load_game()
	mid = grid.object_at(o + Vector2i(1, 5)) as Conveyor
	wa = grid.object_at(o) as Warehouse
	ep = grid.object_at(o + Vector2i(6, 1)) as Processor
	_check(mid != null and mid.save_state() == mid_state and mid.facing() == Vector2i.RIGHT, "벨트 저장·불러오기 (방향·물건·위치)")
	_check(wa != null and wa.save_state() == wa_state and ep != null and ep.save_state() == ep_state, "창고 출구 필터·가공기 입구 재료 저장·불러오기")
	_check((grid.object_at(o + Vector2i(2, 5)) as Conveyor).shape == Conveyor.Shape.FROM_LEFT, "불러온 뒤에도 모서리 모양")

	# 철거: 벨트 위 물건과 컨베이어를 돌려받음 (§64, §106)
	inv.load_data([])
	var held: Dictionary = mid.item.duplicate()
	bm.start(BuildMode.Mode.REMOVE)
	_check(bm.try_remove(o + Vector2i(1, 5)) and inv.count_of("conveyor") == 1 and inv.count_of(str(held.id)) == 1, "벨트 철거 → 컨베이어 + 위의 %s 돌려받음" % held.id)
	bm.stop()

	# 실제 입력으로 끌기 (키보드: Space 누른 채 걸어서 앞 칸을 옮김 — 마우스와 같은 입력 경로)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.physical_keycode = KEY_SPACE
	# 플레이어를 stand 칸에 세워 아래 칸을 보게 한다. 건설 모드의 _process 가 한 번 돌아 앞 칸을 다시 읽도록 두 프레임 기다린다
	var aim := func(stand: Vector2i) -> void:
		player.global_position = world.cell_center(stand)
		player.facing = Vector2i.DOWN
		await get_tree().process_frame
		await get_tree().process_frame
	inv.remove("conveyor", inv.count_of("conveyor"))
	inv.add("conveyor", 2)
	bm.start_place("conveyor")
	bm._use_mouse = false
	await aim.call(o + Vector2i(8, 5))
	space.pressed = true
	get_viewport().push_input(space, true)
	await get_tree().process_frame
	await aim.call(o + Vector2i(10, 5))
	_check(bm._dragging and bm._path.size() == 3 and not bm._path[2].ok, "끄는 동안 길 미리보기 (3칸 중 가진 2개만 초록)")
	var release := space.duplicate()
	release.pressed = false
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	var row := [o + Vector2i(8, 6), o + Vector2i(9, 6), o + Vector2i(10, 6)].map(func(c: Vector2i) -> Placeable: return grid.object_at(c))
	_check(row[0] is Conveyor and row[1] is Conveyor and row[2] == null and row[0].facing() == Vector2i.RIGHT and inv.count_of("conveyor") == 0, "Space 누른 채 걸어서 깔기 → 가진 2칸만 설치")
	bm.stop()

	# 철거: 누른 채 끌면 지나간 컨베이어를 모두 철거 (§65)
	bm.start(BuildMode.Mode.REMOVE)
	bm._use_mouse = false
	await aim.call(o + Vector2i(8, 5))
	get_viewport().push_input(space, true)
	await get_tree().process_frame
	await aim.call(o + Vector2i(9, 5))
	await aim.call(o + Vector2i(10, 5))
	get_viewport().push_input(release, true)
	await get_tree().process_frame
	_check(grid.object_at(o + Vector2i(8, 6)) == null and grid.object_at(o + Vector2i(9, 6)) == null and inv.count_of("conveyor") == 2, "끌어서 철거 → 지나간 벨트 모두 철거, 컨베이어 2개 돌려받음")
	bm.stop()

	# 정리
	for obj in grid.objects().duplicate():
		if Rect2i(o, Vector2i(16, 7)).has_point(obj.cell):
			obj.take_contents()
			grid.remove(obj)
	await get_tree().process_frame
	_check(grid.conveyors.belts().is_empty(), "정리: 벨트 모두 철거")
	inv.load_data(saved_inv)
	hud._close_panels()
	await get_tree().process_frame


func _test_recipe_shop(world: FarmWorld, hud: HUD) -> void:
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var saved_unlocks := GameState.unlocks.duplicate(true)
	var money0 := GameState.money
	var player := world.player

	# 데이터: 처음부터 아는 6개를 뺀 16개를 팔고, 값 = 결과물 판매가 × 개수 × 3
	var shop := RecipeDB.shop_recipes()
	_check(shop.size() == 16 and shop.all(func(r: Dictionary) -> bool: return int(r.price) > 0 and not r.unlocked), "레시피 상점 품목 16개, 모두 값이 있음 (recipes.json price)")
	var syrup_price := int(RecipeDB.get_recipe("fruit_syrup_strawberry").price)
	_check(syrup_price == ItemDB.get_item("fruit_syrup").sell_price * 3 and int(RecipeDB.get_recipe("flour").price) == 0, "과일 시럽 %d G (판매가 × 3), 처음부터 아는 레시피는 0" % syrup_price)

	# 광장 건물 [E] → 창 (게임·시간 멈춤)
	var shops := world.buildings.filter(func(b: Interactable) -> bool: return b is RecipeShop)
	_check(shops.size() == 1 and MapLayout.char_at(Vector2i(64, 37)) == "C", "광장에 레시피 상점 (3x2)")
	if shops.is_empty():
		return
	player.global_position = shops[0].interact_point()
	await get_tree().physics_frame
	player._interact()
	_check(hud._recipes.visible and get_tree().paused and GameState.is_time_paused(), "레시피 상점 창 열면 게임·시간 멈춤")
	hud._close_panels()
	_check(not hud._recipes.visible and not get_tree().paused and not GameState.is_time_paused(), "닫으면 재개")

	# 재료를 모두 얻어 봐야 진열 (사용자 결정: 주재료를 처음 얻으면)
	for key: String in ["found:strawberry", "found:blueberry", "recipe:fruit_syrup_strawberry", "recipe:fruit_syrup_blueberry", "recipe:blueberry_jam", "recipe:strawberry_jam"]:
		GameState.unlocks.erase(key)
	inv.remove("strawberry", inv.count_of("strawberry"))
	inv.remove("blueberry", inv.count_of("blueberry"))
	var syrup := RecipeDB.get_recipe("fruit_syrup_strawberry")
	_check(not RecipeDB.is_revealed("fruit_syrup_strawberry") and RecipeDB.buy_problem("fruit_syrup_strawberry") != "" and RecipeShopPanel._hidden_inputs(syrup) == "??? · ???", "재료를 못 얻었으면 ??? (%s)" % RecipeShopPanel._hidden_inputs(syrup))
	inv.add("strawberry", 1)
	_check(GameState.has_found("strawberry") and not RecipeDB.is_revealed("fruit_syrup_strawberry") and RecipeShopPanel._hidden_inputs(syrup) == "딸기 · ???", "가방에 들어온 재료는 이름이 보임 (%s)" % RecipeShopPanel._hidden_inputs(syrup))
	var wh := Warehouse.new()
	wh.setup(PlaceableDB.get_def("warehouse"), Vector2i.ZERO)
	wh.insert("blueberry", 1)
	wh.free()
	_check(GameState.has_found("blueberry") and RecipeDB.is_revealed("fruit_syrup_strawberry"), "창고로 바로 들어온 재료도 얻은 것으로 침 → 과일 시럽 진열")
	_check(RecipeDB.is_revealed(RecipeShopPanel.ordered()[0].id), "배울 수 있는 레시피가 맨 위")

	# 사기: 돈이 모자라면 못 배우고, 내면 영구히 배움
	GameState.money = syrup_price - 1
	_check(RecipeDB.buy_problem("fruit_syrup_strawberry").begins_with("돈이 부족") and not RecipeDB.buy("fruit_syrup_strawberry"), "돈이 모자라면 못 배움")
	GameState.money = syrup_price + 100
	_check(RecipeDB.buy("fruit_syrup_strawberry") and RecipeDB.is_known("fruit_syrup_strawberry") and GameState.money == 100, "%d G 내고 과일 시럽 배움 (남은 돈 %d)" % [syrup_price, GameState.money])
	_check(RecipeDB.buy_problem("fruit_syrup_strawberry") == "이미 배운 레시피예요." and RecipeShopPanel.ordered()[-1].id in shop.filter(func(r: Dictionary) -> bool: return RecipeDB.is_known(r.id)).map(func(r: Dictionary) -> String: return r.id), "배운 레시피는 맨 아래, 다시 못 삼")
	# 옛 id (합쳐진 레시피): 옛 저장에서 블루베리 과일 시럽을 배웠으면 지금 과일 시럽을 아는 것으로
	GameState.unlocks.erase("recipe:fruit_syrup_strawberry")
	GameState.unlocks["recipe:fruit_syrup_blueberry"] = true
	_check(RecipeDB.is_known("fruit_syrup_strawberry") and RecipeDB.has("fruit_syrup_blueberry") and RecipeDB.get_recipe("fruit_syrup_blueberry").id == "fruit_syrup_strawberry", "옛 id(fruit_syrup_blueberry)로 배운 저장 → 지금 과일 시럽")
	GameState.unlocks.erase("recipe:fruit_syrup_blueberry")

	# 창에서 배우기
	GameState.money = 5000
	player.global_position = shops[0].interact_point()
	await get_tree().physics_frame
	player._interact()
	var rows := hud._recipes._list.get_children()
	_check(rows.size() == 16, "창: 16줄 (%d)" % rows.size())
	var bj_price := int(RecipeDB.get_recipe("blueberry_jam").price)
	hud._recipes._buy("blueberry_jam")
	_check(RecipeDB.is_known("blueberry_jam") and GameState.money == 5000 - bj_price, "창에서 [배우기] (블루베리잼 %d G)" % bj_price)
	hud._close_panels()

	# 처음 만든 가공품도 얻은 것 (다음 레시피 재료)
	GameState.unlocks.erase("found:tomato_puree")
	var pr := Processor.new()
	pr.setup(PlaceableDB.get_def("manual_processor"), Vector2i.ZERO)
	pr.recipe_id = "tomato_puree"
	pr.queue = [{"inputs": [], "quality": "bronze"}] as Array[Dictionary]
	pr._finish_one(RecipeDB.get_recipe("tomato_puree"))
	pr.free()
	_check(GameState.has_found("tomato_puree"), "가공기가 처음 만든 토마토 퓌레도 얻은 것으로 침")

	# 저장 / 불러오기: 배운 레시피·얻은 기록 유지
	world.save_manager.save_game("manual")
	GameState.unlocks.erase("recipe:blueberry_jam")
	GameState.unlocks.erase("found:blueberry")
	world.save_manager.load_game()
	_check(RecipeDB.is_known("blueberry_jam") and GameState.has_found("blueberry"), "저장·불러오기: 배운 레시피와 얻은 기록 유지")

	GameState.unlocks = saved_unlocks
	GameState.money = money0
	inv.load_data(saved_inv)
	await get_tree().process_frame


func _test_farm_machines(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var farm := world.farm
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var saved_day := GameState.day
	var player := world.player
	# 당근(봄 작물)을 심고 하루를 넘겨도 계절이 바뀌지 않게 봄 2일로 둔다
	GameState.day = 2

	# 범위 규칙 (사용자 결정: 하급 + / 중급 3x3 / 상급 5x5, 스프링클러·수확기 같은 규칙)
	var counts := []
	for id in ["sprinkler_1", "sprinkler_2", "sprinkler_3", "harvester_1", "harvester_2", "harvester_3"]:
		var def := PlaceableDB.get_def(id)
		counts.append(FarmArea.cells(Vector2i(10, 10), def.data.get("area")).size() if def else -1)
	_check(counts == [4, 8, 24, 4, 8, 24], "범위: 하급 4칸 · 중급 8칸 · 상급 24칸 %s" % [counts])
	_check(FarmArea.cells(Vector2i(10, 10), {"shape": "plus", "radius": 1}).has(Vector2i(10, 9)) and not FarmArea.cells(Vector2i(10, 10), {"shape": "plus", "radius": 1}).has(Vector2i(11, 9)), "+ 모양은 대각선 제외")
	_check(not PlaceableDB.get_def("sprinkler_1").solid and not PlaceableDB.get_def("harvester_1").solid and PlaceableDB.get_def("harvester_1").directional, "1칸 기계는 지나다닐 수 있고, 수확기는 방향(출구)이 있음")

	# 자리: 7x7 빈 밭 땅 (가운데에 기계)
	var origin := Vector2i(-1, -1)
	var cells: Array = farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 9:
			for x in 9:
				var fc := c + Vector2i(x, y)
				if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or farm.tiles.has(fc):
					ok = false
		if ok:
			origin = c
			break
	_check(origin.x >= 0, "농사 기계 점검 자리 %s" % origin)
	if origin.x < 0:
		return
	for y in 9:
		for x in 9:
			world.obstacles.remove(origin + Vector2i(x, y))
	await get_tree().process_frame
	player.global_position = world.cell_center(_find_char("s"))
	var center := origin + Vector2i(4, 4)
	var ring := FarmArea.cells(center, {"shape": "square", "radius": 2})
	for c in ring:
		farm.till(c)
	_check(ring.all(func(c: Vector2i) -> bool: return farm.get_tile(c) != null and not farm.get_tile(c).watered), "5x5 밭 갈기 (마른 상태)")

	# 스프링클러: 매일 아침 범위 안 밭에 물 (물탱크 물을 씀 — 물은 넉넉히 넣어 둔다)
	var tank := grid.place(PlaceableDB.get_def("water_tank"), origin + Vector2i(7, 0)) as WaterTank
	tank.water = tank.capacity()
	var sp3 := grid.place(PlaceableDB.get_def("sprinkler_3"), center) as Sprinkler
	_check(sp3 != null, "상급 스프링클러 설치")
	grid.start_day()
	_check(ring.all(func(c: Vector2i) -> bool: return farm.get_tile(c).watered), "아침에 5x5 24칸 모두 물")
	grid.remove(sp3)
	for c in ring:
		farm.get_tile(c).watered = false
	var sp1 := grid.place(PlaceableDB.get_def("sprinkler_1"), center) as Sprinkler
	_check(int(sp1.water_area(world).watered) == 4 and farm.get_tile(center + Vector2i.UP).watered and not farm.get_tile(center + Vector2i(1, 1)).watered, "하급은 상하좌우 4칸만")
	for c in ring:
		farm.get_tile(c).watered = false
	GameState.set_clock(9 * 60)
	GameState.sleep()
	hud._close_panels()
	_check(farm.get_tile(center + Vector2i.LEFT).watered and not farm.get_tile(center + Vector2i(-2, -2)).watered, "하루가 넘어가면 아침에 저절로 물 (하루 마감 wake_up 단계)")
	grid.remove(sp1)

	# 자동 수확기: 다 자란 작물 심기 (+ 모양 4칸)
	var carrot_seed := ItemDB.get_item("carrot_seed")
	var plant_ripe := func(c: Vector2i) -> void:
		farm.plant(c, carrot_seed)
		farm.get_tile(c).days_grown = carrot_seed.grow_days
	for c in FarmArea.cells(center, {"shape": "plus", "radius": 1}):
		plant_ripe.call(c)
	await get_tree().process_frame
	var hv := grid.place(PlaceableDB.get_def("harvester_1"), center) as AutoHarvester
	_check(hv != null and hv.next_target() != AutoHarvester.NO_CELL, "하급 자동 수확기 설치 (다 자란 작물 발견)")
	hv.advance(30.0)
	_check(hv.output.is_empty() and hv.starved and hv.status_text().begins_with("전기가 없어서") and farm.get_tile(center + Vector2i.UP).is_mature(), "전기가 없으면 거두지 않고 작물은 밭에 그대로")

	# 발전기 + 연료 → 거두는 동안에만 전기
	# (하루를 넘기는 동안 작은 장애물이 다시 자랐을 수 있다 §103 — 발전기 자리를 다시 치운다)
	for c in Placeable.footprint_of(PlaceableDB.get_def("small_generator"), origin):
		world.obstacles.remove(c)
	await get_tree().process_frame
	var gen := grid.place(PlaceableDB.get_def("small_generator"), origin) as Generator
	inv.add("wood", 5)
	gen.deposit(inv, "wood", 5)
	gen.produce(120.0)
	var before := gen.energy
	var got := hv.advance(40.0)
	var picked := hv.output_count()
	_check(got.size() == 4 and picked >= 4 and picked <= 12 and not hv.starved and absf((before - gen.energy) - 20.0) < 0.6, "40분에 4번 거둠 (당근 %d개, 10분씩, 시간당 30 → 전기 %.1f 사용)" % [picked, before - gen.energy])
	_check(FarmArea.cells(center, {"shape": "plus", "radius": 1}).all(func(c: Vector2i) -> bool: return not farm.get_tile(c).has_crop()), "거둔 칸은 빈 밭 (한 번 거두는 작물)")
	var e2 := gen.energy
	hv.advance(30.0)
	_check(absf(gen.energy - e2) < 0.01 and hv.power_demand() == 0, "거둘 게 없으면 전기를 안 씀")
	_check(farm.get_tile(center + Vector2i(1, 1)) != null and not farm.get_tile(center + Vector2i(1, 1)).has_crop(), "하급은 대각선 칸에 손대지 않음")

	# 출구 → 컨베이어 (§66: 창고로 순간이동하지 않음)
	inv.add("conveyor", 1)
	world.build_mode.start_place("conveyor")
	world.build_mode.turns = 0
	_check(world.build_mode.try_place(center + Vector2i(0, 1)), "수확기 출구(아래) 앞에 벨트")
	world.build_mode.stop()
	var belt := grid.object_at(center + Vector2i(0, 1)) as Conveyor
	grid.conveyors.tick(1.0)
	_check(belt.has_item() and belt.item.id == "carrot" and hv.output_count() == picked - 1, "거둔 당근이 출구 벨트로 나감")
	grid.remove(belt)

	# 안이 가득 차면 거두지 않음 (작물 보존)
	hv.output = [{"id": "carrot", "count": hv.max_output(), "quality": "bronze"}] as Array[Dictionary]
	plant_ripe.call(center + Vector2i.LEFT)
	hv.advance(30.0)
	_check(farm.get_tile(center + Vector2i.LEFT).is_mature() and hv.status_text().begins_with("안이 가득"), "안이 가득 차면 거두지 않고 작물은 밭에 그대로")

	# [E] 로 꺼내기
	inv.load_data([])
	player.global_position = hv.interact_point()
	await get_tree().physics_frame
	player._interact()
	_check(inv.count_of("carrot") == hv.max_output() and hv.output.is_empty(), "[E] 로 거둔 것을 가방에 꺼냄")

	# 야간 생산: 밤에도 거두고 아침 요약에 나옴
	var report := {}
	gen.produce(60.0)
	grid.night_production(report, 30.0)
	var night_carrots := int(report.get("night_production", {}).get("items", {}).get("carrot", 0))
	_check(night_carrots >= 1 and night_carrots <= 3 and not farm.get_tile(center + Vector2i.LEFT).has_crop(), "야간 생산 동안 거둠 → 야간 요약에 당근 %d개" % night_carrots)

	# 상급: 5x5 범위
	grid.remove(hv)
	var hv3 := grid.place(PlaceableDB.get_def("harvester_3"), center) as AutoHarvester
	plant_ripe.call(center + Vector2i(2, -2))
	_check(hv3.next_target() == center + Vector2i(2, -2), "상급은 5x5 모서리 칸도 거둠")

	# 저장 / 불러오기
	hv3.advance(5.0)
	var state := hv3.save_state()
	world.save_manager.save_game("manual")
	hv3.take_contents()
	world.save_manager.load_game()
	hv3 = grid.object_at(center) as AutoHarvester
	_check(hv3 != null and hv3.save_state() == state and absf(hv3.progress - 5.0) < 0.01, "수확기 저장·불러오기 (진행 %.1f분)" % (hv3.progress if hv3 else -1.0))

	# 정리
	for obj in grid.objects().duplicate():
		if Rect2i(origin, Vector2i(9, 9)).has_point(obj.cell):
			obj.take_contents()
			grid.remove(obj)
	for c in ring:
		farm.remove_crop(c)
		farm.untill(c)
	inv.load_data(saved_inv)
	GameState.day = saved_day
	hud._close_panels()
	await get_tree().process_frame


func _test_routers(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var net := grid.conveyors
	var belt := PlaceableDB.get_def("conveyor")
	var R := 3  # 오른쪽을 보는 turns
	var UP := 2
	var DOWN := 0

	# 자리: 10x13 빈 땅 (분배기 줄 y=2, 합류기 줄 y=6, 필터 분배기 줄 y=10)
	var o := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 13:
			for x in 10:
				var fc := c + Vector2i(x, y)
				if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or world.farm.tiles.has(fc):
					ok = false
		if ok:
			o = c
			break
	_check(o.x >= 0, "분배기 점검 자리 %s" % o)
	if o.x < 0:
		return
	for y in 13:
		for x in 10:
			world.obstacles.remove(o + Vector2i(x, y))
	await get_tree().process_frame
	world.player.global_position = world.cell_center(_find_char("s"))

	# 분배기 (사용자 결정: 3갈래, 이어진 쪽으로 돌아가며)
	var src := grid.place(belt, o + Vector2i(1, 2), R) as Conveyor
	var sp := grid.place(PlaceableDB.get_def("splitter"), o + Vector2i(2, 2), R) as Router
	var out_l := grid.place(belt, o + Vector2i(2, 1), UP) as Conveyor
	var out_f := grid.place(belt, o + Vector2i(3, 2), R) as Conveyor
	var out_r := grid.place(belt, o + Vector2i(2, 3), DOWN) as Conveyor
	_check(sp != null and sp.kind() == "split" and sp.left_dir() == Vector2i.UP and sp.right_dir() == Vector2i.DOWN, "분배기: 오른쪽을 보면 흐름 기준 왼쪽 = 위, 오른쪽 = 아래")
	_check(net.next_belt(src) == sp and not sp.accepts_dir(Vector2i.DOWN), "뒤에서만 받음 (옆에서는 안 받음)")
	var outs := {out_l: "L", out_f: "F", out_r: "R"}
	var route := func(n: int) -> String:
		var trace := ""
		for i in n:
			src.put("wheat", "bronze", 0.9)
			for k in 8:
				net.tick(0.5)
				var landed := ""
				for b: Conveyor in outs:
					if is_instance_valid(b) and b.has_item():
						landed = outs[b]
						b.clear_item()
				if landed != "":
					trace += landed
					break
		return trace
	var seq: String = route.call(6)
	_check(seq == "LFRLFR", "왼쪽 → 앞 → 오른쪽 돌아가며 (%s)" % seq)
	out_l.put("stone", Quality.NONE, 1.0)  # 왼쪽이 막힘 (물건이 끝에서 기다림)
	outs.erase(out_l)
	var seq2: String = route.call(4)
	_check(seq2 == "FRFR" and out_l.item.id == "stone", "막힌 쪽은 건너뜀 (%s)" % seq2)
	out_l.clear_item()
	outs[out_l] = "L"
	grid.remove(out_f)
	outs.erase(out_f)
	await get_tree().process_frame
	var seq3: String = route.call(4)
	_check(seq3 == "LRLR" or seq3 == "RLRL", "이어진 쪽이 둘이면 반반 (%s)" % seq3)

	# 합류기: 뒤·왼쪽·오른쪽 → 앞, 번갈아 받음
	var mg := grid.place(PlaceableDB.get_def("merger"), o + Vector2i(5, 6), R) as Router
	var in_b := grid.place(belt, o + Vector2i(4, 6), R) as Conveyor
	var in_l := grid.place(belt, o + Vector2i(5, 5), DOWN) as Conveyor
	var in_r := grid.place(belt, o + Vector2i(5, 7), UP) as Conveyor
	var m_out := grid.place(belt, o + Vector2i(6, 6), R) as Conveyor
	_check(mg.accepts_dir(Vector2i.RIGHT) and mg.accepts_dir(Vector2i.DOWN) and mg.accepts_dir(Vector2i.UP) and not mg.accepts_dir(Vector2i.LEFT), "합류기: 뒤·양옆에서 받고 앞에서는 안 받음")
	var names := {in_b: "B", in_l: "L", in_r: "R"}
	var arrivals := ""
	for i in 9:
		for b: Conveyor in names:
			if not b.has_item():
				b.put("carrot", "bronze", 1.0)  # 세 쪽 모두 늘 기다리는 물건이 있음
		for k in 8:
			net.tick(0.5)
			if m_out.has_item():
				break
		m_out.clear_item()
		arrivals += names[_last_into(mg, names)] if mg.last_in != Vector2i.ZERO else "?"
	var fair := arrivals.count("B") >= 2 and arrivals.count("L") >= 2 and arrivals.count("R") >= 2
	_check(fair and not ("BB" in arrivals or "LL" in arrivals or "RR" in arrivals), "세 쪽이 기다리면 번갈아 받음 (%s)" % arrivals)

	# 필터 분배기 (사용자 결정): 정한 물건은 왼쪽·오른쪽, 나머지는 앞
	var fsrc := grid.place(belt, o + Vector2i(1, 10), R) as Conveyor
	var fs := grid.place(PlaceableDB.get_def("filter_splitter"), o + Vector2i(2, 10), R) as Router
	var f_l := grid.place(belt, o + Vector2i(2, 9), UP) as Conveyor
	var f_f := grid.place(belt, o + Vector2i(3, 10), R) as Conveyor
	var f_r := grid.place(belt, o + Vector2i(2, 11), DOWN) as Conveyor
	_check(fs.kind() == "filter" and fs.set_filter_mode("left", "items") and fs.add_filter_item("left", "tomato") and fs.set_filter_mode("right", "processed"), "필터: 왼쪽 = 토마토, 오른쪽 = 가공품")
	var sort := func(id: String) -> String:
		fsrc.put(id, Quality.NONE if not ItemDB.get_item(id).has_quality else "bronze", 0.9)
		for k in 8:
			net.tick(0.5)
			for pair: Array in [[f_l, "L"], [f_f, "F"], [f_r, "R"]]:
				var b: Conveyor = pair[0]
				if b.has_item():
					b.clear_item()
					return pair[1]
		return "-"
	var sorted := [sort.call("tomato"), sort.call("flour"), sort.call("carrot"), sort.call("tomato")]
	_check(sorted == ["L", "R", "F", "L"], "토마토 → 왼쪽, 밀가루 → 오른쪽, 당근 → 앞 %s" % [sorted])
	f_l.put("stone", Quality.NONE, 1.0)
	fsrc.put("tomato", "bronze", 0.9)
	for k in 8:
		net.tick(0.5)
	_check(fs.has_item() and fs.item.id == "tomato" and not f_f.has_item(), "정한 쪽이 막히면 앞으로 새지 않고 기다림")
	f_l.clear_item()
	fs.clear_item()

	# 창: [E] 로 필터 고르기
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	inv.add("eggplant", 1)
	hud.open_router(fs)
	var panel := hud._router
	_check(panel.visible and get_tree().paused and GameState.is_time_paused(), "필터 분배기 창 (게임·시간 멈춤)")
	(panel._options["right"] as OptionButton).select(5)
	(panel._options["right"] as OptionButton).item_selected.emit(5)
	(panel._picks["right"] as Button).button_pressed = true
	panel._on_bag_clicked(_slot_index(inv, "eggplant", ""))
	_check(fs.filters.right.mode == "items" and fs.filters.right.items == ["eggplant"] and (panel._chips["right"] as HBoxContainer).get_child_count() == 1, "창에서 오른쪽 = 지정 아이템 가지")
	hud._close_panels()
	inv.load_data(saved_inv)

	# 건설 모드 화살표: 들어오는 쪽·나가는 쪽
	var sp_ports := BuildMode.router_ports(sp)
	_check(sp_ports.filter(func(p: Dictionary) -> bool: return p.type == "in").size() == 1 and sp_ports.filter(func(p: Dictionary) -> bool: return p.type == "out").size() == 3, "분배기 화살표: 들어옴 1 · 나감 3")

	# 저장 / 불러오기: 필터·차례·들고 있는 물건
	fs.put("tomato", "silver", 0.5, Vector2i.RIGHT)
	var fs_state := fs.save_state()
	var sp_state := sp.save_state()
	world.save_manager.save_game("manual")
	fs.set_filter_mode("left", "none")
	world.save_manager.load_game()
	fs = grid.object_at(o + Vector2i(2, 10)) as Router
	sp = grid.object_at(o + Vector2i(2, 2)) as Router
	_check(fs != null and fs.save_state() == fs_state and fs.matches("left", ItemDB.get_item("tomato")) and sp.save_state() == sp_state, "저장·불러오기 (필터·차례·물건)")

	# 정리
	for obj in grid.objects().duplicate():
		if Rect2i(o, Vector2i(10, 13)).has_point(obj.cell):
			obj.take_contents()
			grid.remove(obj)
	await get_tree().process_frame


func _test_sky_market(world: FarmWorld, hud: HUD) -> void:
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var saved_day := GameState.day
	var player := world.player
	var cam := player.camera
	GameState.unlocks.erase(SkyMarket.UNLOCK)

	# 분류 (§86, §87)
	var cat := func(id: String) -> String: return SkyMarket.category_of(ItemDB.get_item(id))
	_check([cat.call("carrot"), cat.call("strawberry"), cat.call("wheat"), cat.call("flour"), cat.call("hoe"), cat.call("wood")] == ["vegetable", "fruit", "grain", "processed", "", ""], "분류: 채소·과일·곡물·가공품, 도구·재료는 안 팔림")
	_check(Pricing.channel_name(SkyMarket.CHANNEL) == "하늘시장", "판매 요약 이름: 하늘시장")

	# 시세: 하루 한 번 정해지고 그날은 고정 (§85)
	SkyMarket.rng.seed = 7
	GameState.sky_market = {}
	var t1 := SkyMarket.today().duplicate(true)
	_check(int(t1.day) == GameState.day and t1.items.has("carrot") and t1.items.has("flour") and SkyMarket.today() == t1, "오늘 시세는 한 번 정해지면 그날 고정")
	var carrot := ItemDB.get_item("carrot")
	var expect := Pricing.price_from(roundi(carrot.sell_price * float(t1.items.carrot)), carrot, "silver")
	_check(SkyMarket.unit_price(carrot, "silver") == expect and expect > 0, "당근 실버 오늘 값 %d G (기준가 × 오늘 배율 → 품질 배율)" % expect)
	GameState.day += 1
	_check(int(SkyMarket.today().day) == GameState.day, "다음 날이 되면 새 시세")
	GameState.day -= 1
	GameState.sky_market = t1.duplicate(true)

	# 흔들림: 가공품이 곡물보다 크게 움직이고, 이벤트가 가끔 (§86, §88)
	var spread := func(c: String, samples: Array) -> float:
		var lo := 99.0
		var hi := 0.0
		for r: Dictionary in samples:
			lo = minf(lo, float(r.categories[c]))
			hi = maxf(hi, float(r.categories[c]))
		return hi - lo
	var rolls := []
	var events := 0
	var event_ok := true
	for i in 300:
		var r := SkyMarket.roll(i + 1)
		rolls.append(r)
		if str(r.event) != "":
			events += 1
		if str(r.event) == "grain_boom":
			event_ok = event_ok and float(r.categories.grain) <= 1.12 * 0.75 + 0.01
		for id: String in r.items:
			event_ok = event_ok and float(r.items[id]) >= 0.5 and float(r.items[id]) <= 2.0
	_check(spread.call("processed", rolls) > spread.call("grain", rolls) * 1.5, "가공품 흔들림 %.2f > 곡물 %.2f" % [spread.call("processed", rolls), spread.call("grain", rolls)])
	_check(events >= 15 and events <= 60 and event_ok, "300일 중 이벤트 %d번 (12%%쯤), 곡물 풍년엔 곡물값 내림, 배율 0.5~2.0" % events)

	# 비행선 정류장: 복구 전 (§89)
	var stations := world.buildings.filter(func(b: Interactable) -> bool: return b is SkyStation)
	_check(stations.size() == 1 and MapLayout.char_at(Vector2i(106, 45)) == "A" and stations[0].prompt.contains("오래된"), "광장에 오래된 비행선 정류장")
	if stations.is_empty():
		return
	var station: SkyStation = stations[0]
	_check(not world.travel("sky") and not SkyMarket.is_open(), "복구 전에는 비행선이 없음")
	player.global_position = station.interact_point()
	await get_tree().physics_frame
	player._interact()
	_check(hud._sky_station.visible and get_tree().paused and hud._sky_station._restore.disabled, "[E] → 복구 창 (재료가 없으면 복구 못 함)")
	var cost := SkyMarket.station_cost()
	inv.load_data([])
	GameState.money = int(cost.price) + 500
	for id: String in cost.materials:
		inv.add(id, int(cost.materials[id]))
	hud._sky_station.refresh()
	_check(not hud._sky_station._restore.disabled, "돈·재료가 모이면 [복구하기]")
	hud._sky_station.restore()
	_check(SkyMarket.is_open() and GameState.money == 500 and inv.count_of("wood") == 0 and not hud._sky_station.visible and station.prompt.contains("비행선 타기"), "복구 → 하늘시장 열림, 돈·재료 사용, 정류장 안내 바뀜")
	hud._close_panels()

	# 비행: 편도 1시간, 하늘섬 카메라 범위 (§90)
	GameState.set_clock(9 * 60)
	var before_min := GameState.minutes
	player.global_position = station.interact_point()
	await get_tree().physics_frame
	player._interact()
	_check(world.is_on_sky_island() and cam.limit_left == int(SkyIsland.view_rect().position.x) and cam.limit_right == int(SkyIsland.view_rect().end.x), "정류장 [E] → 하늘섬 도착, 카메라는 섬 범위")
	_check(GameState.minutes - before_min >= 50 and GameState.minutes - before_min <= 70, "비행에 게임 시간 약 1시간 (%d분)" % (GameState.minutes - before_min))
	for i in 60:
		player.velocity = Vector2(-240, 0)
		player.move_and_slide()
	_check(SkyIsland.island_rect().has_point(player.global_position), "섬 밖으로 걸어 나갈 수 없음")

	# 가판대: 오늘 값으로 팔기
	var market := world.sky_island.market
	inv.load_data([])
	inv.add("carrot", 5, "silver")
	inv.add("flour", 2)
	inv.add("hoe", 1)
	player.global_position = market.interact_point()
	await get_tree().physics_frame
	player._interact()
	var panel := hud._sky_market
	_check(panel.visible and get_tree().paused and panel._list.get_child_count() == 2, "가판대 [E] → 하늘시장 창 (팔 수 있는 줄 2개: 당근·밀가루)")
	var money := GameState.money
	var unit := SkyMarket.unit_price(carrot, "silver")
	var earned := SkyMarketPanel.sell("carrot", "silver", 5)
	_check(earned == unit * 5 and GameState.money == money + earned and inv.count_of("carrot") == 0 and int(GameState.today_sales.get(SkyMarket.CHANNEL, 0)) >= earned, "당근 5개 판매 +%d G (판매 요약에 하늘시장)" % earned)
	_check(SkyMarketPanel.sell("hoe", "", 1) == 0 and inv.count_of("hoe") == 1, "도구는 안 팔림")
	hud._close_panels()

	# 저장 / 불러오기: 섬에서 저장하면 섬에서 이어서, 그날 시세 그대로
	var prices := GameState.sky_market.duplicate(true)
	world.save_manager.save_game("manual")
	GameState.sky_market = {}
	world.save_manager.load_game()
	_check(world.is_on_sky_island() and cam.limit_left == int(SkyIsland.view_rect().position.x), "섬에서 저장·불러오기: 섬에서 이어서 (섬 카메라)")
	var same_prices := int(GameState.sky_market.get("day", -1)) == int(prices.day) and str(GameState.sky_market.get("event")) == str(prices.event)
	for id: String in prices.items:
		var it := ItemDB.get_item(id)
		same_prices = same_prices and Pricing.price_from(roundi(it.sell_price * float(prices.items[id])), it, "gold") == SkyMarket.unit_price(it, "gold")
	_check(same_prices, "불러와도 그날 시세 그대로 (모든 품목 값 같음)")

	# 돌아가기
	player.global_position = world.sky_island.dock.interact_point()
	await get_tree().physics_frame
	player._interact()
	_check(not world.is_on_sky_island() and cam.limit_left == 0 and player.global_position.distance_to(station.interact_point()) < 24.0, "선착장 [E] → 광장 정류장으로, 카메라는 농장 범위")

	# 늦으면 비행선이 안 뜸 / 섬에서 하루가 끝나면 집에서 깨어남
	GameState.set_clock(GameState.day_end - 30)
	_check(not world.travel("sky") and not world.is_on_sky_island(), "늦은 밤에는 비행선이 뜨지 않음")
	GameState.set_clock(10 * 60)
	world.travel("sky")
	GameState.sleep()
	hud._close_panels()
	_check(not world.is_on_sky_island() and player.global_position == world.home_position and cam.limit_left == 0, "섬에서 하루가 끝나면 집 앞에서 깨어남")

	GameState.unlocks.erase(SkyMarket.UNLOCK)
	station.refresh()
	GameState.day = saved_day
	inv.load_data(saved_inv)
	await get_tree().process_frame


func _test_water(world: FarmWorld, hud: HUD) -> void:
	var grid := world.build
	var farm := world.farm
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var saved_day := GameState.day
	GameState.day = 2
	var pump_def := PlaceableDB.get_def("pump")
	var tank_def := PlaceableDB.get_def("water_tank")
	_check(pump_def != null and pump_def.data.get("needs_water", false) and tank_def != null and tank_def.size == Vector2i(2, 2), "펌프(1x1, 물가 전용)·물탱크(2x2) 정의")

	# 자리: 8x6 빈 밭 땅 (물탱크·발전기·스프링클러 + 밭)
	var o := Vector2i(-1, -1)
	var cells: Array = farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 6:
			for x in 8:
				var fc := c + Vector2i(x, y)
				if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or farm.tiles.has(fc):
					ok = false
		if ok:
			o = c
			break
	_check(o.x >= 0, "물 점검 자리 %s" % o)
	if o.x < 0:
		return
	for y in 6:
		for x in 8:
			world.obstacles.remove(o + Vector2i(x, y))
	await get_tree().process_frame
	world.player.global_position = world.cell_center(_find_char("s"))

	# 물탱크가 없으면 스프링클러는 못 적심 (사용자 결정: 물탱크 물을 씀)
	var sp_at := o + Vector2i(5, 3)
	var plus := FarmArea.cells(sp_at, {"shape": "plus", "radius": 1})
	for c in plus:
		farm.till(c)
	grid.place(PlaceableDB.get_def("sprinkler_1"), sp_at)
	grid.start_day()
	_check(plus.all(func(c: Vector2i) -> bool: return not farm.get_tile(c).watered) and grid.sprinkler_missed == 4, "물탱크가 없으면 4칸 모두 못 적심 (아침 알림)")
	await get_tree().process_frame
	_check(hud._water_label.visible and hud._water_label.text == "물 0 / 0 없음!", "HUD: 스프링클러는 있는데 물이 없으면 빨간 '없음!' (%s)" % hud._water_label.text)

	# 물탱크 → 지역 물통
	var tank := grid.place(tank_def, o) as WaterTank
	_check(tank != null and grid.water_status().capacity == 200.0 and grid.water_status().stored == 0.0, "물탱크 1개 → 지역 물통 0 / 200")

	# 펌프: 물가 옆에만 (§14, 사용자 결정)
	_check(not grid.check(pump_def, o + Vector2i(7, 0)).ok and grid.check(pump_def, o + Vector2i(7, 0)).reason.begins_with("물가"), "물가가 아니면 펌프를 못 지음 (%s)" % grid.check(pump_def, o + Vector2i(7, 0)).reason)
	var shore := Vector2i(8, 34)
	world.obstacles.remove(shore)
	await get_tree().process_frame
	_check(BuildGrid.touches_water(pump_def, shore) and MapLayout.char_at(shore + Vector2i.DOWN) == "~", "연못가 칸 %s 은 물에 맞닿음" % shore)
	var pump := grid.place(pump_def, shore) as Pump
	_check(pump != null, "연못가에 펌프 설치")
	if pump == null:
		return

	# 전기가 없으면 못 퍼 올림 → 발전기로 퍼 올림 (퍼 올리는 동안만 전기)
	_check(pump.pump(60.0) == 0.0 and pump.starved, "전기가 없으면 못 퍼 올림")
	var gen := grid.place(PlaceableDB.get_def("small_generator"), o + Vector2i(2, 0)) as Generator
	inv.add("wood", 10)
	gen.deposit(inv, "wood", 10)
	gen.produce(300.0)
	var e0 := gen.energy
	var got := pump.pump(60.0)
	_check(absf(got - 60.0) < 0.01 and absf((e0 - gen.energy) - 20.0) < 0.01 and not pump.starved, "1시간에 물 60, 전기 20 (%.1f)" % (e0 - gen.energy))
	pump.pump(600.0)
	var e1 := gen.energy
	_check(absf(tank.water - 200.0) < 0.01 and pump.pump(60.0) == 0.0 and absf(gen.energy - e1) < 0.01 and pump.power_demand() == 0, "물통이 가득 차면 쉬고 전기도 안 씀")

	# 아침: 적신 칸마다 물 1
	for c in plus:
		farm.get_tile(c).watered = false
	grid.start_day()
	_check(plus.all(func(c: Vector2i) -> bool: return farm.get_tile(c).watered) and absf(tank.water - 196.0) < 0.01 and grid.sprinkler_missed == 0, "아침에 4칸 적시고 물 4 사용 (남은 물 %.0f)" % tank.water)
	grid.start_day()
	_check(absf(tank.water - 196.0) < 0.01, "이미 젖은 칸(비 오는 날 등)에는 물을 안 씀")
	for c in plus:
		farm.get_tile(c).watered = false
	tank.water = 2.0
	grid.start_day()
	var wet := plus.filter(func(c: Vector2i) -> bool: return farm.get_tile(c).watered).size()
	_check(wet == 2 and grid.sprinkler_missed == 2 and tank.water < 0.01, "물이 2뿐이면 2칸만 적시고 2칸은 못 적심")

	# 밤에도 퍼 올리고 아침 요약에 나옴
	var report := {}
	grid.night_production(report, 60.0)
	_check(absf(float(report.get("night_production", {}).get("water", 0.0)) - 60.0) < 0.5, "야간 1시간에 물 60 → 야간 요약에 기록")
	hud._night.open(GameState.day, {"items": {"carrot": 1}, "energy": 120.0, "water": 60.0})
	_check(hud._night._energy.text.contains("펌프가 퍼 올린 물 +60"), "야간 요약에 '펌프가 퍼 올린 물 +60'")
	hud._close_panels()
	await get_tree().process_frame
	_check(hud._water_label.text.begins_with("물 60 / 200"), "HUD 물 표시 (%s)" % hud._water_label.text)

	# 물탱크 2개 → 물통 400, 저장 / 불러오기
	var tank2 := grid.place(tank_def, o + Vector2i(0, 2)) as WaterTank
	_check(tank2 != null and grid.water_status().capacity == 400.0, "물탱크 2개 → 지역 물통 400")
	var state := tank.save_state()
	world.save_manager.save_game("manual")
	tank.water = 0.0
	world.save_manager.load_game()
	tank = grid.object_at(o) as WaterTank
	_check(tank != null and tank.save_state() == state and grid.object_at(shore) is Pump, "물탱크 물·펌프 저장·불러오기")

	# 정리
	for obj in grid.objects().duplicate():
		if Rect2i(o, Vector2i(8, 6)).has_point(obj.cell) or obj.cell == shore:
			obj.take_contents()
			grid.remove(obj)
	for c in plus:
		farm.untill(c)
	inv.load_data(saved_inv)
	GameState.day = saved_day
	await get_tree().process_frame


func _test_tool_cooldown(world: FarmWorld) -> void:
	var player := world.player
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	inv.load_data([])  # 빈손으로 휘둘러서 밭·장애물에 영향이 없게
	GameState.select_slot(0)
	player.global_position = world.home_position
	player._next_use_ms = 0
	_check(player.tool_cooldown == 0.5, "도구 딜레이 0.5초 (player.json)")
	var uses := player.tool_uses
	_check(player.try_use_tool() and not player.try_use_tool() and player.tool_uses == uses + 1, "바로 다시 누르면 무시")
	await _wait_real(600)  # 헤드리스에서는 게임 시간이 실제보다 조금 빨리 가서 타이머 대신 실제 시각으로 기다린다
	_check(player.try_use_tool() and player.tool_uses == uses + 2, "0.5초가 지나면 다시 씀")

	# 누르고 있으면 0.5초마다 계속 (실제 입력: Space 누른 채 1.1초)
	await _wait_real(600)
	uses = player.tool_uses
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	get_viewport().push_input(space, true)
	await _wait_real(1100)
	var release := space.duplicate()
	release.pressed = false
	Input.parse_input_event(release)
	get_viewport().push_input(release, true)
	await get_tree().physics_frame
	var held := player.tool_uses - uses
	_check(held == 3, "누르고 있으면 0.5초마다 계속 (1.1초에 %d번)" % held)
	await _wait_real(600)
	_check(player.tool_uses - uses == held, "떼면 멈춤")
	inv.load_data(saved_inv)


## 광장 주민·동물 (사용자 요청: 고양이·강아지·벤치 할머니·바구니 든 아이). 쓰다듬기는 하트만 (보상 없음, 사용자 결정)
func _test_townsfolk(world: FarmWorld, hud: HUD) -> void:
	var folk := {}
	for t: Townsfolk in world.townsfolk:
		folk[str(t.data.id)] = t
	_check(folk.size() == 4 and folk.has("cat") and folk.has("dog") and folk.has("grandma") and folk.has("kid"), "광장 주민·동물 4 (고양이·강아지·할머니·아이)")
	_check(world.townsfolk.all(func(t: Townsfolk) -> bool: return Interior.room_at(t.position) == "" and t.position.x >= 53 * FarmWorld.TILE and t.get_children().all(func(c: Node) -> bool: return not c is PhysicsBody2D)), "모두 광장에, 길을 막지 않음 (충돌 없음)")
	GameState.set_clock(10 * 60)
	var toasts: Array[String] = []
	var grab := func(msg: String) -> void: toasts.append(msg)
	Events.toast.connect(grab)
	var cat: Townsfolk = folk.cat
	var money := GameState.money
	var bag := GameState.inventory.to_data()
	cat.interact(world.player)
	_check(toasts.has("나비가 골골거려요.") and cat.get_child_count() >= 2 and GameState.money == money and GameState.inventory.to_data() == bag, "고양이 쓰다듬기 → 하트 + 골골 (보상 없음)")
	Events.toast.disconnect(grab)
	var grandma: Townsfolk = folk.grandma
	grandma.interact(world.player)
	_check(hud._dialog.visible and hud._dialog._name.text == "순자 할머니" and hud._dialog._line.text != "" and get_tree().paused, "할머니 말 걸기 → 대화 창 (%s)" % hud._dialog._line.text)
	hud._dialog.choose("")
	_check(not hud._dialog.visible and not get_tree().paused, "대화 닫기")
	_check(grandma.line_for(1) != grandma.line_for(2) or grandma.line_for(1) != grandma.line_for(3), "할머니 대사는 날마다 바뀜")

	# 아이: 정해진 곳 사이를 돌길로 오감
	var kid: Townsfolk = folk.kid
	kid.process_mode = Node.PROCESS_MODE_INHERIT
	kid._rest = 0.01
	kid.step(0.02)
	var first_leg := kid.path.size()
	var start := kid.position
	for i in 600:
		kid.step(0.1)
	_check(first_leg > 5 and kid.position.distance_to(start) > 64.0, "아이가 돌길을 따라 다음 장소로 감 (%d칸 길)" % first_leg)
	_check(kid.path.all(func(p: Vector2) -> bool: return MapLayout.char_at(world.world_to_cell(p)) == "p"), "아이는 돌길 위로만")
	# 고양이: 가까이 가면 따라옴, 강아지: 돌아다님
	cat.process_mode = Node.PROCESS_MODE_INHERIT
	cat._napping = false
	cat._follow_cooldown = 0.0
	var p0 := world.player.global_position
	world.player.global_position = cat.global_position + Vector2(30, 0)
	cat.step(0.1)
	_check(cat._follow_left > 0.0, "고양이 근처에 가면 따라오기 시작")
	var dog: Townsfolk = folk.dog
	var d0 := dog.position
	dog._rest = 0.01
	for i in 100:
		dog.step(0.1)
	_check(dog.position != d0 and dog.position.distance_to(dog.home) <= dog._roam() * 1.5, "강아지는 광장 안에서 돌아다님")
	world.player.global_position = p0
	# 밤 9시: 사람은 집에 가고 고양이는 잠듦, 아침엔 돌아옴
	GameState.set_clock(21 * 60 + 30)
	for t: Townsfolk in world.townsfolk:
		t.step(0.1)
	_check(not kid.visible and not grandma.visible and not kid.can_interact(kid.interact_point()) and cat._napping and dog.visible, "밤 9시 이후: 아이·할머니는 집에, 고양이는 잠")
	GameState.set_clock(8 * 60)
	for t: Townsfolk in world.townsfolk:
		t.step(0.1)
	_check(kid.visible and grandma.visible and kid.position == kid.home, "아침: 처음 자리로 돌아옴")
	await get_tree().process_frame


## 중급 가공기 + 2급 레시피 (사용자 결정: 새 기계 · 새 레시피만 2급 · 봄 양배추 · 상급은 나중에)
## 용광로 (사용자 결정: 1x1, 기계상점, 손으로 넣고 꺼내기, 광석 5 + 석탄 1 → 주괴 1) + 도구 3·4단계 (돌→구리→철→금, 강화 재료는 주괴)
func _test_furnace_tools(world: FarmWorld) -> void:
	var grid := world.build
	var farm := world.farm
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var saved_money := GameState.money
	var fdef := PlaceableDB.get_def("furnace")
	_check(fdef != null and fdef.size == Vector2i(1, 1) and fdef.machine_item() == ItemDB.get_item("furnace") and ItemDB.get_item("furnace").shop == "smith", "용광로: 1x1, 대장간에서 파는 기계 (스토리 결정 6)")
	var spot := _free_clear_cell(world)
	var f := grid.place(fdef, spot) as Furnace
	_check(f != null and grid.object_at(spot) == f, "용광로 설치")
	if f == null:
		return
	inv.load_data([])
	inv.add("copper_ore", 7)
	_check(f.start(inv, "copper_ore").contains("석탄") and inv.count_of("copper_ore") == 7 and not f.is_working(), "석탄이 없으면 못 구움")
	inv.add("coal", 3)
	_check(f.start(inv, "stone").contains("광석"), "광석이 아니면 안 들어감")
	inv.add("pickaxe")
	var slot := -1
	for i in inv.size():
		if inv.item_at(i) and inv.item_at(i).id == "copper_ore":
			slot = i
	_check(f.use_held_item(inv, slot) and f.is_working() and inv.count_of("copper_ore") == 4 and inv.count_of("coal") == 2, "광석을 들고 클릭 → 굽기 시작 (광석 3 · 석탄 1 빠짐)")
	_check(not f.start(inv, "copper_ore").is_empty(), "굽는 중엔 더 못 넣음 (한 번에 하나)")
	f.on_time(59.0)
	_check(f.output == 0 and f.is_working(), "구리 주괴: 게임 시계 59분엔 아직")
	f.on_time(1.0)
	_check(f.output == 1 and f.output_id == "copper_bar" and not f.is_working() and f._icon.visible and f.prompt.contains("꺼내기"), "60분 → 구리 주괴 1 (위에 아이콘)")
	inv.add("iron_ore", 5)
	_check(f.start(inv, "iron_ore").contains("먼저 꺼내"), "다른 주괴가 남아 있으면 먼저 꺼내야")
	f.interact(world.player)
	_check(inv.count_of("copper_bar") == 1 and f.output == 0, "[E] → 구리 주괴를 가방으로")
	_check(f.start(inv, "iron_ore") == "" and is_equal_approx(f.minutes_left, 90.0), "철 주괴는 90분")
	# 밤사이: 굽던 것만 마저
	var report := {}
	f.on_night_production(world, report, 120.0)
	_check(f.output == 1 and f.output_id == "iron_bar" and int(report.get("night_production", {}).get("processed", 0)) == 1, "밤사이 굽던 철 주괴 완성")
	# 저장 · 철거 환불
	inv.add("gold_ore", 5)
	f.output = 0
	f.output_id = ""
	f.start(inv, "gold_ore")
	var state := f.save_state()
	var f2 := Furnace.new()
	f2.def = fdef
	f2.load_state(state)
	_check(f2.smelting == "gold_ore" and is_equal_approx(f2.minutes_left, 120.0), "굽던 상태 저장·불러오기 (금 주괴 2시간)")
	f2.free()
	var refund := f.contents().map(func(st: Dictionary) -> String: return "%s %d" % [st.id, st.count])
	_check(refund == ["gold_ore 3", "coal 1"], "철거하면 굽던 광석·석탄을 돌려받음 %s" % [refund])
	# 컨베이어 (사용자 결정: 이 용광로에 입구·출구): 광석·석탄을 받아 두고 모이면 알아서 굽고, 주괴를 내보냄
	f.take_contents()
	_check((f.def.data.get("ports", []) as Array).size() == 2 and f.def.rotatable, "용광로: 입구·출구 하나씩, 돌릴 수 있음")
	_check(not f.accept_item("wheat", Quality.NONE) and f.accept_item("coal", Quality.NONE), "입구: 광석·석탄만 받음")
	for i in 2:
		f.accept_item("iron_ore", Quality.NONE)
	_check(not f.is_working() and f.ore_in_total() == 2, "광석 2개로는 아직 안 구움")
	f.accept_item("iron_ore", Quality.NONE)
	_check(f.is_working() and f.smelting == "iron_ore" and f.ore_in_total() == 0 and f.coal_in == 0, "3개 + 석탄 → 알아서 굽기 시작")
	for i in 12:
		f.accept_item("iron_ore", Quality.NONE)
	_check(f.ore_in_total() == f.ore_buffer(), "받아 두는 광석은 %d개까지" % f.ore_buffer())
	f.accept_item("coal", Quality.NONE)
	f.on_time(90.0)
	_check(f.output == 1 and f.is_working() and f.ore_in_total() == 7, "다 구우면 받아 둔 것으로 바로 다음 굽기")
	var out := f.provide_item()
	_check(out.get("id", "") == "iron_bar" and f.output == 0, "출구: 철 주괴를 내보냄")
	var night := {}
	f.accept_item("coal", Quality.NONE)
	f.on_night_production(world, night, 300.0)
	_check(f.output == 2 and f.ore_in_total() == 4 and f.coal_in == 0, "밤사이 받아 둔 것도 이어서 구움, 석탄이 떨어지면 멈춤 (%d)" % f.output)
	var st2 := f.save_state()
	_check(st2.has("ore_in") and st2.has("coal_in"), "받아 둔 광석·석탄도 저장")
	grid.remove(f)

	# 도구 3·4단계
	_check(ItemDB.get_item("hoe_2").name == "구리 괭이" and ItemDB.get_item("pickaxe_3").name == "철 곡괭이" and ItemDB.get_item("axe_4").name == "금 도끼", "도구 이름: 돌(기본)·구리·철·금")
	var chain_ok := true
	for t: String in ["hoe", "watering_can", "axe", "pickaxe"]:
		var t2 := ItemDB.get_item(t + "_2")
		var t3 := ItemDB.get_item(t + "_3")
		chain_ok = chain_ok and ToolUpgrade.next_of(t2) == t3 and ToolUpgrade.materials_of(t2).keys() == ["iron_bar"] and int(ToolUpgrade.materials_of(t2).iron_bar) == 5 and ToolUpgrade.price_of(t2) == int(_econ().tools.upgrade_price[t][1]) 				and ToolUpgrade.next_of(t3) == ItemDB.get_item(t + "_4") and ToolUpgrade.materials_of(t3).keys() == ["gold_bar"] and int(ToolUpgrade.materials_of(t3).gold_bar) == 8 and ToolUpgrade.price_of(t3) == int(_econ().tools.upgrade_price[t][2]) 				and int(ToolUpgrade.materials_of(ItemDB.get_item(t)).copper_bar) == 3 and ToolUpgrade.price_of(ItemDB.get_item(t)) == int(_econ().tools.upgrade_price[t][0]) 				and ToolUpgrade.next_of(ItemDB.get_item(t + "_4")) == null and t3.tier == 3 and ItemDB.get_item(t + "_4").tier == 4
	_check(chain_ok, "강화 경로: 구리(구리 주괴 3) → 철(철 주괴 5) → 금(금 주괴 8), 값은 경제 기준, 금이 최고")
	inv.load_data([])
	inv.add("hoe_2")
	inv.add("iron_bar", 5)
	inv.add("gold_bar", 8)
	GameState.money = 100000
	_check(ToolUpgrade.apply(inv, 0) and inv.item_at(0).id == "hoe_3" and inv.count_of("iron_bar") == 0 and GameState.money == 98200, "구리 괭이 → 철 괭이 (1,800 G + 철 주괴 5)")
	_check(ToolUpgrade.apply(inv, 0) and inv.item_at(0).id == "hoe_4" and inv.count_of("gold_bar") == 0 and GameState.money == 91700, "철 괭이 → 금 괭이 (6,500 G + 금 주괴 8)")
	# 넓은 범위: 철 괭이 5칸, 금 괭이 앞쪽 3x3
	var area_free := func(origin: Vector2i, w: int, h: int) -> bool:
		for y in h:
			for x in w:
				var c := origin + Vector2i(x, y)
				if not farm.is_farmable(c) or world.obstacles.is_blocked(c) or farm.tiles.has(c) or grid.is_occupied(c):
					return false
		return true
	var origin := Vector2i(-1, -1)
	var cells: Array = farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		if area_free.call(c, 9, 5):
			origin = c
			break
	_check(origin.x >= 0, "넓은 밭 자리 찾음 %s" % origin)
	if origin.x >= 0:
		var count_tiles := func() -> int:
			var n := 0
			for y in 5:
				for x in 9:
					if farm.tiles.has(origin + Vector2i(x, y)):
						n += 1
			return n
		var clear_tiles := func() -> void:
			for y in 5:
				for x in 9:
					farm.tiles.erase(origin + Vector2i(x, y))
		var hoe3 := ItemDB.get_item("hoe_3")
		var hoe4 := ItemDB.get_item("hoe_4")
		# 단계: 1 = 1칸, 2 = 앞으로 3칸, 3 = 앞쪽 3x3, 4 = 앞쪽 5x5. 도구 최대 단계까지만
		var sizes := [1, 2, 3, 4].map(func(lv: int) -> int:
			clear_tiles.call()
			farm.use_item(origin + Vector2i(2, 0), hoe4, Vector2i.DOWN, lv)
			return count_tiles.call())
		_check(sizes == [1, 3, 9, 25], "금 괭이: 그냥 1칸 · 1초 3칸 · 2초 3x3 · 3초 5x5 %s" % [sizes])
		clear_tiles.call()
		farm.use_item(origin + Vector2i(2, 0), hoe3, Vector2i.DOWN, 4)
		_check(count_tiles.call() == 9, "철 괭이는 3초를 눌러도 3x3까지")
		clear_tiles.call()
		farm.use_item(origin, hoe3, Vector2i.RIGHT, 2)
		var line: bool = range(3).all(func(i: int) -> bool: return farm.tiles.has(origin + Vector2i(i, 0))) and count_tiles.call() == 3
		_check(line, "1초 = 바라보는 방향으로 3칸 (오른쪽)")
		var sq := origin + Vector2i(1, 2)
		farm.use_item(sq, hoe3, Vector2i.DOWN, 3)
		var n9 := 0
		for y in range(2, 5):
			for x in range(0, 3):
				if farm.tiles.has(origin + Vector2i(x, y)):
					n9 += 1
		_check(n9 == 9 and not farm.tiles.has(origin + Vector2i(3, 2)), "철 괭이 2초: 앞쪽 3x3 (클릭한 칸이 가까운 가장자리 가운데)")
		# 물뿌리개도 같은 단계, 물이 모자라면 거기까지
		inv.load_data([])
		inv.add("watering_can_3")
		inv.set_slot_value(0, "water", 30)
		WateringCan.use(world, origin, inv, 0, Vector2i.RIGHT, 2)
		var wet := range(3).all(func(i: int) -> bool: return farm.get_tile(origin + Vector2i(i, 0)).watered)
		_check(wet and WateringCan.water_left(inv, 0) == 27, "철 물뿌리개 1초: 3칸에 물 (물 3 씀)")
		inv.load_data([])
		inv.add("watering_can_4")
		inv.set_slot_value(0, "water", 5)
		_check(WateringCan.use(world, sq, inv, 0, Vector2i.DOWN, 3) and WateringCan.water_left(inv, 0) == 0, "금 물뿌리개 2초: 물이 5뿐이면 5칸만 주고 멈춤")
		var watered := 0
		for y in range(2, 5):
			for x in range(0, 3):
				if farm.get_tile(origin + Vector2i(x, y)).watered:
					watered += 1
		_check(watered == 5 and ItemDB.get_item("watering_can_4").capacity == 48 and ItemDB.get_item("watering_can_3").capacity == 32, "금 물뿌리개 용량 48 · 철 32 (경제 기준)")
		# 플레이어: 꾹 누르기 (1초마다 한 단계, 떼면 씀, 바닥에 미리보기)
		clear_tiles.call()
		inv.load_data([])
		inv.add("hoe_4")
		GameState.select_slot(0)
		var player := world.player
		player.global_position = world.cell_center(origin + Vector2i(4, 0))
		player.facing = Vector2i.DOWN
		_check(Player.is_chargeable(hoe4) and not Player.is_chargeable(ItemDB.get_item("hoe")) and not Player.is_chargeable(ItemDB.get_item("pickaxe_4")), "꾹 누르기: 구리 이상 괭이·물뿌리개만 (돌 괭이는 바로)")
		player.start_charge()
		player._charge = 2.2
		_check(player.charge_level() == 3, "2.2초 누름 → 3단계")
		player._physics_process(0.0)
		_check(farm._preview.size() == 9, "누르는 동안 바닥에 3x3 미리보기")
		player.release_charge()
		_check(count_tiles.call() == 9 and farm._preview.is_empty() and player._charge < 0.0, "떼면 3x3 을 갈고 미리보기 사라짐")
		player.start_charge()
		player._charge = 9.0
		_check(player.charge_level() == 4, "오래 눌러도 금 괭이 최대 4단계")
		inv.load_data([])
		player._physics_process(0.0)
		_check(player._charge < 0.0, "손에 든 것이 바뀌면 꾹 누르기 취소")
		for y in 5:
			for x in 9:
				farm.tiles.erase(origin + Vector2i(x, y))
		farm.queue_redraw()
	# 금 바위: 돌 곡괭이로도 (5번), 금 곡괭이는 1번. 광산 15층부터 · 20층 보물 층
	var gold := ObstacleDB.get_def("mine_gold")
	_check(gold != null and gold.tier == 1 and gold.hits == 5 and ItemDB.get_item("pickaxe_4").power >= gold.hits, "금 바위: 돌 곡괭이 5번 · 금 곡괭이 1번")
	_check(Mine.rock_weights(16).has("mine_gold") and not Mine.rock_weights(14).has("mine_gold") and Mine.rock_weights(20).has("mine_gold") and not Mine.rock_weights(10).has("mine_gold"), "금 바위는 15층부터 + 20층 보물 층")
	_check(ItemDB.get_item("pickaxe_4").power > ItemDB.get_item("pickaxe_3").power and ItemDB.get_item("pickaxe_3").power > ItemDB.get_item("pickaxe_2").power, "곡괭이 세기 2 → 3 → 5")
	inv.load_data(saved_inv)
	GameState.money = saved_money


## 스토리·메인 퀘스트·기술 발전 1단계 (명세 v1.0 + 사용자 결정): 데이터 · 퀘스트 상태 · MQ01~05 · 보상 한 번 · 저장 · 기존 저장(legacy)
func _test_story(world: FarmWorld) -> void:
	var qm := world.quests
	var inv := GameState.inventory
	var farm := world.farm
	var player := world.player
	var saved_story := qm.to_data()
	var saved_inv := inv.to_data()
	var saved_money := GameState.money
	var saved_pos := player.global_position

	# 데이터
	var ids := QuestManager.quest_defs().map(func(q: Dictionary) -> String: return q.id)
	var want_ids := []
	for i in 20:
		want_ids.append("MQ%02d" % (i + 1))
	_check(ids == want_ids, "메인 퀘스트 20개 (MQ01~MQ20)")
	_check(QuestManager.era_ids() == ["pioneer", "metal", "mechanical", "electric", "advanced"], "시대 5개 (개척·금속·기계·전기·첨단)")
	var mech: Dictionary = QuestManager.data().projects.mechanical_research
	_check(mech.items == {"copper_bar": 8.0} and int(mech.money) == 500, "기계 기술 복구 = 구리 주괴 8 + 500 G (철 없음, 사용자 결정)")
	var missing := []
	for it: ItemDef in ItemDB.shop_items():
		if it.kind == ItemDef.Kind.MACHINE and QuestManager.tech_for_item(it.id) == "":
			missing.append(it.id)
	for pid: String in ["scarecrow", "shed", "compost_bin", "greenhouse", "conveyor"]:
		if QuestManager.tech_for_item(pid) == "":
			missing.append(pid)
	_check(missing.is_empty(), "기계·건설 시설은 모두 어느 기술에 속함 (빠진 것 %s)" % [missing])
	_check(QuestManager.tech_for_item("furnace") == "basic_smelting" and QuestManager.tech_for_item("sprinkler_3") == "advanced_automation" and QuestManager.tech_for_item("carrot_seed") == "", "용광로 = 금속시대, 상급 스프링클러 = 첨단, 씨앗은 제한 없음")

	# 새 게임: 개척시대, MQ01 만 진행 중
	qm.new_game()
	_check(qm.state_of("MQ01") == QuestManager.ACTIVE and qm.state_of("MQ02") == QuestManager.LOCKED and qm.active_quests().size() == 1, "새 게임: MQ01 만 진행 중")
	_check(qm.era == "pioneer" and qm.is_unlocked("basic_farming") and not qm.is_unlocked("conveyor") and not qm.item_unlocked("manual_processor") and qm.item_unlocked("carrot_seed"), "새 게임: 개척시대, 기본 농사만 열림")

	# MQ01: 농장 안내판 읽기 + 광장 가 보기 → 감자 씨앗 5 (기본 도구 대신, 사용자 결정)
	var signs := world.objects.get_children().filter(func(n: Node) -> bool: return n is InfoSign)
	_check(signs.size() == 1 and (signs[0] as InfoSign).sign_id == "farm_sign" and signs[0].is_in_group("interactables"), "농장 안내판은 [E] 로 읽을 수 있음")
	var potato0 := inv.count_of("potato_seed")
	(signs[0] as InfoSign).interact(player)
	_check(qm.progress_of("MQ01") == [1, 0] and qm.state_of("MQ01") == QuestManager.ACTIVE, "안내판 읽기 1/1, 광장은 아직")
	player.global_position = world.cell_center(Vector2i(60, 20))
	qm._process(0.0)
	_check(qm.state_of("MQ01") == QuestManager.REWARDED and inv.count_of("potato_seed") == potato0 + 5 and qm.state_of("MQ02") == QuestManager.ACTIVE, "광장 도착 → MQ01 완료, 감자 씨앗 +5, MQ02 시작")
	player.global_position = saved_pos

	# MQ02: 잡초 10 · 나뭇가지 5 (진행 중일 때 치운 것만)
	var spot := _free_clear_cell(world)
	var hoe := ItemDB.get_item("hoe")
	var axe := ItemDB.get_item("axe")
	for i in 10:
		world.obstacles.spawn(spot, "weed", i)
		world.obstacles.try_clear(spot, hoe)
	for i in 4:
		world.obstacles.spawn(spot, "branch", i)
		world.obstacles.try_clear(spot, axe)
	_check(qm.progress_of("MQ02") == [10, 4] and qm.state_of("MQ02") == QuestManager.ACTIVE, "잡초 10 · 나뭇가지 4/5")
	# 가방이 가득 차면 보상은 미뤄짐 (완료로 남음)
	var keep := inv.to_data()
	for i in inv.size():
		if inv.get_slot(i) == null:
			inv.slots[i] = {"id": "stone", "count": 99, "quality": ""}
	for i in inv.size():
		var sl: Variant = inv.get_slot(i)
		if sl != null and sl.id == "potato_seed":
			sl.count = 99
	world.obstacles.spawn(spot, "branch", 9)
	world.obstacles.try_clear(spot, axe)
	_check(qm.state_of("MQ02") == QuestManager.COMPLETED and qm.state_of("MQ03") == QuestManager.LOCKED, "가방이 가득 차면 보상을 미루고 완료로 남음")
	inv.load_data(keep)
	_check(qm.state_of("MQ02") == QuestManager.REWARDED and inv.count_of("potato_seed") == potato0 + 10 and qm.state_of("MQ03") == QuestManager.ACTIVE, "자리가 생기면 보상 (감자 씨앗 +5), MQ03 시작")

	# MQ03: 밭 5칸 갈기 · 씨앗 5칸 심기
	var season := Calendar.season_of(GameState.day)
	var seed: ItemDef = null
	for it: ItemDef in ItemDB.shop_items():
		if it.kind == ItemDef.Kind.SEED and Calendar.crop_allowed(it, season) and not it.regrows():
			seed = it
			break
	var plots: Array[Vector2i] = []
	for c: Vector2i in farm.farmable_cells.keys():
		if plots.size() >= 5:
			break
		if not world.obstacles.is_blocked(c) and not farm.tiles.has(c) and not world.build.is_occupied(c) and c.distance_to(spot) > 1:
			plots.append(c)
	var carrot0 := inv.count_of("carrot_seed")
	for c in plots:
		farm.till(c)
	_check(qm.progress_of("MQ03") == [5, 0], "밭 갈기 5/5")
	for c in plots:
		farm.plant(c, seed)
	_check(qm.state_of("MQ03") == QuestManager.REWARDED and inv.count_of("carrot_seed") == carrot0 + 3, "씨앗 5칸 심기 → MQ03 완료, 당근 씨앗 +3")

	# MQ04: 물 주기 5칸 · 물뿌리개 채우기 1번
	var money0 := GameState.money
	for c in plots:
		farm.get_tile(c).watered = false
		farm.water(c)
	_check(qm.progress_of("MQ04") == [5, 0], "물 주기 5/5, 채우기는 아직")
	var well: Well = world.buildings.filter(func(b: Interactable) -> bool: return b is Well)[0]
	var can_i := -1
	for i in inv.size():
		if inv.item_at(i) and inv.item_at(i).tool_type == "watering_can":
			can_i = i
	inv.set_slot_value(can_i, "water", WateringCan.capacity_of(inv, can_i))
	WateringCan.refill(inv, can_i, well)
	_check(qm.progress_of("MQ04")[1] == 0, "가득 찬 물뿌리개는 채운 것으로 안 침")
	inv.set_slot_value(can_i, "water", 0)
	WateringCan.refill(inv, can_i, well)
	_check(qm.state_of("MQ04") == QuestManager.REWARDED and GameState.money == money0 + 100, "우물에서 채우기 → MQ04 완료, +100 G")

	# MQ05: 작물 5개 거두기 (수확량 합계)
	player.facing = Vector2i.DOWN
	var harvested := 0
	for c in plots:
		farm.get_tile(c).days_grown = seed.grow_days
		var before := inv.count_of(seed.grows)
		player._try_harvest(c)
		harvested += inv.count_of(seed.grows) - before
		if harvested >= 5:
			break
	_check(harvested >= 5 and qm.state_of("MQ05") == QuestManager.REWARDED and GameState.money == money0 + 300 and qm.state_of("MQ06") == QuestManager.ACTIVE, "작물 %d개 거둠 → MQ05 완료, +200 G, MQ06 시작" % harvested)

	# 보상은 한 번만: 같은 행동을 더 해도 돈이 그대로
	Events.crop_harvested.emit("carrot", 9)
	Events.sign_read.emit("farm_sign")
	qm._try_rewards()
	_check(GameState.money == money0 + 300 and inv.count_of("potato_seed") == potato0 + 10, "끝난 퀘스트는 다시 보상하지 않음")

	# 저장 · 불러오기: 상태 그대로, 다시 보상하지 않음
	world.save_manager.save_game("manual")
	qm.new_game()
	var money_saved := GameState.money
	world.save_manager.load_game()
	var states := ["MQ01", "MQ02", "MQ03", "MQ04", "MQ05", "MQ06", "MQ07"].map(func(id: String) -> String: return qm.state_of(id))
	_check(states == ["rewarded", "rewarded", "rewarded", "rewarded", "rewarded", "active", "locked"] and not qm.legacy and qm.era == "pioneer", "저장·불러오기 후 퀘스트 상태 그대로 %s" % [states])
	_check(GameState.money == money_saved, "불러와도 보상을 다시 주지 않음")

	# MQ17: 받을 때 밀 4개 한 번 (저장에 기록, 사용자 결정 2)
	for id: String in ["MQ06", "MQ07", "MQ08", "MQ09", "MQ10", "MQ11", "MQ12", "MQ13", "MQ14", "MQ15", "MQ16"]:
		qm.quests[id].state = QuestManager.REWARDED
	var wheat0 := inv.count_of("wheat")
	qm._activate_ready()
	_check(qm.state_of("MQ17") == QuestManager.ACTIVE and inv.count_of("wheat") == wheat0 + 4 and qm.quests.MQ17.granted, "MQ17 을 받으면 밀 4개 (계절 상관없이)")
	qm._activate_ready()
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	_check(inv.count_of("wheat") == wheat0 + 4 and qm.quests.MQ17.granted, "다시 열거나 불러와도 밀은 한 번만")

	# 기존 저장 (버전 5): 돈·아이템·건물 그대로, 기술 제한 없음, 퀘스트는 MQ01 부터 (지난 기록으로 보상 안 함)
	var migrated: Dictionary = world.save_manager._migrate({"version": 5, "sections": {"game": {"money": 1234}}})
	_check(migrated.version == SaveManager.VERSION and migrated.sections.story == {"legacy": true} and migrated.sections.game.money == 1234, "버전 5 저장 → 6: story = legacy, 나머지 그대로")
	var m0 := GameState.money
	var inv0 := inv.to_data()
	qm.load_data(migrated.sections.story)
	_check(qm.legacy and qm.is_unlocked("conveyor") and qm.is_unlocked("sky_station") and qm.item_unlocked("harvester_3"), "기존 저장: 모든 기술 열림 (새 게임에만 제한)")
	_check(qm.state_of("MQ01") == QuestManager.ACTIVE and qm.state_of("MQ02") == QuestManager.LOCKED and GameState.money == m0 and inv.to_data() == inv0, "기존 저장: MQ01 부터 직접 진행, 지난 기록으로 보상하지 않음")

	# 정리
	qm.load_data(saved_story)
	inv.load_data(saved_inv)
	GameState.money = saved_money
	for c in plots:
		farm.tiles.erase(c)
	farm.queue_redraw()
	await get_tree().process_frame


## 스토리 2단계: 퀘스트 HUD · 퀘스트 목록 · 입력 충돌 · NPC 대화·납품 · 시대 표시
func _test_story_ui(world: FarmWorld, hud: HUD) -> void:
	var qm := world.quests
	var inv := GameState.inventory
	var player := world.player
	var saved_story := qm.to_data()
	var saved_inv := inv.to_data()
	var saved_money := GameState.money
	var saved_pos := player.global_position
	var q_key := InputEventAction.new()
	q_key.action = "quest_log"
	q_key.pressed = true
	player.global_position = world.home_position  # 광장 밖에서 (광장 방문이 저절로 세지지 않게)
	qm.new_game()
	await get_tree().process_frame

	# HUD 추적: 제목 + 목표 2개 (진행도/필요 수량)
	var tr := hud._quest_tracker
	var lines := tr._lines.map(func(l: Label) -> String: return l.text)
	_check(tr.visible and tr._title.text == "낯선 고향" and lines == ["· 농장 안내판 읽기 0/1", "· 광장에 가 보기 0/1"], "HUD: MQ01 제목 + 목표 2개 %s" % [lines])
	Events.sign_read.emit("farm_sign")
	_check(tr._lines[0].text == "· 농장 안내판 읽기 1/1" and tr._lines[0].get_theme_color("font_color") == QuestTracker.DONE, "HUD: 끝낸 목표는 1/1 초록")
	_check(tr.mouse_filter == Control.MOUSE_FILTER_IGNORE and tr.get_global_rect().position.x < 40 and tr.get_global_rect().position.y < 40 and tr.size.x < 420, "HUD: 왼쪽 위 작게, 클릭을 막지 않음 (%s)" % tr.size)

	# 퀘스트 목록 (Q): 진행 중 / 잠김, 시대
	hud._unhandled_input(q_key)
	var log := hud._quest_log
	_check(log.visible and get_tree().paused and GameState.is_time_paused(), "Q → 퀘스트 목록 (게임·시간 멈춤)")
	var rows := log._list.get_children().filter(func(n: Node) -> bool: return n is VBoxContainer)
	var head := func(id: String) -> String: return (log._list.get_node(id).get_child(0) as Label).text
	_check(rows.size() == 20 and head.call("MQ01").contains("진행 중") and head.call("MQ02").contains("잠김") and (log._list.get_node("MQ02").get_child(1) as Label).text.contains("앞 퀘스트"), "목록 20개: MQ01 진행 중, MQ02 잠김 (제목만)")
	_check(log._era.text == "시대: 개척시대" and log._techs.text.contains("기본 농사"), "새 저장: 시대 개척시대, 열린 기술 표시 (%s)" % log._era.text)
	hud._unhandled_input(q_key)
	_check(not log.visible and not get_tree().paused and not GameState.is_time_paused(), "Q 다시 → 닫힘, 게임 재개")
	# 완료 · 보상 받음
	player.global_position = world.cell_center(Vector2i(60, 20))
	qm._process(0.0)
	player.global_position = world.home_position
	hud.open_quest_log()
	_check(head.call("MQ01").contains("완료 · 보상 받음") and (log._list.get_node("MQ01").get_child(4) as Label).text.contains("(받음)") and head.call("MQ02").contains("진행 중"), "MQ01 완료 · 보상 받음 (받음 표시), MQ02 진행 중")
	hud._close_panels()

	# 입력 충돌: 가방·건설 창·건설 모드·대화·상점이 열려 있으면 Q 로 안 열림, 퀘스트 목록이 열려 있으면 I·B 로 안 열림
	hud.open_inventory()
	hud._unhandled_input(q_key)
	_check(hud._inventory.visible and not log.visible, "가방이 열려 있으면 Q 무시")
	hud._close_panels()
	hud.open_build_panel()
	hud._unhandled_input(q_key)
	_check(hud._build.visible and not log.visible, "건설 창이 열려 있으면 Q 무시")
	hud._close_panels()
	Events.shop_requested.emit("buy")
	hud._unhandled_input(q_key)
	_check(hud._shop.visible and not log.visible, "상점이 열려 있으면 Q 무시")
	hud._close_panels()
	hud.open_quest_log()
	var i_key := InputEventAction.new()
	i_key.action = "toggle_inventory"
	i_key.pressed = true
	var b_key := InputEventAction.new()
	b_key.action = "build_menu"
	b_key.pressed = true
	hud._unhandled_input(i_key)
	hud._unhandled_input(b_key)
	_check(log.visible and not hud._inventory.visible and not hud._build.visible, "퀘스트 목록이 열려 있으면 I·B 무시")
	hud._close_panels()

	# 기존 저장 표시
	qm.load_data({"legacy": true})
	hud.open_quest_log()
	_check(log._era.text == "시대: 기존 저장 · 모든 기술 해금", "기존 저장: '기존 저장 · 모든 기술 해금' (%s)" % log._era.text)
	hud._close_panels()

	# NPC 대화·납품 (MQ07: 잡화점에 작물 아무거나 3개)
	qm.new_game()
	for id: String in ["MQ01", "MQ02", "MQ03", "MQ04", "MQ05", "MQ06"]:
		qm.quests[id].state = QuestManager.REWARDED
	qm._activate_ready()
	var store: Npc = world.interiors["store"].npc
	inv.load_data([])
	inv.add("carrot", 2, "bronze")
	store.interact(player)
	var btn := hud._dialog._buttons.get_child(0) as Button
	_check(qm.state_of("MQ07") == QuestManager.ACTIVE and qm.progress_of("MQ07")[0] == 1, "잡화점 주인에게 말 걸기 → 대화 목표 1/1")
	_check(btn.text == "납품: 작물 아무거나 3개 납품 (2/3)" and btn.disabled and hud._dialog._line.text.contains("[퀘스트] 씨앗상점의 부탁"), "대화 창: 퀘스트 안내 + 납품 버튼 (2/3, 누를 수 없음)")
	var money0 := GameState.money
	hud._on_dialog_chosen("quest:MQ07:1")
	_check(inv.count_of("carrot") == 2 and qm.progress_of("MQ07")[1] == 0 and GameState.money == money0, "모자라면 납품 안 됨 (아무것도 안 빠짐)")
	inv.add("potato", 2, "silver")
	store.interact(player)
	btn = hud._dialog._buttons.get_child(0) as Button
	_check(btn.text == "납품: 작물 아무거나 3개 납품 (4/3)" and not btn.disabled, "재료가 모이면 납품 버튼 (4/3)")
	btn.pressed.emit()
	await get_tree().process_frame
	_check(inv.count_of("potato") == 0 and inv.count_of("carrot") == 1, "납품: 정확히 3개 차감 (싼 감자 2 → 당근 1)")
	_check(qm.state_of("MQ07") == QuestManager.REWARDED and GameState.money == money0 + 200 and qm.state_of("MQ08") == QuestManager.ACTIVE, "MQ07 완료, +200 G, MQ08 시작")
	hud._on_dialog_chosen("quest:MQ07:1")
	store.interact(player)
	var has_quest_btn := hud._dialog._buttons.get_children().any(func(b: Button) -> bool: return b.text.begins_with("납품:"))
	_check(GameState.money == money0 + 200 and inv.count_of("carrot") == 1 and not has_quest_btn, "끝난 납품은 다시 안 됨 (버튼도 없음, 보상 한 번)")
	hud._close_panels()
	# MQ09: 대장장이에게 석탄 3개
	qm.quests.MQ08.state = QuestManager.REWARDED
	qm._activate_ready()
	inv.add("coal", 3)
	var smith: Npc = world.interiors["smith"].npc
	smith.interact(player)
	btn = hud._dialog._buttons.get_child(0) as Button
	_check(btn.text == "납품: 석탄 3개 전달 (폐탄더미) (3/3)" and not btn.disabled and qm.progress_of("MQ09")[0] == 1, "대장장이: 대화 1/1, 석탄 납품 버튼 (3/3)")
	btn.pressed.emit()
	await get_tree().process_frame
	_check(inv.count_of("coal") == 0 and qm.state_of("MQ09") == QuestManager.REWARDED and qm.state_of("MQ10") == QuestManager.ACTIVE, "석탄 3개 납품 → MQ09 완료, MQ10 시작")
	# 저장 → 다시 불러오기: 진행도·보상 상태 그대로
	world.save_manager.save_game("manual")
	var money_saved := GameState.money
	qm.new_game()
	world.save_manager.load_game()
	_check(qm.state_of("MQ07") == QuestManager.REWARDED and qm.state_of("MQ09") == QuestManager.REWARDED and qm.state_of("MQ10") == QuestManager.ACTIVE and GameState.money == money_saved, "저장·불러오기 후 납품·보상 상태 그대로, 다시 보상 안 함")
	hud._close_panels()

	# 정리
	qm.load_data(saved_story)
	inv.load_data(saved_inv)
	GameState.money = saved_money
	player.global_position = saved_pos
	await get_tree().process_frame


## 5단계 후속 안정화 (퀘스트 상태 강제): MQ03 갈아 둔 칸 인정 · 가공 재료 보충 (MQ17 밀 손실, 가을·겨울 MQ18~20) · 토스트 위치
func _test_story_stabilize(world: FarmWorld, hud: HUD) -> void:
	var qm := world.quests
	var inv := GameState.inventory
	var farm := world.farm
	var saved_story := qm.to_data()
	var saved_inv := inv.to_data()
	var saved_farm := farm.to_data()
	var saved_day := GameState.day
	var saved_build := world.build.to_data()
	world.build.load_data([])  # 다른 점검이 남긴 벨트·가공기 물건이 '흐르는 중' 수에 섞이지 않게

	# MQ03: 받기 전에 간 칸도 인정, 같은 칸은 한 번
	farm.load_data({})
	qm.new_game()
	inv.load_data([])
	var cells: Array = farm.farmable_cells.keys().filter(func(c: Vector2i) -> bool: return world.obstacles.obstacle_at(c) == null and not world.build.is_occupied(c))
	cells.sort()
	for i in 3:
		farm.till(cells[i])
	qm.quests["MQ01"].state = QuestManager.REWARDED
	qm.quests["MQ02"].state = QuestManager.REWARDED
	qm._activate_ready()
	_check(qm.state_of("MQ03") == QuestManager.ACTIVE and qm.progress_of("MQ03")[0] == 3, "MQ03: 받기 전에 갈아 둔 3칸 인정 (%s)" % qm.objective_line(QuestManager.quest_def("MQ03"), 0))
	farm.till(cells[0])
	farm.untill(cells[1])
	farm.till(cells[1])
	_check(qm.progress_of("MQ03")[0] == 3, "같은 칸을 다시 갈아도 두 번 세지 않음 (3)")
	farm.till(cells[3])
	farm.till(cells[4])
	_check(qm.progress_of("MQ03")[0] == 5, "새 칸 2개 더 → 5/5")

	# 퀘스트 재료 (MQ17): 가방에 밀이 있으면 안 보이고, 다 팔면 보임
	farm.load_data(saved_farm)
	GameState.day = 10
	qm.new_game()
	inv.load_data([])
	_reach(qm, "MQ17")
	_check(inv.count_of("wheat") == 4 and not qm.quest_material_usable(), "MQ17: 받은 밀 4개가 있으면 퀘스트 재료 안 보임 (겹쳐 주지 않음)")
	inv.remove("wheat", 3)
	_check(qm.quest_material_usable(), "밀이 1개만 남으면 (밀가루 1회분 2개가 안 됨) 퀘스트 재료가 보임")
	inv.remove("wheat", 1)
	_check(qm.quest_material_usable() and qm.quest_material_left() == 1, "밀을 다 팔면 퀘스트 재료 1회")
	var o := _factory_line_spot(world)
	var proc := world.build.place(PlaceableDB.get_def("manual_processor"), o) as Processor
	hud.open_processor(proc)
	await get_tree().process_frame
	var pp := hud._processor
	pp._select("flour")
	pp.refresh()
	_check(pp._quest_btn.visible and pp._quest_btn.text == "퀘스트 재료 사용 · 밀가루 (MQ17 남은 1회)", "가공기 창 버튼: %s" % pp._quest_btn.text)
	pp._select("dough")
	pp.refresh()
	_check(not pp._quest_btn.visible, "다른 레시피를 고르면 안 보임")
	pp._select("flour")
	pp.refresh()
	hud._close_panels()
	hud.open_quest_log()
	hud._quest_log.show_tab("quests")
	var qline := hud._quest_log._list.get_node_or_null("Support/QuestMaterial") as Label
	_check(qline != null and qline.text.contains("MQ17 남은 1회") and qline.text.contains("[퀘스트 재료 사용]"), "퀘스트 창 안내: %s" % (qline.text if qline else "없음"))
	_check(hud._quest_tracker._hint.text.begins_with("가방에 밀이 없으면 수동 가공기에서 [퀘스트 재료 사용]"), "HUD 안내: %s" % hud._quest_tracker._hint.text)
	hud._close_panels()
	# 빠른 반복 클릭 · 취소 → 횟수만 돌려받음 (밀은 생기지 않음)
	for i in 5:
		qm.use_quest_material(proc, 3)
	_check(proc.queue.size() == 1 and qm.quest_material_left() == 0, "5번 눌러도 1회만")
	_check(proc.cancel(inv) and inv.count_of("wheat") == 0 and qm.quest_material_left() == 1, "취소 → 퀘스트 재료 1회 돌려받음, 밀은 안 생김")
	# 저장·불러오기: 진행 중인 퀘스트 재료 회차와 쓴 횟수 그대로
	qm.use_quest_material(proc, 1)
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	proc = world.build.object_at(o) as Processor
	_check(proc.queue.size() == 1 and str(proc.queue[0].get("quest", "")) == "MQ17" and qm.quest_material_used == {"MQ17": 1}, "저장·불러오기 뒤에도 퀘스트 재료 회차·쓴 횟수 그대로")
	# 철거: 가공기를 치우면 회차 대신 횟수를 돌려받음 (밀 복제 없음)
	world.build_mode.start(BuildMode.Mode.REMOVE)
	_check(world.build_mode.try_remove(o) and inv.count_of("wheat") == 0 and qm.quest_material_left() == 1, "철거 → 횟수 돌려받음, 밀은 안 생김")
	world.build_mode.stop()
	# 끝나면 비활성
	proc = world.build.place(PlaceableDB.get_def("manual_processor"), o) as Processor
	qm.use_quest_material(proc, 1)
	Events.time_advanced.emit(61.0)
	_check(qm.state_of("MQ17") == QuestManager.REWARDED and qm.quest_material_left("MQ17") == 0, "MQ17 완료 → MQ17 퀘스트 재료 비활성")
	_check(inv.count_of("flour") == 0 and proc.take_output(inv) == 1 and inv.count_of("flour") == 1, "퀘스트 재료로 만든 밀가루는 보통 아이템 (꺼내기)")
	# 예전 저장 (쓴 기록 없음): MQ17 진행 중 · 밀 없음 → 바로 쓸 수 있음
	inv.load_data([])
	qm.load_data(_old_story(qm, "MQ17", QuestManager.ACTIVE, true))
	_check(qm.quest_material_used.is_empty() and qm.quest_material_usable() and qm.quest_material_left() == 1, "예전 저장 · MQ17 진행 중 · 밀 없음 → 퀘스트 재료 1회")
	# 저장 값이 상한보다 크면 잘라 냄
	var dd := qm.to_data()
	dd.quest_material_used = {"MQ17": 99, "MQ99": 3}
	qm.load_data(dd)
	_check(qm.quest_material_used == {"MQ17": 1}, "틀린 저장 값은 상한·없는 퀘스트 정리 %s" % [qm.quest_material_used])
	world.build.load_data([])

	# 토스트는 위쪽 HUD 칸 아래에 (1280x720 에서 퀘스트 추적·시계 칸과 안 겹침)
	qm.load_data(saved_story)
	await get_tree().process_frame
	hud.show_toast("하루가 끝나 집으로 돌아왔어요. 봄 2일 (화) 아침, 맑음 · 아주 긴 알림 글로 겹침을 확인해요")
	await get_tree().process_frame
	var t := hud._toast.get_global_rect()
	_check(not t.intersects(hud._quest_tracker.get_global_rect()) and not t.intersects(hud._info_box.get_global_rect()), "긴 알림도 퀘스트 추적·시계 칸과 겹치지 않음 (알림 %s)" % t)
	_check(hud.get_viewport().get_visible_rect().encloses(t), "긴 알림은 줄을 바꿔 화면 안에 (%s)" % t)
	hud.show_toast("나무 +1")
	await get_tree().process_frame
	_check(hud._toast.get_global_rect().size.x < 400, "짧은 알림은 글 길이만큼 (%s)" % hud._toast.get_global_rect().size)

	world.build.load_data(saved_build)
	farm.load_data(saved_farm)
	GameState.day = saved_day
	qm.load_data(saved_story)
	inv.load_data(saved_inv)
	await get_tree().process_frame


## 5단계 계절 검증 (퀘스트 상태 강제): 겨울(바깥에 못 심음)에 MQ17~MQ20 을 작물 없이 — 수동 가공기 [퀘스트 재료 사용]
## → 실제 가공 시간 → 벨트 → 창고 (MQ17 가공 1 · MQ18 운송 5 · MQ19 분배 2 · MQ20 입고 5 를 각각 확인)
func _test_story_winter_mq20(world: FarmWorld) -> void:
	var qm := world.quests
	var inv := GameState.inventory
	var saved_story := qm.to_data()
	var saved_inv := inv.to_data()
	var saved_day := GameState.day
	var saved_build := world.build.to_data()
	world.build.load_data([])
	GameState.day = 3 * 28 + 5  # 겨울 5일
	qm.new_game()
	inv.load_data([])
	_reach(qm, "MQ17")
	inv.remove("wheat", inv.count_of("wheat"))  # 받은 밀을 다 팔아 버림
	var o := _factory_line_spot(world)
	var proc := world.build.place(PlaceableDB.get_def("manual_processor"), o) as Processor
	_check(Calendar.season_of(GameState.day) == "winter" and qm.quest_material_usable() and qm.quest_material_left() == 1, "겨울 MQ17 · 밀 0 → 퀘스트 재료 1회")
	_check(qm.use_quest_material(proc, 9) == 1 and proc.queue.size() == 1 and qm.quest_material_left() == 0 and qm.use_quest_material(proc, 1) == 0, "MQ17: 1회만 시작 (더 못 씀)")
	_check(qm.state_of("MQ17") == QuestManager.ACTIVE, "시작만으로는 완료 아님 (가공 시간 필요)")
	Events.time_advanced.emit(30.0)
	_check(qm.state_of("MQ17") == QuestManager.ACTIVE, "30분: 아직")
	Events.time_advanced.emit(31.0)
	_check(qm.state_of("MQ17") == QuestManager.REWARDED and proc.output_count() == 1, "60분 → 밀가루 완성 → MQ17 완료 (결과물 1개 가공기 안)")
	# MQ18: 벨트 5칸 + 운송 5 (가공기 → 벨트 → 창고)
	var wh := world.build.place(PlaceableDB.get_def("warehouse"), o + Vector2i(7, 0)) as Warehouse
	for x in range(2, 7):
		world.build.place(PlaceableDB.get_def("conveyor"), o + Vector2i(x, 1), 3)
		Events.facility_placed.emit("conveyor")  # 건설 모드로 놓은 것과 같게 (이 강제 상태에선 컨베이어 기술이 잠겨 있어 직접 놓음)
	_check(qm.quest_material_left("MQ18") == 5, "MQ18 퀘스트 재료 5회")
	qm.use_quest_material(proc, 5)
	for i in 14:
		Events.time_advanced.emit(30.0)
	_check(qm.state_of("MQ18") == QuestManager.REWARDED and wh.storage.count_of("flour") >= 5, "MQ18: 퀘스트 재료 밀가루가 벨트로 창고에 (창고 %d)" % wh.storage.count_of("flour"))
	# MQ19: 분배기 + 옆 벨트, 2회
	world.build.remove(world.build.object_at(o + Vector2i(4, 1)))
	world.build.place(PlaceableDB.get_def("splitter"), o + Vector2i(4, 1), 3)
	world.build.place(PlaceableDB.get_def("conveyor"), o + Vector2i(4, 0), 2)
	qm.use_quest_material(proc, 2)
	for i in 8:
		Events.time_advanced.emit(30.0)
	_check(qm.state_of("MQ19") == QuestManager.REWARDED, "MQ19: 퀘스트 재료 2회로 분배기 두 출구 (%s)" % qm.objective_line(QuestManager.quest_def("MQ19"), 0))
	# MQ20: 입고 5 (분배기 옆 막다른 벨트로 빠지는 것이 있어도)
	var before := wh.storage.count_of("flour")
	qm.use_quest_material(proc, 5)
	for i in 16:
		Events.time_advanced.emit(30.0)
	_check(qm.state_of("MQ20") == QuestManager.REWARDED and qm.quest_material_left("MQ20") == 0, "MQ20: 퀘스트 재료 5회 → 창고 입고 5 → 완료 (창고 %d → %d)" % [before, wh.storage.count_of("flour")])
	_check(qm.quest_material_used == {"MQ17": 1, "MQ18": 5, "MQ19": 2, "MQ20": 5}, "쓴 횟수 기록 %s (한 저장 최대 13)" % [qm.quest_material_used])
	world.build.load_data(saved_build)
	GameState.day = saved_day
	qm.load_data(saved_story)
	inv.load_data(saved_inv)
	await get_tree().process_frame


## 퀘스트 지원 물건 (MQ17 밀 4 · MQ20 밀가루 3): 받는 순간만 바로 지급 시도, 못 넣은 것은 대기 → 퀘스트 창 [받기]로 직접 (저절로 주지 않음)
func _test_story_support(world: FarmWorld, hud: HUD) -> void:
	var qm := world.quests
	var inv := GameState.inventory
	var saved_story := qm.to_data()
	var saved_inv := inv.to_data()
	var wheat_max := ItemDB.get_item("wheat").max_stack

	# 가방에 자리가 있으면 받는 순간 바로 (지금까지와 같음)
	qm.new_game()
	inv.load_data([])
	_reach(qm, "MQ17")
	_check(inv.count_of("wheat") == 4 and qm.support_waiting().is_empty() and qm.quests["MQ17"].granted, "자리가 있으면 MQ17 을 받는 순간 밀 4")
	hud.open_quest_log()
	hud._quest_log.show_tab("quests")
	_check(hud._quest_log._list.has_node("MQ17") and not hud._quest_log._list.has_node("Support"), "대기 물건이 없으면 퀘스트 창에 지원 영역 없음")
	hud._close_panels()

	# 가방이 가득한 채 MQ17 을 받음 → 대기
	qm.new_game()
	inv.load_data([])
	_fill_bag(inv)
	_reach(qm, "MQ17")
	_check(qm.state_of("MQ17") == QuestManager.ACTIVE and inv.count_of("wheat") == 0 and not qm.quests["MQ17"].granted and qm._support_left("MQ17") == {"wheat": 4}, "가방이 가득: MQ17 은 받지만 밀 4 는 대기")
	hud.open_quest_log()
	hud._quest_log.show_tab("quests")
	var sup := hud._quest_log._list.get_node_or_null("Support")
	var line: Node = sup.get_node_or_null("MQ17_wheat") if sup else null
	_check(line != null and (line.get_child(0) as Label).text.begins_with("· 밀 4개") and (line.get_child(1) as Button).disabled and (line.get_child(2) as Label).text == "가방 공간 부족", "퀘스트 창: 받을 지원 물건 '밀 4개' · [받기] 꺼짐 · 가방 공간 부족")
	_check(sup != null and sup.get_combined_minimum_size().x <= 960, "지원 영역이 퀘스트 창 폭 안에 (%s)" % [sup.get_combined_minimum_size() if sup else Vector2.ZERO])
	await get_tree().process_frame
	var gap := (line.get_child(1) as Control).position.x - ((line.get_child(0) as Control).position.x + (line.get_child(0) as Control).size.x) if line else 999.0
	_check(gap >= 0.0 and gap <= 16.0 and (line.get_child(1) as Control).get_global_rect().end.x <= hud._quest_log.get_global_rect().end.x, "[받기]가 글 바로 옆 (간격 %d), 창 안" % gap)
	# 자리를 비워도 저절로 주지 않음
	inv.remove_at(0, inv.get_slot(0).count)
	_check(inv.count_of("wheat") == 0 and qm._support_left("MQ17") == {"wheat": 4}, "가방 자리가 생겨도 저절로 주지 않음")
	line = hud._quest_log._list.get_node("Support/MQ17_wheat")
	_check(not (line.get_child(1) as Button).disabled and line.get_child_count() == 2, "자리가 생기면 [받기] 켜짐")
	# 대기 중 저장·불러오기
	world.save_manager.save_game("manual")
	qm.new_game()
	world.save_manager.load_game()
	_check(qm._support_left("MQ17") == {"wheat": 4} and inv.count_of("wheat") == 0, "대기 중 저장·불러오기: 밀 4 대기 그대로 (불러올 때도 저절로 안 줌)")
	_check(qm.to_data().support.has("MQ17") and qm.to_data().quests["MQ17"].state == QuestManager.ACTIVE, "지원 물건 기록은 퀘스트 상태와 따로 저장 (story.support)")
	# 빠른 반복 클릭: 같은 버튼을 여러 번 (불러오면 창이 닫히므로 다시 연다)
	hud.open_quest_log()
	hud._quest_log.show_tab("quests")
	var btn := hud._quest_log._list.get_node("Support/MQ17_wheat").get_child(1) as Button
	for i in 5:
		btn.pressed.emit()
	_check(inv.count_of("wheat") == 4 and qm._support_left("MQ17").is_empty() and qm.quests["MQ17"].granted, "[받기] 5번 눌러도 밀 정확히 4")
	await get_tree().process_frame
	_check(not hud._quest_log._list.has_node("Support"), "다 받으면 지원 영역이 사라짐")
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	qm._activate_ready()
	_check(inv.count_of("wheat") == 4 and qm.claim_support("MQ17", "wheat") == 0, "다 받은 뒤 저장·불러오기·다시 받기에도 더 안 줌")
	hud._close_panels()

	# 일부만 들어감: 받는 순간 2, 받기로도 자리가 없으면 아무것도 안 바뀜, 퀘스트를 끝내도 남은 2 유지
	qm.new_game()
	inv.load_data([])
	inv.add("wheat", wheat_max - 2)
	_fill_bag(inv)
	_reach(qm, "MQ17")
	_check(inv.count_of("wheat") == wheat_max and qm._support_left("MQ17") == {"wheat": 2}, "일부만 들어감: 받는 순간 2 지급, 2 대기")
	var before: Dictionary = qm.to_data().support.duplicate(true)
	_check(qm.claim_support("MQ17", "wheat") == 0 and inv.count_of("wheat") == wheat_max and qm.to_data().support == before, "자리가 없으면 [받기]는 아무것도 바꾸지 않음")
	qm.quests["MQ17"].state = QuestManager.REWARDED
	qm._activate_ready()
	_check(qm._support_left("MQ17") == {"wheat": 2}, "퀘스트를 끝내도 받지 못한 2 는 대기로 남음")
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	_check(qm._support_left("MQ17") == {"wheat": 2} and qm.state_of("MQ17") == QuestManager.REWARDED, "저장·불러오기 뒤에도 남은 2 그대로")
	for i in inv.size():
		if inv.item_at(i) and inv.item_at(i).id == "stone":
			inv.remove_at(i, inv.get_slot(i).count)
			break
	_check(inv.count_of("wheat") == wheat_max, "자리가 나도 저절로 안 줌")
	_check(qm.claim_support("MQ17", "wheat") == 2 and inv.count_of("wheat") == wheat_max + 2 and qm._support_left("MQ17").is_empty(), "[받기] → 나머지 2, 모두 4 (중복·유실 없음)")

	# 받기 때 일부만: 밀 칸에 1 자리 → 1 받고 3 남음
	qm.new_game()
	inv.load_data([])
	_fill_bag(inv)
	_reach(qm, "MQ17")
	inv.remove_at(0, inv.get_slot(0).count)
	inv.add("wheat", wheat_max - 1)
	var w0 := inv.count_of("wheat")
	_check(qm.claim_support("MQ17", "wheat") == 1 and inv.count_of("wheat") == w0 + 1 and qm._support_left("MQ17") == {"wheat": 3}, "[받기] 때 1 자리 → 1 받고 3 대기")
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	_check(qm._support_left("MQ17") == {"wheat": 3} and inv.count_of("wheat") == w0 + 1, "재접속해도 준 1 · 남은 3 그대로")
	# MQ20 은 가방 지원 없음 (퀘스트 재료로 바뀜)
	qm.new_game()
	inv.load_data([])
	_reach(qm, "MQ20")
	_check(inv.count_of("flour") == 0 and qm.support_waiting().is_empty() and qm.quest_material_left("MQ20") == 5, "MQ20: 가방 밀가루 지원 없이 퀘스트 재료 5회")

	# 예전 저장 이전 (story.support 없음): granted 로 판단, 못 받은 것은 대기 → 받기
	inv.load_data([])
	qm.load_data(_old_story(qm, "MQ20", QuestManager.ACTIVE, false))
	_check(inv.count_of("flour") == 0 and qm.support_waiting().is_empty() and qm.quest_material_left("MQ20") == 5, "예전 저장: MQ20 진행 중 · 밀가루 3 미지급 → 가방 대기 대신 퀘스트 재료 5회 (겹쳐 주지 않음)")
	inv.load_data([])
	qm.load_data(_old_story(qm, "MQ20", QuestManager.ACTIVE, true))
	_check(qm.support_waiting().is_empty(), "예전 저장: MQ20 이미 받음 (granted) → 대기 없음")
	qm.load_data(_old_story(qm, "MQ20", QuestManager.REWARDED, false))
	_check(qm.support_waiting().is_empty(), "예전 저장: 끝난 MQ20 → 대기 없음")
	var unknown := _old_story(qm, "MQ20", QuestManager.ACTIVE, false)
	unknown.quests["MQ20"].erase("granted")
	qm.load_data(unknown)
	_check(qm.support_waiting().is_empty(), "예전 저장: 지급 기록이 아예 없음 → 주지 않음")
	qm.load_data(_old_story(qm, "MQ17", QuestManager.ACTIVE, false))
	_check(qm._support_left("MQ17") == {"wheat": 4} and inv.count_of("wheat") == 0, "예전 저장: MQ17 진행 중 · 미지급 → 밀 4 대기")
	qm.load_data(qm.to_data())
	_check(qm._support_left("MQ17") == {"wheat": 4}, "이전 뒤 새 형식으로 다시 불러도 대기 그대로")

	qm.load_data(saved_story)
	inv.load_data(saved_inv)
	await get_tree().process_frame


## 가방을 돌로 가득 채운다
func _fill_bag(inv: Inventory) -> void:
	while inv.add("stone", 999) == 0:
		pass


## target 앞의 퀘스트를 모두 끝내 target 을 받게 한다
func _reach(qm: QuestManager, target: String) -> void:
	for q: Dictionary in QuestManager.quest_defs():
		if q.id == target:
			break
		qm.quests[q.id].state = QuestManager.REWARDED
	qm._activate_ready()


## 4단계 후속 이전 형식의 story (support 없음): target 앞은 끝남 (MQ17 은 받은 걸로), target 은 state · granted
func _old_story(qm: QuestManager, target: String, state: String, granted: bool) -> Dictionary:
	var qs := {}
	var before := true
	for q: Dictionary in QuestManager.quest_defs():
		if q.id == target:
			qs[q.id] = {"state": state, "progress": [], "granted": granted}
			before = false
		elif before:
			qs[q.id] = {"state": QuestManager.REWARDED, "progress": [], "granted": true}
		else:
			qs[q.id] = {"state": QuestManager.LOCKED, "progress": [], "granted": false}
	return {"era": "mechanical", "techs": {}, "flags": {}, "legacy": false, "quests": qs}


## 스토리 4단계: 새 게임으로 MQ06 → MQ20 을 실제 기능으로 끝까지 (출하·납품·프로젝트·폐탄더미·잔해·광산·용광로·강화·설계도·가공·컨베이어·분배기·창고)
func _test_story_play(world: FarmWorld, hud: HUD) -> void:
	var qm := world.quests
	var inv := GameState.inventory
	var player := world.player
	var saved_story := qm.to_data()
	var saved_inv := inv.to_data()
	var saved_money := GameState.money
	var saved_pos := player.global_position
	var saved_unlocks := GameState.unlocks.duplicate(true)
	var saved_obstacles := world.obstacles.to_data()
	var saved_build := world.build.to_data()
	player.global_position = world.home_position
	qm.new_game()
	inv.load_data([])
	inv.add("hoe")
	inv.add("pickaxe")
	GameState.money = 0
	for id: String in ["MQ01", "MQ02", "MQ03", "MQ04", "MQ05"]:
		qm.quests[id].state = QuestManager.REWARDED
	qm._activate_ready()
	await get_tree().process_frame
	_check(qm.state_of("MQ06") == QuestManager.ACTIVE, "MQ06 시작 (MQ01~05 끝낸 뒤)")
	_check(qm.lock_short("conveyor") == "잠김 · MQ16 · 기계 기술 복구" and qm.lock_short("splitter") == "잠김 · MQ18 보상", "짧은 잠김 글 (%s / %s)" % [qm.lock_short("conveyor"), qm.lock_short("splitter")])

	# MQ06 출하함 정산: 작물 3개
	inv.add("carrot", 3)
	var cq := str(inv.stacks().filter(func(st: Dictionary) -> bool: return st.id == "carrot")[0].get("quality", ""))
	world.shipping_bin.deposit(inv, "carrot", cq, 3)
	_check(qm.state_of("MQ06") == QuestManager.ACTIVE, "출하함에 넣기만 하면 아직 (정산 때)")
	world.shipping_bin.settle()
	_check(qm.state_of("MQ06") == QuestManager.REWARDED and qm.state_of("MQ07") == QuestManager.ACTIVE, "MQ06: 출하함 정산 → 완료")

	# MQ07 잡화점 주인과 대화 + 작물 3개 납품 (계절 상관없이: 겨울 작물로)
	var store_npc: Node = world.interiors["store"].npc
	store_npc.interact(player)
	hud._close_panels()
	inv.add("spinach", 3)
	store_npc.interact(player)
	var opts := _dialog_options(hud)
	_check(opts.any(func(t: String) -> bool: return t.begins_with("납품: ")), "잡화점 대화에 작물 납품 선택지 %s" % [opts])
	hud._dialog.choose("quest:MQ07:1")
	_check(qm.state_of("MQ07") == QuestManager.REWARDED and inv.count_of("spinach") == 0, "MQ07: 아무 작물 3개 납품 (시금치, 겨울 작물)")

	# MQ08 낡은 제작대: NPC 납품과 기술 탭 납품이 같은 데이터
	_check(qm.project_hint() == "Q → 기술·복구 탭에서 납품 (또는 씨앗상점 하나)", "HUD 안내: %s" % qm.project_hint())
	await get_tree().process_frame
	_check(hud._quest_tracker._hint.visible and hud._quest_tracker._hint.text.begins_with("Q → 기술·복구 탭"), "HUD 추적 칸에 납품 안내 줄")
	inv.add("wood", 9)
	inv.add("stone", 10)
	store_npc.interact(player)
	opts = _dialog_options(hud)
	_check(opts.has("납품 나무 0/15 (가진 9)") and opts.has("납품 돌 0/10 (가진 10)"), "잡화점 대화: 복구 납품 선택지 %s" % [opts])
	hud._dialog.choose("project:workbench_repair:wood")
	_check(qm.project_rows("workbench_repair")[0].given == 9 and inv.count_of("wood") == 0, "NPC 로 목재 9 넣음")
	inv.add("wood", 10)
	hud.open_quest_log()
	hud._quest_log.show_tab("tech")
	var wb_box := hud._quest_log._list.get_node("workbench_repair")
	var wood_btn := (wb_box.get_child(1) as HBoxContainer).get_child(1) as Button
	wood_btn.pressed.emit()
	_check(qm.project_rows("workbench_repair")[0].given == 15 and inv.count_of("wood") == 4, "기술 탭으로 남은 6 만 넣음 (같은 프로젝트, 4개는 가방에)")
	hud._close_panels()
	store_npc.interact(player)
	opts = _dialog_options(hud)
	_check(not opts.any(func(t: String) -> bool: return t.begins_with("납품 나무")) and opts.any(func(t: String) -> bool: return t.begins_with("납품 돌")), "다 넣은 목재는 대화에서 사라짐 %s" % [opts])
	_check(qm.donate("workbench_repair", "wood") == 0 and inv.count_of("wood") == 4, "다 찬 목재는 더 안 빠짐")
	hud._dialog.choose("project:workbench_repair:stone")
	_check(qm.project_done("workbench_repair") and qm.state_of("MQ08") == QuestManager.REWARDED and inv.count_of("stone") == 0, "MQ08: 제작대 복구 완료 (돌 정확히 10)")
	store_npc.interact(player)
	opts = _dialog_options(hud)
	_check(not opts.any(func(t: String) -> bool: return t.begins_with("납품 ")), "끝난 프로젝트는 대화에 안 나옴 %s" % [opts])
	hud._close_panels()

	# MQ09 대장장이 + 폐탄더미에서 석탄 3
	await get_tree().process_frame
	var piles := world.obstacles.all().filter(func(o: Obstacle) -> bool: return o.def.id == "coal_pile")
	_check(piles.size() == 3, "MQ09 진행 중: 숲길 옆 폐탄더미 3개 (%d)" % piles.size())
	var smith_npc: Node = world.interiors["smith"].npc
	smith_npc.interact(player)
	hud._close_panels()
	for ob: Obstacle in piles:
		await _break(world.obstacles, ob.cell, "pickaxe")
	_check(inv.count_of("coal") >= 3 and world.obstacles.all().filter(func(o: Obstacle) -> bool: return o.def.id == "coal_pile").is_empty(), "곡괭이로 폐탄더미 → 석탄 %d" % inv.count_of("coal"))
	smith_npc.interact(player)
	hud._dialog.choose("quest:MQ09:1")
	_check(qm.state_of("MQ09") == QuestManager.REWARDED and qm.flags.has("mine_hint"), "MQ09: 대장장이에게 석탄 3 전달")
	qm.ensure_quest_objects()
	_check(world.obstacles.all().filter(func(o: Obstacle) -> bool: return o.def.id == "coal_pile").is_empty(), "MQ09 뒤에는 폐탄더미를 더 깔지 않음")

	# MQ10 광산 입구 도착 + 잔해 5
	await get_tree().process_frame
	var debris := world.obstacles.all().filter(func(o: Obstacle) -> bool: return o.def.id == "mine_debris")
	_check(debris.size() == 5, "MQ10 진행 중: 입구 앞 잔해 5개 (%d)" % debris.size())
	player.global_position = world.cell_center(Vector2i(85, 6))
	await get_tree().process_frame
	_check(qm.progress_of("MQ10")[0] == 1, "광산 입구 앞 도착")
	for ob: Obstacle in debris:
		await _break(world.obstacles, ob.cell, "pickaxe")
	_check(qm.state_of("MQ10") == QuestManager.REWARDED, "MQ10: 잔해 5개 치움")
	world.mine_entrance.interact(player)
	_check(world.area == "farm", "MQ11 전에는 아직 광산이 막혀 있음")

	# MQ11 광산 입구 수리 (대장장이에게 납품)
	inv.add("wood", 10)
	inv.add("stone", 10)
	smith_npc.interact(player)
	hud._dialog.choose("project:mine_repair:wood")
	smith_npc.interact(player)
	hud._dialog.choose("project:mine_repair:stone")
	_check(qm.state_of("MQ11") == QuestManager.REWARDED and qm.era == "metal", "MQ11: 대장장이 납품으로 광산 입구 수리 → 금속시대")

	# MQ12 광산에서 구리 광석 6 (곡괭이로 구리 바위)
	world.mine_entrance.interact(player)
	_check(world.area == "mine", "광산 입구 열림")
	Events.mine_requested.emit(1)
	await get_tree().process_frame
	world.mine.rocks.clear()
	for x in 6:
		world.mine.rocks.spawn(Mine.ORIGIN + Vector2i(5 + x * 2, 9), "mine_copper", x)
	for ob: Obstacle in world.mine.rocks.all():
		await _break(world.mine.rocks, ob.cell, "pickaxe")
	_check(qm.state_of("MQ12") == QuestManager.REWARDED and inv.count_of("copper_ore") >= 6, "MQ12: 구리 광석 %d 캠" % inv.count_of("copper_ore"))

	# MQ13 대장간에서 용광로 사서 구리 주괴
	world.exit_mine()
	GameState.money += 1000
	inv.add("stone", 30)
	smith_npc.interact(player)
	hud._dialog.choose("smith_shop")
	hud._shop._buy("furnace", 1)
	hud._close_panels()
	_check(inv.count_of("furnace") == 1, "금속시대: 대장간에서 용광로 구매")
	var fspot := _free_origin(world, PlaceableDB.get_def("furnace"), Vector2i(-1, -1))
	world.build_mode.start_place("furnace")
	_check(world.build_mode.try_place(fspot), "용광로 설치")
	world.build_mode.stop()
	var furnace := world.build.object_at(fspot) as Furnace
	inv.add("coal", 1)
	_check(furnace.start(inv, "copper_ore") == "", "용광로에 구리 광석 3 + 석탄 1")
	Events.time_advanced.emit(61.0)
	_check(qm.state_of("MQ13") == QuestManager.REWARDED, "MQ13: 구리 주괴 제련")
	furnace.take_output(inv)

	# MQ14 구리 도구 강화
	inv.add("copper_bar", 3)
	GameState.money += 500
	var hoe_i := -1
	for i in inv.size():
		if inv.item_at(i) and inv.item_at(i).id == "hoe":
			hoe_i = i
	_check(ToolUpgrade.apply(inv, hoe_i) and inv.item_at(hoe_i).id == "hoe_2", "괭이 → 구리 괭이")
	_check(qm.state_of("MQ14") == QuestManager.REWARDED, "MQ14: 구리 도구 강화")

	# MQ15 광산 5층 + 오래된 설계도
	Events.mine_requested.emit(5)
	await get_tree().process_frame
	var bps := world.objects.get_children().filter(func(n: Node) -> bool: return n is MineFeature and n.kind == MineFeature.Kind.BLUEPRINT)
	_check(bps.size() == 1 and qm.progress_of("MQ15")[0] == 5, "광산 5층 도달, 오래된 설계도가 있음")
	if not bps.is_empty():
		bps[0].interact(player)
	await get_tree().process_frame
	_check(qm.state_of("MQ15") == QuestManager.REWARDED and not is_instance_valid(bps[0]) or bps[0].is_queued_for_deletion(), "MQ15: 설계도 조사 → 완료, 설계도 사라짐")
	Events.mine_requested.emit(5)
	await get_tree().process_frame
	_check(world.objects.get_children().filter(func(n: Node) -> bool: return n is MineFeature and n.kind == MineFeature.Kind.BLUEPRINT and not n.is_queued_for_deletion()).is_empty(), "찾은 설계도는 다시 안 나옴")
	world.exit_mine()

	# MQ16 기계 기술 복구 (기계상점 미나에게 구리 주괴 8 + 500 G) + 설계도 전달(대화)
	var machine_npc: Node = world.interiors["machine"].npc
	inv.add("copper_bar", 8)
	GameState.money += 500
	machine_npc.interact(player)
	hud._dialog.choose("project:mechanical_research:copper_bar")
	machine_npc.interact(player)
	var m0 := GameState.money
	hud._dialog.choose("project:mechanical_research:money")
	_check(GameState.money == m0 - 500 and qm.project_done("mechanical_research"), "기계 기술 복구: 주괴 8 + 정확히 500 G")
	machine_npc.interact(player)
	hud._close_panels()
	_check(qm.state_of("MQ16") == QuestManager.REWARDED and qm.era == "mechanical", "MQ16: 기계시대")

	# MQ17 밀 4 (한 번만) → 수동 가공기로 밀가루
	_check(inv.count_of("wheat") == 4 and qm.quests["MQ17"].granted, "MQ17 시작: 밀 4개 받음")
	qm._activate_ready()
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	_check(inv.count_of("wheat") == 4, "저장·불러오기·다시 확인해도 밀은 4개 그대로 (중복 지급 없음)")
	GameState.money += 5000
	inv.add("wood", 130)
	inv.add("stone", 70)
	Events.shop_requested.emit("machine")
	hud._shop._buy("manual_processor", 1)
	hud._shop._buy("conveyor", 5)
	hud._shop._buy("warehouse", 1)
	hud._close_panels()
	_check(inv.count_of("manual_processor") == 1 and inv.count_of("conveyor") == 5 and inv.count_of("warehouse") == 1, "기계시대: 수동 가공기·컨베이어·창고 구매")
	# 가공기 → 벨트 5칸 → 창고 가 들어갈 자리
	var line := _factory_line_spot(world)
	_check(line != Vector2i(-1, -1), "가공 라인 자리 찾음 %s" % line)
	world.build_mode.start_place("manual_processor")
	world.build_mode.try_place(line)
	world.build_mode.stop()
	var proc := world.build.object_at(line) as Processor
	_check(proc != null and proc.belt_out, "새로 놓은 수동 가공기: 컨베이어로 내보내기 켜짐")
	_check(proc.start(inv, "flour", 2) == 2, "밀가루 2회 시작 (밀 4)")
	Events.time_advanced.emit(121.0)
	_check(qm.state_of("MQ17") == QuestManager.REWARDED and proc.output_count() == 2, "MQ17: 수동 가공기 밀가루 → 완료 (결과물 2개는 가공기 안)")

	# MQ18 컨베이어 5칸 설치 + 실제 운송 (가공기 → 벨트 → 창고)
	world.build_mode.start_place("warehouse")
	world.build_mode.try_place(line + Vector2i(7, 0))
	world.build_mode.stop()
	var wh := world.build.object_at(line + Vector2i(7, 0)) as Warehouse
	world.build_mode.start_place("conveyor")
	var belts := world.build_mode.place_belts(line + Vector2i(2, 1), line + Vector2i(6, 1))
	world.build_mode.stop()
	_check(belts == 5 and qm.progress_of("MQ18")[0] == 5, "컨베이어 5칸 설치 (%d)" % belts)
	inv.add("wheat", 6)
	proc.start(inv, "flour", 3)
	for i in 12:
		Events.time_advanced.emit(30.0)
	_check(qm.state_of("MQ18") == QuestManager.REWARDED and wh.storage.count_of("flour") == 5, "MQ18: 밀가루 5개가 벨트로 창고까지 (창고 %d)" % wh.storage.count_of("flour"))
	_check(qm.is_unlocked("splitter"), "MQ18 보상: 분배기 해금")

	# MQ19 분배기의 서로 다른 두 출구
	inv.add("wood", 10)
	inv.add("stone", 5)
	Events.shop_requested.emit("machine")
	hud._shop._buy("splitter", 1)
	hud._shop._buy("conveyor", 1)
	hud._close_panels()
	var mid := line + Vector2i(4, 1)
	world.build.remove(world.build.object_at(mid))
	inv.add("conveyor", 1)
	world.build_mode.start_place("splitter")
	world.build_mode.turns = 3  # 오른쪽 (벨트와 같은 방향)
	_check(world.build_mode.try_place(mid), "벨트 한 칸을 분배기로 바꿈")
	world.build_mode.stop()
	world.build_mode.start_place("conveyor")
	world.build_mode.turns = 2  # 위로 (분배기 왼쪽 출구)
	world.build_mode.try_place(mid + Vector2i.UP)
	world.build_mode.stop()
	inv.add("wheat", 4)
	proc.start(inv, "flour", 2)
	for i in 10:
		Events.time_advanced.emit(30.0)
	_check(qm.state_of("MQ19") == QuestManager.REWARDED and qm.is_unlocked("merger"), "MQ19: 분배기 두 출구 → 합류기 해금 (출구 %s)" % [qm.quests["MQ19"].get("seen", {})])

	# MQ20 가공품 5개를 컨베이어로 창고에 (진행 중일 때만 셈)
	var before := wh.storage.count_of("flour")
	_check(qm.state_of("MQ20") == QuestManager.ACTIVE, "MQ20 시작")
	_check(qm.support_waiting().is_empty() and qm.quest_material_left("MQ20") == 5, "MQ20 시작: 가방 지원 없이 퀘스트 재료 5회 (%d)" % qm.quest_material_left("MQ20"))
	_check(qm.objective_line(QuestManager.quest_def("MQ20"), 0).begins_with("가공품 5개를 컨베이어로 운반해 창고에 저장"), "MQ20 목표 글: %s" % qm.objective_line(QuestManager.quest_def("MQ20"), 0))
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	qm._activate_ready()
	_check(qm.quest_material_left("MQ20") == 5, "저장·불러오기 뒤에도 퀘스트 재료 5회 그대로")
	wh = world.build.object_at(line + Vector2i(7, 0)) as Warehouse
	proc = world.build.object_at(line) as Processor
	var m20: int = qm.progress_of("MQ20")[0]
	wh.insert("flour", 3, Quality.NONE)
	_check(qm.progress_of("MQ20")[0] == m20, "손으로/직접 창고에 넣은 건 안 셈")
	Events.belt_delivered.emit(wh, "carrot")
	Events.belt_delivered.emit(wh, "copper_ore")
	Events.belt_delivered.emit(wh, "copper_bar")
	_check(qm.progress_of("MQ20")[0] == m20, "컨베이어로 들어와도 작물·광석·주괴는 안 셈")
	# 가방에 밀이 없으니 가공기 창의 [퀘스트 재료 사용] → 5회 (재료 없이 실제 가공 시간)
	inv.remove("wheat", inv.count_of("wheat"))
	for i in 8:
		Events.time_advanced.emit(30.0)
	hud.open_processor(proc)
	await get_tree().process_frame
	var pp := hud._processor
	pp._select("flour")
	pp._set_runs(5)
	pp.refresh()
	_check(pp._quest_btn.visible and pp._quest_btn.text.contains("MQ20 남은 5회"), "가공기 창: [퀘스트 재료 사용] 보임 (%s)" % pp._quest_btn.text)
	pp._quest_btn.pressed.emit()
	_check(proc.queue.size() == 5 and inv.count_of("wheat") == 0 and qm.quest_material_left("MQ20") == 0, "퀘스트 재료로 밀가루 5회 시작 (가방 밀 0)")
	hud._close_panels()
	for i in 24:
		Events.time_advanced.emit(30.0)
	_check(qm.state_of("MQ20") == QuestManager.REWARDED and qm.flags.has("electric_project_open"), "MQ20: 가공 → 컨베이어 → 창고 입고 5 → 완료 (창고 밀가루 %d → %d)" % [before, wh.storage.count_of("flour")])
	var money_after := GameState.money
	qm._try_rewards()
	qm._activate_ready()
	_check(GameState.money == money_after and qm.state_of("MQ20") == QuestManager.REWARDED, "보상은 한 번만 (다시 불러도 그대로)")
	_check(qm.quests.values().all(func(st: Dictionary) -> bool: return st.state == QuestManager.REWARDED), "MQ01 ~ MQ20 모두 완료")
	# 끝난 MQ20 은 퀘스트 재료를 쓸 수 없음 (쓴 기록을 지워도)
	var d20 := qm.to_data()
	d20.quest_material_used = {}
	qm.load_data(d20)
	_check(qm.quest_material_left("MQ20") == 0 and not qm.quest_material_usable(), "끝난 MQ20 은 퀘스트 재료 비활성")
	_check(qm.project_problem("electric_repair") == "", "MQ20 뒤: 전력 복구 프로젝트를 시작할 수 있음")

	# 기존 저장의 수동 가공기 (belt_out 키 없음): 컨베이어로 저절로 빠져나가지 않음
	var old := Processor.new()
	old.setup(PlaceableDB.get_def("manual_processor"), Vector2i(-50, -50), 0)
	old.load_state({"recipe": "flour", "output": [{"id": "flour", "count": 2, "quality": Quality.NONE}]})
	_check(not old.belt_out and old.provide_item().is_empty() and old.output_count() == 2, "예전 저장 가공기: 컨베이어 출력 꺼짐 (결과물 그대로)")
	old.belt_out = true
	_check(not old.provide_item().is_empty(), "켜면 컨베이어로 내보냄")
	old.free()

	# 정리
	world.build.load_data(saved_build)
	world.obstacles.load_data(saved_obstacles)
	qm.load_data(saved_story)
	inv.load_data(saved_inv)
	GameState.money = saved_money
	GameState.unlocks = saved_unlocks
	player.global_position = saved_pos
	await get_tree().process_frame


## 대화 창 버튼 글
func _dialog_options(hud: HUD) -> Array:
	return hud._dialog._buttons.get_children().map(func(b: Node) -> String: return (b as Button).text)


## 장애물을 도구로 깰 때까지 친다
func _break(grid: ObstacleGrid, cell: Vector2i, tool_id: String) -> void:
	var tool := ItemDB.get_item(tool_id)
	for i in 20:
		if grid.obstacle_at(cell) == null:
			return
		grid.try_clear(cell, tool)
	await get_tree().process_frame


## 가공기(2x2) → 벨트 5칸 → 창고(4x4) 가 들어갈 자리 (장애물은 치움). 위아래 한 줄 여유
func _factory_line_spot(world: FarmWorld) -> Vector2i:
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in range(-1, 5):
			for x in 11:
				var cc := c + Vector2i(x, y)
				if not world.farm.farmable_cells.has(cc) or world.build.is_occupied(cc) or world.farm.tiles.has(cc):
					ok = false
					break
			if not ok:
				break
		if ok:
			for y in range(-1, 5):
				for x in 11:
					world.obstacles.remove(c + Vector2i(x, y))
			return c
	return Vector2i(-1, -1)


## 스토리 3단계: 새 게임 시대 제한 (상점·대장간·건설·광산·정류장) · 복구 프로젝트 · 기술 탭 · 기존 저장
func _test_story_tech(world: FarmWorld, hud: HUD) -> void:
	var qm := world.quests
	var inv := GameState.inventory
	var player := world.player
	var saved_story := qm.to_data()
	var saved_inv := inv.to_data()
	var saved_money := GameState.money
	var saved_pos := player.global_position
	var saved_sky: Variant = GameState.unlocks.get(SkyMarket.UNLOCK, null)
	GameState.unlocks.erase(SkyMarket.UNLOCK)
	player.global_position = world.home_position
	qm.new_game()
	GameState.money = 50000

	# 새 게임: 잠긴 기계는 못 삼 (해금 조건 표시)
	var conveyor := ItemDB.get_item("conveyor")
	var lock := ShopPanel.buy_problem(conveyor, 1)
	_check(lock == "잠김 · 기계 기술 복구 프로젝트 (MQ16)에서 해금", "새 게임: 컨베이어 잠김 + 해금 조건 (%s)" % lock)
	Events.shop_requested.emit("machine")
	var rows := hud._shop._buy_list.get_children()
	var conv_row: Node = rows.filter(func(r: Node) -> bool: return r.get_child(1).text == "컨베이어")[0]
	_check((conv_row.get_child(2) as Label).text.begins_with("잠김 ·") and (conv_row.get_child(3) as Button).disabled, "기계상점: 잠긴 기계는 조건 표시, 사기 버튼 꺼짐")
	var money0 := GameState.money
	hud._shop._buy("conveyor", 1)
	_check(GameState.money == money0 and inv.count_of("conveyor") == 0, "잠긴 기계는 사지 못함 (돈·가방 그대로)")
	hud._close_panels()
	# 대장간: 용광로·도구 강화는 금속시대
	Events.shop_requested.emit("smith")
	var smith_names := hud._shop._buy_list.get_children().map(func(r: Node) -> String: return r.get_child(1).text)
	_check(hud._shop._title.text == "대장간 · 사기" and smith_names == ["용광로"] and ShopPanel.buy_problem(ItemDB.get_item("furnace"), 1).contains("광산 입구 수리"), "대장간에서 용광로 판매, 지금은 잠김 (광산 입구 수리)")
	hud._close_panels()
	inv.load_data([])
	inv.add("hoe")
	inv.add("copper_bar", 5)
	_check(ToolUpgrade.check(inv, 0).reason.begins_with("도구 강화는 잠김"), "도구 강화도 금속시대 전엔 잠김 (%s)" % ToolUpgrade.check(inv, 0).reason)
	# 건설: 잠긴 시설은 새로 못 놓음 (가방에 있어도), 이미 놓은 건 옮기기 가능
	inv.add("conveyor", 3)
	world.build_mode.start_place("conveyor")
	_check(not world.build_mode.is_active(), "가방에 있어도 잠긴 시설은 건설 모드로 놓지 못함")
	world.build_mode.start_place("scarecrow")
	_check(not world.build_mode.is_active() and qm.lock_reason("scarecrow").contains("낡은 제작대 복구"), "허수아비도 제작대 복구(MQ08) 전엔 잠김")
	hud.open_build_panel()
	var brow: Node = hud._build._list.get_children().filter(func(r: Node) -> bool: return (r.get_child(1).get_child(0) as Label).text.begins_with("허수아비"))[0]
	_check((brow.get_child(2) as Label).text.begins_with("잠김 ·") and (brow.get_child(3) as Button).disabled, "건설 창: 잠긴 시설은 조건 표시, 배치 버튼 꺼짐")
	hud._close_panels()
	var spot := _free_origin(world, PlaceableDB.get_def("scarecrow"), Vector2i(-1, -1))
	world.obstacles.remove(spot)
	var crow := world.build.place(PlaceableDB.get_def("scarecrow"), spot)
	var spot2 := _free_origin(world, PlaceableDB.get_def("scarecrow"), spot)
	world.obstacles.remove(spot2)
	_check(crow != null and world.build.move(crow, spot2) and crow.cell == spot2, "이미 놓은 시설은 잠겨도 그대로 옮길 수 있음")
	world.build.remove(crow)
	# 광산 입구·하늘섬 정류장
	world.mine_entrance.interact(player)
	_check(world.area == "farm" and qm.lock_reason("") == "" and not qm.is_unlocked("mine_access"), "새 게임: 광산 입구는 막혀 있음 (들어가지 않음)")
	_check(SkyMarket.restore_problem(inv).begins_with("하늘섬 정류장은 잠김"), "새 게임: 하늘섬 정류장 복구는 첨단시대 (%s)" % SkyMarket.restore_problem(inv))

	# 복구 프로젝트: 퀘스트가 진행 중일 때만, 나눠 넣기, 저장 유지, 완료는 한 번
	_check(qm.project_problem("workbench_repair") == "MQ08 퀘스트를 받으면 시작할 수 있어요." and qm.donate("workbench_repair", "wood") == 0, "MQ08 전에는 제작대 복구에 못 넣음")
	for id: String in ["MQ01", "MQ02", "MQ03", "MQ04", "MQ05", "MQ06", "MQ07"]:
		qm.quests[id].state = QuestManager.REWARDED
	qm._activate_ready()
	inv.load_data([])
	inv.add("wood", 10)
	_check(qm.donate("workbench_repair", "wood") == 10 and inv.count_of("wood") == 0 and not qm.project_done("workbench_repair"), "목재 10 넣음 (15 중), 가방에서 정확히 10 빠짐")
	world.save_manager.save_game("manual")
	qm.new_game()
	world.save_manager.load_game()
	var wb_rows := qm.project_rows("workbench_repair")
	_check(wb_rows[0].given == 10 and wb_rows[0].need == 15 and wb_rows[1].given == 0 and qm.state_of("MQ08") == QuestManager.ACTIVE, "저장·불러오기 후 넣은 양 그대로 (목재 10/15, 돌 0/10)")
	inv.add("wood", 9)
	inv.add("stone", 10)
	_check(qm.donate("workbench_repair", "wood") == 5 and inv.count_of("wood") == 4, "남은 만큼만 넣음 (목재 5, 4개는 가방에)")
	_check(qm.donate("workbench_repair", "stone") == 10 and qm.project_done("workbench_repair") and qm.is_unlocked("basic_buildings"), "다 차면 완료 → 기본 건설 시설 해금")
	_check(qm.state_of("MQ08") == QuestManager.REWARDED and qm.state_of("MQ09") == QuestManager.ACTIVE, "프로젝트 완료 → MQ08 완료, MQ09 시작")
	inv.add("stone", 5)
	_check(qm.donate("workbench_repair", "stone") == 0 and inv.count_of("stone") == 5, "끝난 프로젝트에는 더 안 들어감")
	world.build_mode.start_place("scarecrow")
	_check(world.build_mode.is_active(), "해금 뒤: 허수아비를 건설 모드로 놓을 수 있음")
	world.build_mode.stop()
	# 광산 입구 수리 (MQ11) → 금속시대: 광산·용광로·도구 강화
	for id: String in ["MQ09", "MQ10"]:
		qm.quests[id].state = QuestManager.REWARDED
	qm._activate_ready()
	inv.add("wood", 10)
	inv.add("stone", 10)
	qm.donate("mine_repair", "wood")
	qm.donate("mine_repair", "stone")
	_check(qm.project_done("mine_repair") and qm.era == "metal" and qm.is_unlocked("mine_access") and qm.lock_reason("furnace") == "" and not ShopPanel.buy_problem(ItemDB.get_item("furnace"), 1).begins_with("잠김"), "광산 입구 수리 → 금속시대, 광산·용광로 해금")
	world.mine_entrance.interact(player)
	_check(world.area == "mine", "광산 입구가 열림")
	world.exit_mine()
	inv.load_data([])
	inv.add("hoe")
	inv.add("copper_bar", 3)
	_check(ToolUpgrade.check(inv, 0).ok, "금속시대: 도구 강화 가능")
	# 기계 기술 복구 (MQ16): 구리 주괴 8 + 500 G → 기계시대, 컨베이어 등
	for id: String in ["MQ11", "MQ12", "MQ13", "MQ14", "MQ15"]:
		qm.quests[id].state = QuestManager.REWARDED
	qm._activate_ready()
	inv.add("copper_bar", 8)
	var m1 := GameState.money
	qm.donate("mechanical_research", "copper_bar")
	_check(qm.donate("mechanical_research", "money") == 500 and GameState.money == m1 - 500 and qm.project_done("mechanical_research") and qm.era == "mechanical", "구리 주괴 8 + 500 G → 기계시대 (돈도 정확히 500)")
	_check(ShopPanel.buy_problem(conveyor, 1) == "" and qm.is_unlocked("warehouse_basic") and not qm.is_unlocked("splitter"), "기계시대: 컨베이어·창고 해금, 분배기는 MQ18 보상")
	hud._shop._buy("conveyor", 1)
	_check(inv.count_of("conveyor") == 1, "해금 뒤 컨베이어를 살 수 있음")
	world.build_mode.start_place("conveyor")
	_check(world.build_mode.is_active(), "해금 뒤 컨베이어를 놓을 수 있음")
	world.build_mode.stop()
	_check(qm.project_problem("advanced_research") == "아직 준비 중이에요." and qm.project_problem("electric_repair").contains("MQ20"), "전력 복구는 MQ20 뒤, 첨단 연구는 준비 중 (구조만)")

	# 기술 탭: 시대별 기술 (열림/잠김 + 해금 조건), 프로젝트 진행도·남은 재료
	hud.open_quest_log()
	hud._quest_log.show_tab("tech")
	var texts := hud._quest_log._list.get_children().filter(func(n: Node) -> bool: return n is Label).map(func(l: Label) -> String: return l.text)
	_check(texts.has("기계시대  (지금)") and texts.any(func(t: String) -> bool: return t.begins_with("· 열림  컨베이어")) and texts.any(func(t: String) -> bool: return t.begins_with("· 잠김  전력") and t.contains("전력 복구 프로젝트 (MQ20 뒤)에서 해금")), "기술 탭: 지금 시대 · 열린 기술 · 잠긴 기술과 해금 조건")
	var pr_box := hud._quest_log._list.get_node("electric_repair")
	var pr_line := (pr_box.get_child(1) as HBoxContainer).get_child(0) as Label
	_check((pr_box.get_child(0) as Label).text.contains("MQ20") and pr_line.text.begins_with("· 철 주괴  넣은 양 0/10") and pr_line.text.contains("남은 것 10"), "기술 탭: 프로젝트 넣은 양·가진 것·남은 것 (%s)" % pr_line.text)
	_check((hud._quest_log._list.get_node("mine_repair").get_child(0) as Label).text.ends_with("완료"), "기술 탭: 끝난 프로젝트는 완료")
	hud._quest_log.show_tab("quests")
	hud._close_panels()

	# 기존 저장: 모든 기술 열림, 광산·정류장 그대로
	qm.load_data({"legacy": true})
	_check(ShopPanel.buy_problem(ItemDB.get_item("harvester_3"), 1) != "" and not ShopPanel.buy_problem(ItemDB.get_item("harvester_3"), 1).begins_with("잠김") and SkyMarket.restore_problem(inv).find("잠김") < 0, "기존 저장: 잠김 없음 (돈만 확인), 정류장 복구도 잠기지 않음")
	world.mine_entrance.interact(player)
	_check(world.area == "mine", "기존 저장: 광산 그대로 열림")
	world.exit_mine()

	# HUD 추적 한 단계 크게 (사용자 결정): 제목 큰 글씨
	qm.new_game()
	await get_tree().process_frame
	_check(hud._quest_tracker._title.get_theme_font_size("font_size") == Art.FONT_SIZE and hud._quest_tracker.size.x >= 340, "HUD 추적: 제목 큰 글씨, 폭 넓힘 (%s)" % hud._quest_tracker.size)

	# 정리
	qm.load_data(saved_story)
	inv.load_data(saved_inv)
	GameState.money = saved_money
	player.global_position = saved_pos
	if saved_sky != null:
		GameState.unlocks[SkyMarket.UNLOCK] = saved_sky
	await get_tree().process_frame


## 광산 (사용자 결정: 북쪽 숲길 끝 입구 · 아래로 내려가는 층 · 엘리베이터 · 사다리 찾기 · 10층마다 보물 층 · 광석 4종)
## 광산에서 나온 직후(화면 전환 중) 창을 열어도 전환은 끝까지 → 닫으면 일시정지·시간 정상 (회귀 방지)
func _test_mine_exit_fade(world: FarmWorld, hud: HUD) -> void:
	for what: String in ["quest_log", "inventory", "build"]:
		Events.mine_requested.emit(0)
		await get_tree().process_frame
		world.exit_mine()
		match what:
			"quest_log": hud.open_quest_log()
			"inventory": hud.open_inventory()
			"build": hud.open_build_panel()
		await get_tree().create_timer(1.0).timeout
		var a: float = hud._fade.modulate.a
		hud._close_panels()
		await get_tree().process_frame
		_check(a == 0.0 and not get_tree().paused and not GameState.is_time_paused() and world.area == "farm", "광산에서 나오자마자 %s 열어도 화면 전환 끝까지 (어둠 %.2f), 닫으면 정상" % [what, a])


func _test_mine(world: FarmWorld, hud: Node) -> void:
	var mine := world.mine
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var saved_unlocks := GameState.unlocks.duplicate(true)
	var saved_money := GameState.money
	var saved_pos := world.player.global_position
	GameState.unlocks.erase("mine_deepest")
	for k: String in GameState.unlocks.keys():
		if k.begins_with("mine_chest:"):
			GameState.unlocks.erase(k)
	# 입구: 북쪽 숲길 맨 위 (길 칸 앞)
	var front := world.world_to_cell(world.mine_entrance.interact_point())
	_check(MapLayout.char_at(front) == "p" and front.y <= 4 and front.x >= 84 and front.x <= 86, "광산 입구: 북쪽 숲길 끝 %s" % front)
	_check(ItemDB.get_item("coal") != null and ItemDB.get_item("copper_ore") != null and ItemDB.get_item("iron_ore") != null and ItemDB.get_item("iron_ore").sell_price == int(_econ().materials.iron_ore), "광석 3종 = 경제 기준")
	# 제련 검산 (사용자 결정): 석탄값까지 넣어도 적자가 아니고, 이익률이 상한(checks.smelt_margin_max)을 넘지 않음
	var smelt_ok := true
	var smelt_txt := []
	var fcfg: Dictionary = PlaceableDB.get_def("furnace").data.furnace.recipes
	for ore: String in fcfg:
		var r: Dictionary = fcfg[ore]
		var cost := int(r.ore) * ItemDB.get_item(ore).sell_price + int(r.coal) * ItemDB.get_item("coal").sell_price
		var bar := ItemDB.get_item(str(r.output)).sell_price
		smelt_ok = smelt_ok and bar > cost and (bar - cost) / float(cost) <= float(_econ().checks.smelt_margin_max)
		smelt_txt.append("%s %+d" % [ItemDB.get_item(str(r.output)).name, bar - cost])
	_check(smelt_ok, "제련: 적자 없음, 이익률 상한 안 (%s)" % ", ".join(smelt_txt))
	_check(not Mine.rock_weights(1).has("mine_iron") and Mine.rock_weights(12).has("mine_iron") and Mine.rock_weights(10).has("mine_iron") and Mine.bottom() == 20, "깊이별 바위: 철은 10층부터, 1단계 바닥 20층")
	_check(not Mine.view_rect().intersects(SkyIsland.view_rect()) and not Mine.view_rect().intersects(Interior.view_rect_of("machine")) and not Mine.view_rect().intersects(Rect2(Vector2.ZERO, Vector2(MapLayout.size() * FarmWorld.TILE))), "광산 자리가 농장·하늘섬·가게와 겹치지 않음")
	# 들어가기 → 입구층
	world.mine_entrance.interact(world.player)
	_check(world.area == "mine" and mine.floor_no == 0 and mine.rocks.count() == 0 and world.player.global_position.distance_to(mine.arrive_position()) < 1.0, "[E] 입구 → 입구층 (바위 없음)")
	_check(world._daylight.color == Mine.LIGHT, "광산 안은 늘 같은 등불 빛")
	var kinds := mine._features.map(func(f: MineFeature) -> int: return f.kind)
	_check(MineFeature.Kind.ELEVATOR in kinds and MineFeature.Kind.DOWN in kinds and mine.has_ladder(), "입구층: 엘리베이터 + 내려가는 사다리")
	_check(mine.is_exit(Mine.ORIGIN + Mine.EXIT_CELLS[0]) and not mine.is_exit(Mine.ORIGIN + Vector2i(5, 5)), "입구층 아래 출구 칸")
	var elevator: MineFeature = mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.ELEVATOR)[0]
	elevator._fill_options()
	_check(elevator.options.size() == 1 and elevator.greeting.contains("5층"), "처음엔 열린 정류장 없음 (%s)" % elevator.greeting)
	# 1층: 바위 깔림, 사다리는 아직
	var down: MineFeature = mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.DOWN)[0]
	down.interact(world.player)
	_check(mine.floor_no == 1 and Mine.deepest() == 1 and mine.rocks.count() >= 26 and mine.rocks.count() <= 36 and not mine.has_ladder(), "사다리 → 1층 (바위 %d개, 사다리 아직 없음)" % mine.rocks.count())
	var ids := mine.rocks.all().map(func(o: Obstacle) -> String: return o.def.id)
	_check(not ids.has("mine_iron") and ids.has("mine_stone"), "1층엔 철 바위 없음")
	var walls_ok := true
	for o: Obstacle in mine.rocks.all():
		if mine.is_wall(o.cell - Mine.ORIGIN) or (o.cell - Mine.ORIGIN).distance_to(Mine.UP_LADDER_AT + Vector2i.DOWN) < 2.5:
			walls_ok = false
	_check(walls_ok, "바위는 벽·내려선 자리 위에 생기지 않음")
	# 곡괭이로 깨다 보면 사다리가 나온다 (마지막 바위면 반드시)
	inv.load_data([])
	var pick := ItemDB.get_item("pickaxe_2")
	var broke := 0
	var safety := 0
	while not mine.has_ladder() and mine.rocks.count() > 0 and safety < 400:
		safety += 1
		var o: Obstacle = mine.rocks.all()[0]
		mine.rocks.try_clear(o.cell, pick)
		if mine.rocks.obstacle_at(o.cell) == null:
			broke += 1
	var ladder := mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.DOWN)
	_check(mine.has_ladder() and ladder.size() == 1 and inv.count_of("stone") + inv.count_of("coal") + inv.count_of("copper_ore") > 0, "바위 %d개 깨서 사다리 찾음 · 광석이 가방에" % broke)
	_check(ladder.size() == 1 and (ladder[0] as MineFeature).prompt.contains("2층") and (ladder[0] as MineFeature).z_index == -1, "새 사다리: 깬 바위 자리, 바닥에 깔림")
	# 철 바위: 강화 곡괭이(2단계)가 있어야
	var spot := Mine.ORIGIN + Vector2i(15, 9)
	mine.rocks.remove(spot)
	mine.rocks.spawn(spot, "mine_iron", 1)
	for i in 3:
		mine.rocks.try_clear(spot, ItemDB.get_item("pickaxe"))
	_check(mine.rocks.obstacle_at(spot) != null, "철 바위: 돌 곡괭이 3번엔 아직")
	mine.rocks.try_clear(spot, ItemDB.get_item("pickaxe"))
	_check(mine.rocks.obstacle_at(spot) == null and inv.count_of("iron_ore") >= 1, "철 바위: 돌 곡괭이 4번에 철 광석")
	# 5층에 닿으면 정류장이 열리고, 엘리베이터로 오간다
	Events.mine_requested.emit(5)
	_check(mine.floor_no == 5 and Mine.deepest() == 5 and Mine.elevator_stops() == [0, 5], "5층 도착 → 정류장 열림 %s" % [Mine.elevator_stops()])
	var el5 := mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.ELEVATOR)
	_check(el5.size() == 1 and mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.UP).size() == 1, "5층: 엘리베이터 + 올라가는 사다리")
	(el5[0] as MineFeature)._fill_options()
	_check((el5[0] as MineFeature).options[0] == ["입구층", "mine:0"], "5층 엘리베이터 → 입구층 버튼")
	hud._on_dialog_chosen("mine:0")
	_check(mine.floor_no == 0 and world.area == "mine", "엘리베이터 대화 → 입구층")
	elevator = mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.ELEVATOR)[0]
	elevator._fill_options()
	_check(elevator.options[0] == ["5층", "mine:5"], "입구층 엘리베이터 → 5층 버튼")
	# 보물 층 (10층): 상자는 처음 한 번만
	Events.mine_requested.emit(10)
	var chest := mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.CHEST)
	_check(chest.size() == 1 and mine.rocks.count() >= 40 and not mine.rocks.all().any(func(o: Obstacle) -> bool: return o.def.id == "mine_stone"), "10층 보물 층: 상자 + 광석 바위 %d개" % mine.rocks.count())
	var money := GameState.money
	var copper := inv.count_of("copper_ore")
	(chest[0] as MineFeature).interact(world.player)
	_check(GameState.money == money + 800 and inv.count_of("copper_ore") == copper + 15 and GameState.unlocks.get("mine_chest:10", false), "보물 상자: 800 G + 구리 광석 15")
	Events.mine_requested.emit(10)
	_check(mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.CHEST).is_empty(), "다시 와도 상자는 없음")
	# 맨 아래층(20층)은 사다리가 나오지 않는다
	Events.mine_requested.emit(20)
	while mine.rocks.count() > 0:
		var o: Obstacle = mine.rocks.all()[0]
		mine.rocks.remove(o.cell)
		mine._on_rock_cleared(o.cell, o.def)
	_check(mine.floor_no == 20 and not mine.has_ladder() and Mine.elevator_stops() == [0, 5, 10, 15, 20], "20층(바닥): 사다리 없음, 정류장 %s" % [Mine.elevator_stops()])
	Events.mine_requested.emit(99)
	_check(mine.floor_no == 20, "바닥보다 깊이는 못 감")
	# 광산 안에서 불러오면 입구층에서 시작
	Events.mine_requested.emit(7)
	Events.game_loaded.emit()
	_check(mine.floor_no == 0 and world.area == "mine", "광산 안에서 불러오면 입구층")
	# 출구 → 입구 앞
	world.exit_mine()
	_check(world.area == "farm" and world.player.global_position.distance_to(world.mine_entrance.interact_point()) < 10.0 and world._daylight.color != Mine.LIGHT, "출구 → 동굴 입구 앞, 햇빛으로")
	inv.load_data(saved_inv)
	GameState.unlocks = saved_unlocks
	GameState.money = saved_money
	world.player.wake_at(saved_pos)
	world._apply_camera_area()


func _test_mid_processor(world: FarmWorld) -> void:
	var grid := world.build
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var mid_def := PlaceableDB.get_def("mid_processor")
	var ep_def := PlaceableDB.get_def("electric_processor")
	var item := ItemDB.get_item("mid_processor")
	_check(mid_def != null and mid_def.size == Vector2i(3, 3) and mid_def.machine_item() == item and item.shop == "machine" and item.buy_price == int(_econ().machines.mid_processor), "중급 가공기 정의 (3x3, 기계상점 %d G + 재료)" % item.buy_price)
	# 양배추 (봄) + 중급·상급 레시피 (상급은 상급 가공기가 생기기 전까지 중급 가공기에서, 사용자 결정)
	var cab := ItemDB.get_item("cabbage_seed")
	_check(cab != null and cab.grows == "cabbage" and cab.seasons == ["spring"] and Calendar.crop_allowed(cab, "spring") and not Calendar.crop_allowed(cab, "summer"), "양배추 씨앗: 봄 작물")
	var tier2 := RecipeDB.all().filter(func(r: Dictionary) -> bool: return int(r.tier) >= 2).map(func(r: Dictionary) -> String: return r.id)
	var high := RecipeDB.all().filter(func(r: Dictionary) -> bool: return int(r.tier) == 3)
	_check(tier2.size() == 12 and high.size() == 6 and high.all(func(r: Dictionary) -> bool: return int(r.machine_tier) == 2), "중급 6 + 상급 6, 상급은 지금 중급 가공기에서 %s" % [high.map(func(r: Dictionary) -> String: return r.id)])
	var pj := RecipeDB.get_recipe("premium_jam_strawberry")
	_check(pj.inputs == {"strawberry_jam": 1, "blueberry_jam": 1} and pj.input_quality.is_empty() and not RecipeDB.inputs_text(pj).contains("골드"), "고급잼: 딸기잼 + 블루베리잼, 품질 조건 없음 (%s)" % RecipeDB.inputs_text(pj))
	# 자리: 창고(4x4) | 중급 가공기(3x3) — 맞닿게
	var origin := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 5:
			for x in 12:
				var fc := c + Vector2i(x, y)
				if not grid.is_buildable_ground(fc) or grid.is_occupied(fc) or grid.is_reserved(fc) or world.farm.tiles.has(fc):
					ok = false
		if ok:
			origin = c
			break
	_check(origin.x >= 0, "중급 가공기 자리 찾음 %s" % origin)
	# 플레이어가 그 자리에 서 있으면 설치가 막히므로 잠깐 비켜 둔다 (앞 점검들이 어디서 끝났는지와 상관없이)
	world.player.global_position = world.cell_center(origin + Vector2i(6, 7))
	if origin.x < 0:
		return
	for y in 5:
		for x in 12:
			world.obstacles.remove(origin + Vector2i(x, y))
	var wh := grid.place(PlaceableDB.get_def("warehouse"), origin) as Warehouse
	var mid := grid.place(mid_def, origin + Vector2i(4, 0)) as Processor
	var ep := grid.place(ep_def, origin + Vector2i(8, 0)) as Processor
	_check(mid != null and mid.tier() == 2 and is_equal_approx(mid.speed(), 2.0) and mid.input_runs() == 4 and mid.max_output() == 60 and mid.warehouses().size() == 1, "중급: 2급 · 2배 빠름 · 재료 4회분 · 보관 60 · 맞닿은 창고")
	_check(is_equal_approx(float(mid.recipe_for("flour").minutes), 30.0) and is_equal_approx(float(ep.recipe_for("flour").minutes), 60.0), "밀가루 60분 → 중급은 30분")
	for id: String in tier2:
		GameState.unlocks["recipe:" + id] = true
	_check(ep.recipe_problem("pickled_cabbage") == "더 좋은 가공기가 필요해요." and mid.recipe_problem("pickled_cabbage") == "" and mid.recipe_problem("flour") == "" and mid.recipe_problem("pumpkin_pie") == "" and ep.recipe_problem("pumpkin_pie") != "", "중급·상급 레시피는 중급 가공기에서만 (하급도 중급에서 됨)")
	_check(is_equal_approx(float(mid.recipe_for("pumpkin_pie").minutes), 90.0), "상급 180분 → 중급 가공기는 2배 빨라 90분")
	# 고급잼: 품질 상관없이 받음
	_check(mid.set_recipe("premium_jam_strawberry"), "중급에 고급잼 레시피 정하기")
	_check(mid.accept_item("strawberry_jam", "silver") and mid.accept_item("blueberry_jam", "bronze") and not mid.accept_item("strawberry", "gold"), "벨트 입구: 딸기잼·블루베리잼은 품질 상관없이, 다른 재료는 안 받음")
	wh.storage.add("strawberry_jam", 2, "silver")
	wh.storage.add("blueberry_jam", 2, "gold")
	_check(mid._pull_run(mid.recipe()) and mid._pull_run(mid.recipe()), "받아 둔 것 + 맞닿은 창고로 회분 시작")
	inv.load_data([])
	inv.add("strawberry_jam", 2, "silver")
	inv.add("blueberry_jam", 1, "bronze")
	var r := RecipeDB.get_recipe("premium_jam_strawberry")
	_check(Processor.runs_possible(inv, r, 9) == 1, "가방: 딸기잼 2 + 블루베리잼 1 → 1회")
	# 옛 id 로 정해도 지금 레시피로
	_check(mid.set_recipe("premium_jam_blueberry") and mid.recipe_id == "premium_jam_strawberry", "옛 id(premium_jam_blueberry) → 지금 고급잼")
	# 정리
	for id: String in tier2:
		GameState.unlocks.erase("recipe:" + id)
	for o: Placeable in [mid, ep, wh]:
		o.take_contents()
		grid.remove(o)
	inv.load_data(saved_inv)


## 물탱크로 물뿌리개 채우기 (사용자 요청): [E] · 물뿌리개로 클릭 모두, 지역 물통에서 꺼낸다
func _test_tank_refill(world: FarmWorld) -> void:
	var grid := world.build
	var inv := GameState.inventory
	var def := PlaceableDB.get_def("water_tank")
	var spot := _free_origin(world, def, Vector2i(-1, -1))
	for y in 3:
		for x in 2:
			world.obstacles.remove(spot + Vector2i(x, y))
	var tank := grid.place(def, spot) as WaterTank
	_check(tank != null and tank.is_in_group(WateringCan.WATER_SOURCES) and tank.is_in_group("interactables"), "물탱크는 물 공급원 + [E]")
	var can_index := -1
	for i in inv.size():
		if inv.get_slot(i) != null and inv.get_slot(i)["id"] == "watering_can":
			can_index = i
	inv.set_slot_value(can_index, "water", 0)
	var cap := WateringCan.capacity_of(inv, can_index)
	tank.water = 5.0
	tank.interact(world.player)
	_check(WateringCan.water_left(inv, can_index) == 5 and is_equal_approx(tank.water, 0.0), "물이 5뿐이면 5만 채움")
	tank.water = 100.0
	_check(WateringCan.use(world, spot, inv, can_index) and WateringCan.water_left(inv, can_index) == cap and is_equal_approx(tank.water, 100.0 - (cap - 5)), "물뿌리개로 물탱크 클릭 → 가득 (%d)" % cap)
	inv.set_slot_value(can_index, "water", 0)
	tank.water = 0.0
	_check(not WateringCan.use(world, spot, inv, can_index) and WateringCan.water_left(inv, can_index) == 0, "빈 물탱크로는 못 채움")
	grid.remove(tank)


## 집·출하함·우물 옮기기 (사용자 결정: 건설 모드에서 농장 땅 어디로든, 철거는 안 됨)
func _test_fixtures(world: FarmWorld) -> void:
	var grid := world.build
	var bm := world.build_mode
	var player := world.player
	var fixtures := grid.objects().filter(func(o: Placeable) -> bool: return o is Fixture)
	_check(fixtures.size() == 3 and world.fixture_buildings.size() == 3, "집·출하함·우물 자리표 3개")
	var house_fx: Fixture = fixtures.filter(func(o: Placeable) -> bool: return o.def.id == "house")[0]
	var bin_fx: Fixture = fixtures.filter(func(o: Placeable) -> bool: return o.def.id == "shipping_bin")[0]
	var well_fx: Fixture = fixtures.filter(func(o: Placeable) -> bool: return o.def.id == "well")[0]
	var house: House = world.fixture_buildings["house"]
	var home0 := world.home_position
	var house_cell0 := house_fx.cell
	_check(house_cell0 == _find_char("H") and house.position == Vector2(house_cell0.x * FarmWorld.TILE, (house_cell0.y + 3) * FarmWorld.TILE), "집 자리표 = 맵의 집 자리")
	var panel_rows := PlaceableDB.all().filter(func(d: PlaceableDef) -> bool: return d.data.has("fixture"))
	_check(panel_rows.size() == 3, "고정 건물 정의 3개 (건설 창 목록에는 안 나옴)")

	# 철거 불가
	player.global_position = world.cell_center(_find_char("s"))
	bm.start(BuildMode.Mode.REMOVE)
	_check(not bm.try_remove(house_cell0) and grid.object_at(house_cell0) == house_fx and is_instance_valid(house), "집은 철거할 수 없음")
	bm.stop()

	# 앞 한 줄은 비워 둠: 집 앞에 허수아비를 못 놓음 (농장 땅이 아니어도 '앞 줄' 이유가 먼저인지 보려고 check 로)
	var front := house_fx.front_cells()
	_check(front.size() == 4 and front[0] == house_cell0 + Vector2i(0, 3) and grid.is_reserved(front[1]), "집 앞 4칸은 비워 둘 칸")

	# 농장 땅 빈 자리 찾기 (집 4x3·출하함·우물 + 앞 한 줄이 들어갈 10x5)
	var target := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := c.x > 12
		for y in 5:
			for x in 10:
				var fc := c + Vector2i(x, y)
				if not world.farm.farmable_cells.has(fc) or grid.is_occupied(fc) or world.farm.tiles.has(fc):
					ok = false
		if ok:
			target = c
			break
	_check(target.x >= 0, "집 옮길 자리 찾음 %s" % target)
	for y in 5:
		for x in 4:
			world.obstacles.remove(target + Vector2i(x, y))
	world.obstacles.spawn(target + Vector2i(1, 3), "weed")
	await get_tree().process_frame
	bm.start(BuildMode.Mode.MOVE)
	_check(bm.pick(house_cell0 + Vector2i(1, 1)) and house.modulate.a < 1.0, "집 집기 (집이 흐려짐)")
	_check(not bm.try_drop(target), "집 앞 줄에 잡초가 있으면 못 놓음")
	world.obstacles.remove(target + Vector2i(1, 3))
	_check(bm.try_drop(target) and house.modulate.a == 1.0, "농장 땅으로 집 옮기기")
	bm.stop()
	_check(house_fx.cell == target and house.position == Vector2(target.x * FarmWorld.TILE, (target.y + 3) * FarmWorld.TILE), "집 건물이 새 자리로")
	_check(world.home_position == world.cell_center(target + Vector2i(2, 4)) and world.home_position != home0, "깨어나는 자리도 새 집 앞")
	player.global_position = house.interact_point()
	_check(house.can_interact(player.global_position), "새 집 앞에서 [E] 잠자기 가능")
	_check(not grid.is_occupied(house_cell0) and grid.is_buildable_ground(house_cell0), "예전 집 자리는 비고, 다시 지을 수 있는 땅")
	var scarecrow := PlaceableDB.get_def("scarecrow")
	_check(not grid.check(scarecrow, target + Vector2i(1, 3)).ok and grid.check(scarecrow, target + Vector2i(1, 3)).reason.contains("비워"), "새 집 앞에는 시설을 못 놓음")
	_check(not world.obstacles.can_grow_at(target + Vector2i(2, 3)), "집 앞에는 장애물이 다시 자라지 않음")

	# 출하함: 내용물을 넣고 옮겨도 그대로 / 우물: 옮기면 물 공급원 칸도 따라감
	var bin: ShippingBin = world.fixture_buildings["shipping_bin"]
	var bin_cell0 := bin_fx.cell
	GameState.inventory.add("carrot", 2, "bronze")
	bin.deposit(GameState.inventory, "carrot", "bronze", 2)
	var bin_to := Vector2i(target.x + 5, target.y)
	for y in 2:
		for x in 2:
			world.obstacles.remove(bin_to + Vector2i(x, y))
	_check(grid.move(bin_fx, bin_to) and bin.count_of("carrot", "bronze") == 2 and world.shipping_bin == bin and bin.position.x == bin_to.x * FarmWorld.TILE, "출하함 옮겨도 내용물 그대로")
	var well: Well = world.fixture_buildings["well"]
	var well_cell0 := well_fx.cell
	var well_to := Vector2i(target.x + 8, target.y)
	for y in 3:
		for x in 2:
			world.obstacles.remove(well_to + Vector2i(x, y))
	_check(grid.move(well_fx, well_to) and well.covers_cell(well_to) and not well.covers_cell(well_cell0), "우물 옮기면 물 긷는 칸도 따라감")

	# 저장·불러오기: 옮긴 자리 그대로, 예전 저장(자리표 없음)은 건물이 있던 자리에 다시 만듦
	var data := grid.to_data()
	grid.load_data(data)
	await get_tree().process_frame
	var house_fx2: Placeable = grid.object_at(target)
	_check(house_fx2 is Fixture and house_fx2.def.id == "house" and world.home_position == world.cell_center(target + Vector2i(2, 4)), "저장·불러오기: 옮긴 집 그대로")
	grid.load_data(data.filter(func(e: Dictionary) -> bool: return not str(e.id) in ["house", "shipping_bin", "well"]))
	await get_tree().process_frame
	_check(grid.objects().filter(func(o: Placeable) -> bool: return o is Fixture).size() == 3 and grid.object_at(target) is Fixture, "자리표가 없는 예전 저장: 건물 자리에 다시 만듦")

	# 처음 자리로 되돌리기 (농장 땅이 아니어도 처음 자리는 가능)
	bin.withdraw(GameState.inventory, "carrot", "bronze", 2)
	_check(grid.move(grid.object_at(target) as Placeable, house_cell0) and world.home_position == home0, "집을 처음 자리로 되돌림")
	_check(grid.move(grid.object_at(bin_to) as Placeable, bin_cell0) and grid.move(grid.object_at(well_to) as Placeable, well_cell0), "출하함·우물도 처음 자리로")
	await get_tree().process_frame


## 넓힌 메인 광장 (사용자 요청: 가로·세로 모두 더 크게)
func _test_plaza(world: FarmWorld) -> void:
	_check(MapLayout.size() == Vector2i(124, 64), "맵 124x64 (%s)" % MapLayout.size())
	_check(world.farm.farmable_cells.size() >= 1200, "넓힌 농장 경작지 %d칸 (예전 514)" % world.farm.farmable_cells.size())
	var walk := 0
	for y in MapLayout.size().y:
		for x in range(53, MapLayout.size().x):
			if not MapLayout.char_at(Vector2i(x, y)) in ["T", "~", "#", "x", "M", "C", "K", "J", "A", "Y", "B", "R", "*", "P", "e", "=", "l", "u", "4", "6", "7", "8"]:
				walk += 1
	_check(walk >= 2000, "광장 걸을 수 있는 칸 %d (예전 771, 꽃밭·나무로 채움)" % walk)
	_check(MapLayout.char_at(Vector2i(86, 30)) == "F" and MapLayout.char_at(Vector2i(85, 18)) == "p", "분수 광장 + 큰길")
	# 마을 그래픽 정리: 다리는 놓인 방향에 맞춘 타일 (남쪽 = 남북 다리, 좌우 난간 / 서쪽 개울 = 동서 다리, 위아래 난간)
	var gs := world.ground
	_check(gs.get_cell_source_id(Vector2i(84, 54)) == TerrainTileSet.BRIDGE_SOURCE_ID and gs.get_cell_atlas_coords(Vector2i(84, 54)) == Vector2i(8, 1)
		and gs.get_cell_atlas_coords(Vector2i(85, 54)) == Vector2i(0, 1) and gs.get_cell_atlas_coords(Vector2i(86, 54)) == Vector2i(2, 1), "남쪽 다리: 남북 방향, 왼쪽·오른쪽에만 난간 (가운데는 열림)")
	_check(gs.get_cell_atlas_coords(Vector2i(48, 17)) == Vector2i(1, 0) and gs.get_cell_atlas_coords(Vector2i(48, 18)) == Vector2i(4, 0), "서쪽 다리: 동서 방향, 위·아래에만 난간 (두 줄 사이 난간 없음)")
	_check(world.fences.get_cell_source_id(Vector2i(57, 26)) == TerrainTileSet.GARDEN_SOURCE_ID and not MapLayout.PROPS.has("*"), "화단은 땅에 까는 타일 (둥근 꽃덤불 소품 아님)")
	var q := PhysicsPointQueryParameters2D.new()
	q.position = world.cell_center(Vector2i(57, 26))
	var q2 := PhysicsPointQueryParameters2D.new()
	q2.position = world.cell_center(Vector2i(112, 28))
	var space := world.get_world_2d().direct_space_state
	_check(not space.intersect_point(q).is_empty() and space.intersect_point(q2).is_empty(), "화단 칸은 들어갈 수 없음, 정리한 맨흙 자리는 지나갈 수 있음")
	var lamps := 0
	for y in MapLayout.size().y:
		for x in MapLayout.size().x:
			if MapLayout.char_at(Vector2i(x, y)) == "L":
				lamps += 1
	_check(lamps == 21 and MapLayout.char_at(Vector2i(111, 28)) == "." and MapLayout.char_at(Vector2i(72, 44)) == "*", "가로등 21개 (광장·다리 둘레 7개 추가), 파인 땅 정리 (%d)" % lamps)
	# 새 경작지 장애물 (예전 저장): 옛 농장 칸에는 깔지 않고 새 땅에만
	var new_cells := world.farm.farmable_cells.keys().filter(func(c: Vector2i) -> bool: return not MapLayout.is_old_farm_cell(c))
	var old_before := world.obstacles.all().filter(func(o: Obstacle) -> bool: return MapLayout.is_old_farm_cell(o.cell)).size()
	for c: Vector2i in new_cells:
		world.obstacles.remove(c)
	var made := world.obstacles.generate_new_land()
	var old_after := world.obstacles.all().filter(func(o: Obstacle) -> bool: return MapLayout.is_old_farm_cell(o.cell)).size()
	_check(made > new_cells.size() / 4.0 and old_after == old_before, "예전 저장의 새 땅에만 잡초·돌 %d개 (옛 농장 칸 그대로)" % made)
	var right_edge := float(MapLayout.size().x * FarmWorld.TILE)
	_check(SkyIsland.island_rect().position.x > right_edge and Vector2(Interior.origin_of("store") * FarmWorld.TILE).x > SkyIsland.island_rect().end.x, "하늘섬·가게 실내는 넓힌 맵 밖")
	# 예전(버전 1) 저장: 광장에 서 있었으면 집 앞으로, 농장이면 그대로
	var old := {"version": 1, "sections": {"player": {"position": [50.0 * FarmWorld.TILE, 20.0 * FarmWorld.TILE]}}}
	var moved: Dictionary = world.save_manager._migrate(old)
	var farm_pos := [10.0 * FarmWorld.TILE, 20.0 * FarmWorld.TILE]
	var kept: Dictionary = world.save_manager._migrate({"version": 1, "sections": {"player": {"position": farm_pos.duplicate()}}})
	_check(moved.version == SaveManager.VERSION and Vector2(moved.sections.player.position[0], moved.sections.player.position[1]) == world.home_position and kept.sections.player.position == farm_pos, "예전 저장: 광장에 있었으면 집 앞, 농장이면 그대로")
	var in_room: Dictionary = world.save_manager._migrate({"version": 2, "sections": {"player": {"position": [165.0 * FarmWorld.TILE, 20.0 * FarmWorld.TILE]}}})
	_check(Vector2(in_room.sections.player.position[0], in_room.sections.player.position[1]) == world.home_position, "버전 2 저장: 옛 가게 실내 자리에 있었으면 집 앞 (방 자리 바뀜)")
	_check(Interior.door_cell("store") == Vector2i(8, 11) and Interior.size_of("store") == Vector2i(18, 12) and Interior.size_of("smith") == Vector2i(18, 12) and Interior.size_of("machine") == Vector2i(18, 12) and Interior.door_cell("smith") == Vector2i(8, 11) and Interior.door_cell("machine") == Vector2i(8, 11), "가게 실내 셋 다 18x12, 문은 아래 가운데")
	# 실내 개편: 방마다 문 안쪽 → 계산대 앞까지 바닥으로 이어지고, NPC 는 계산대 뒤 (손님 칸에서 닿지 않음)
	for rid: String in Interior.ROOMS:
		var rows: Array = Interior.room(rid).rows
		var size := Interior.size_of(rid)
		var npc_cell: Vector2i = Interior.room(rid).npc.cell
		var talk := npc_cell + Vector2i(0, 2)
		var start := Interior.door_cell(rid) + Vector2i(0, -1)
		var seen := {start: true}
		var todo: Array[Vector2i] = [start]
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			for d: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				if not seen.has(c + d) and Interior.is_floor(rid, c + d):
					seen[c + d] = true
					todo.append(c + d)
		var rows_ok := rows.all(func(r: String) -> bool: return r.length() == size.x)
		var behind_ok: bool = not seen.has(npc_cell)
		_check(rows_ok and Interior.is_floor(rid, start) and Interior.is_floor(rid, start + Vector2i(1, 0)) and seen.has(talk) and behind_ok and Interior.is_floor(rid, npc_cell) and not Interior.is_floor(rid, npc_cell + Vector2i(0, 1)),
			"%s 실내: 문 안쪽 → 계산대 앞 %s 로 걸어갈 수 있고 NPC %s 는 계산대 뒤" % [rid, talk, npc_cell])
	# 저녁 불빛 (무드 개편): 낮엔 꺼짐, 밤엔 가로등·가게 창 둘레가 밝아짐
	var lights := get_tree().get_nodes_in_group(NightLight.GROUP)
	var m0 := GameState.minutes
	GameState.set_clock(12 * 60)
	world._on_time_changed(GameState.day, GameState.minutes)
	var day_off := lights.all(func(l: NightLight) -> bool: return not l.enabled)
	GameState.set_clock(21 * 60)
	world._on_time_changed(GameState.day, GameState.minutes)
	var night_on := lights.all(func(l: NightLight) -> bool: return l.enabled and l.energy > 0.5)
	_check(lights.size() >= 30 and day_off and night_on, "저녁 불빛 %d개: 낮엔 꺼지고 밤엔 켜짐" % lights.size())
	GameState.set_clock(m0)
	world._on_time_changed(GameState.day, GameState.minutes)
	var r0 := Interior.view_rect_of("store")
	_check(not r0.intersects(Interior.view_rect_of("smith")) and not Interior.view_rect_of("smith").intersects(Interior.view_rect_of("machine")) and not Interior.view_rect_of("machine").intersects(Mine.view_rect()) and not r0.intersects(SkyIsland.view_rect()), "방끼리·광산·하늘섬과 카메라 범위가 겹치지 않음")


func _test_interiors(world: FarmWorld, hud: HUD) -> void:
	var player := world.player
	var cam := player.camera
	var inv := GameState.inventory
	var saved_inv := inv.to_data()
	var store: ShopBuilding = world.buildings.filter(func(b: Interactable) -> bool: return b is ShopBuilding and b.room_id == "store")[0]
	_check(MapLayout.char_at(Vector2i(64, 11)) == "M" and store.size_tiles == Vector2i(5, 3) and MapLayout.char_at(Vector2i(97, 11)) == "J" and MapLayout.char_at(Vector2i(91, 11)) == "K", "잡화점 5x3 (64, 11) · 대장간 (91, 11) · 기계상점 (97, 11)")

	# 문 [E] → 실내 (걸을 때는 시간이 흐름)
	GameState.set_clock(9 * 60)
	player.global_position = store.interact_point()
	await get_tree().physics_frame
	_check(player._nearest_interactable() == store and store.prompt == "[E] 씨앗상점 들어가기" and store.sign_text == "씨앗상점", "씨앗상점 문 앞 안내·간판 (room_id 는 store 그대로)")
	player._interact()
	var room: Interior = world.interiors["store"]
	var store_rect := Interior.room_rect_of("store")
	var cam_rect := Rect2(cam.limit_left, cam.limit_top, cam.limit_right - cam.limit_left, cam.limit_bottom - cam.limit_top)
	_check(world.area == "store" and world.is_indoors() and cam_rect.encloses(Interior.camera_rect_of("store")) and absf(cam_rect.get_center().x - store_rect.get_center().x) <= 1.0, "씨앗상점 안으로 (카메라: 방 가로 가운데, 위아래 HUD 여백까지 %s / 방 %s)" % [cam_rect, store_rect])
	# 예전 저장(12x9 방)에서 지금은 가구가 된 자리에 서 있었으면 → 문 안쪽에서 시작
	player.global_position = world.cell_center(Interior.origin_of("store") + Vector2i(6, 3))
	world._apply_camera_area()
	_check(player.global_position == Interior.arrive_position("store"), "실내 저장 자리가 가구 위면 문 안쪽으로 옮김")
	_check(not GameState.is_time_paused() and not get_tree().paused, "실내를 걸을 때는 시간이 흐름")
	var t0 := GameState.minutes
	GameState.advance_time(30.0)
	_check(GameState.minutes > t0, "실내에서도 시계가 감")
	for i in 30:
		player.velocity = Vector2(0, -240)
		player.move_and_slide()
	_check(Interior.room_at(player.global_position) == "store", "벽을 넘어 나갈 수 없음")

	# NPC 에게 말 걸기 → 대화 → 사기 / 팔기
	player.global_position = room.npc.interact_point()
	await get_tree().physics_frame
	_check(player._nearest_interactable() == room.npc and room.npc.prompt.contains("말 걸기"), "계산대 앞에서 [E] 말 걸기 안내")
	player._interact()
	_check(hud._dialog.visible and get_tree().paused and GameState.is_time_paused() and hud._dialog._buttons.get_child_count() == 3, "대화 창 (사기·팔기·나가기, 게임·시간 멈춤)")
	hud._dialog.choose("buy")
	var names := hud._shop._buy_list.get_children().map(func(r: Node) -> String: return r.get_child(1).text)
	_check(hud._shop.visible and not hud._dialog.visible and hud._shop._title.text == "씨앗상점 · 사기" and names.any(func(n: String) -> bool: return n.ends_with("씨앗")) and "기본 비료" in names and not "컨베이어" in names, "[사기] → 제철 씨앗·비료 (기계는 없음) %s" % [names])
	hud._close_panels()
	inv.add("carrot", 3, "silver")
	player._interact()
	hud._dialog.choose("sell")
	_check(hud._shop.visible and hud._shop._sell_list.get_parent().visible and not hud._shop._buy_col.visible and hud._shop._sell_list.get_child_count() >= 1, "[팔기] → 작물 팔기")
	hud._close_panels()
	player._interact()
	hud._dialog.choose("")
	_check(not hud._dialog.visible and not get_tree().paused, "[나가기] → 대화 닫힘")

	# 문 칸을 밟으면 밖으로
	player.global_position = world.cell_center(Interior.origin_of("store") + Interior.door_cell("store"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(world.area == "farm" and player.global_position.distance_to(store.interact_point()) < 24.0 and cam.limit_left == 0, "문을 밟으면 잡화점 앞으로 (카메라 농장 범위)")

	# 기계상점: 기계를 판다
	var shop: ShopBuilding = world.buildings.filter(func(b: Interactable) -> bool: return b is ShopBuilding and b.room_id == "machine")[0]
	player.global_position = shop.interact_point()
	await get_tree().physics_frame
	player._interact()
	player.global_position = (world.interiors["machine"] as Interior).npc.interact_point()
	await get_tree().physics_frame
	player._interact()
	hud._dialog.choose("machine")
	var mnames := hud._shop._buy_list.get_children().map(func(r: Node) -> String: return r.get_child(1).text)
	_check(world.area == "machine" and hud._shop._title.text == "기계상점" and "컨베이어" in mnames and not "당근 씨앗" in mnames, "기계상점 [기계 사기] → 컨베이어 %s" % [mnames])
	_check(mnames.size() == 17 and "창고" in mnames and "중급 가공기" in mnames and "펌프" in mnames and not "용광로" in mnames, "기계상점에 기계 17종 (컨베이어 + 공장·자동화 16종, 용광로는 대장간, %d)" % mnames.size())
	var build_names := PlaceableDB.all().filter(func(d: PlaceableDef) -> bool: return d.machine_item() == null and not d.data.has("fixture")).map(func(d: PlaceableDef) -> String: return d.id)
	_check(build_names == ["scarecrow", "shed", "greenhouse", "compost_bin"], "돈으로 바로 짓는 건 허수아비·헛간·온실·퇴비통만 %s" % [build_names])
	hud._close_panels()

	# 실내에서 저장 → 불러오면 실내에서, 하루가 끝나면 집 앞
	world.save_manager.save_game("manual")
	world.save_manager.load_game()
	_check(world.area == "machine" and cam.limit_left == int(world._centered_limits(Interior.camera_rect_of("machine")).position.x), "실내에서 저장·불러오기 → 실내에서 이어서")
	GameState.sleep()
	hud._close_panels()
	_check(world.area == "farm" and player.global_position == world.home_position, "실내에서 하루가 끝나면 집 앞에서 깨어남")
	inv.load_data(saved_inv)
	await get_tree().process_frame


## 기계상점에서 기계 하나를 산다 (돈·재료를 먼저 채워 주고 상점 창의 사기를 그대로 부른다)
func _buy_machine(hud: HUD, item_id: String) -> void:
	var item := ItemDB.get_item(item_id)
	GameState.add_money(item.buy_price)
	for mat_id: String in item.buy_materials:
		GameState.inventory.add(mat_id, int(item.buy_materials[mat_id]))
	hud._shop._buy(item_id, 1)


## 실제 시각으로 ms 만큼 기다린다 (프레임마다 확인)
func _wait_real(ms: int) -> void:
	var until := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


## 합류기가 마지막으로 받은 쪽의 벨트 (names 의 키 중)
func _last_into(m: Router, names: Dictionary) -> Conveyor:
	for b: Conveyor in names:
		if b.cell + m.last_in == m.cell:
			return b
	return names.keys()[0]


## 칸 형식 보관함에서 (id, quality) 가 든 첫 칸 번호 (없으면 -1). quality "" 면 품질은 보지 않는다
func _slot_index(inv: Inventory, item_id: String, quality: String) -> int:
	for i in inv.size():
		var slot: Variant = inv.get_slot(i)
		if slot != null and slot.id == item_id and (quality == "" or slot.get("quality", "") == quality):
			return i
	return -1


func _test_continue_on_start(main: Node) -> void:
	var world: FarmWorld = main.get_node("FarmWorld")
	GameState.add_money(1234)
	world.player.global_position = world.home_position + Vector2(24, 4)
	world.save_manager.save_game("manual")
	var money := GameState.money
	var pos := world.player.global_position
	main.queue_free()
	await get_tree().process_frame

	GameState.new_game()
	SaveManager.load_on_start = true
	var main2: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main2)
	var w2: FarmWorld = main2.get_node("FarmWorld")
	_check(GameState.money == money and w2.player.global_position.distance_to(pos) < 1.0, "게임을 켜면 저장한 곳에서 이어서 (%d G)" % GameState.money)
	await get_tree().process_frame
	main2.queue_free()
	await get_tree().process_frame

	SaveManager.skip_load_once = true
	GameState.new_game()
	var main3: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main3)
	var w3: FarmWorld = main3.get_node("FarmWorld")
	_check(GameState.money == GameState.START_MONEY and GameState.day == 1 and w3.player.global_position == w3.home_position and not SaveManager.skip_load_once, "새 게임을 고르면 저장을 불러오지 않음")
	await get_tree().process_frame
	main3.queue_free()
	SaveManager.load_on_start = false
	await get_tree().process_frame


func _test_title() -> void:
	# 실제 설정(user://settings.cfg, 플레이어가 켠 전체 화면 등)과 상관없이 같은 결과가 나오게
	# 점검용 설정 파일을 비우고 '꺼짐'에서 시작한다. 끝나면 원래 값으로 되돌린다
	var real_fullscreen := Settings.fullscreen
	Settings.path = "user://smoke_test_settings.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.fullscreen = false
	var opened := [0]
	var title: TitleScreen = load("res://scenes/title.tscn").instantiate()
	title.open_main = func() -> void: opened[0] += 1
	add_child(title)
	await get_tree().process_frame
	var has_save := FileAccess.file_exists(SaveManager.slot_path)
	_check(has_save and not title._continue.disabled and title._save_info.text.begins_with("저장: "), "저장이 있으면 [이어하기] (%s)" % title._save_info.text)
	title.continue_game()
	_check(opened[0] == 1 and SaveManager.load_on_start and not SaveManager.skip_load_once, "이어하기 → 저장을 불러오며 게임 시작")
	title.new_game()
	_check(opened[0] == 1 and title._new_game.text.begins_with("정말"), "저장이 있으면 새 게임은 한 번 더 눌러야")
	title.new_game()
	_check(opened[0] == 2 and SaveManager.skip_load_once and GameState.day == 1, "두 번 누르면 새 게임 (저장을 불러오지 않음)")
	SaveManager.skip_load_once = false
	SaveManager.load_on_start = false

	# 설정: 전체 화면 (따로 저장)
	title._show_settings(true)
	_check(title._settings.visible and not title._menu.visible and title._fullscreen.text.ends_with("꺼짐"), "설정 화면 (전체 화면 꺼짐)")
	title._toggle_fullscreen()
	Settings.fullscreen = false
	Settings.load_settings()
	_check(Settings.fullscreen and title._fullscreen.text.ends_with("켜짐"), "전체 화면 켜기 → 설정 파일에 저장")
	title._toggle_fullscreen()
	title._show_settings(false)
	_check(title._menu.visible and not Settings.fullscreen, "돌아가기")

	# 저장이 없으면 이어하기를 못 누르고 새 게임은 바로
	_remove_test_save()
	title.refresh()
	_check(title._continue.disabled and title._save_info.text == "저장된 게임이 없어요", "저장이 없으면 이어하기 비활성")
	title.continue_game()
	title.new_game()
	_check(opened[0] == 3, "저장이 없으면 새 게임 바로 시작")
	SaveManager.skip_load_once = false
	title.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = "user://settings.cfg"
	Settings.fullscreen = real_fullscreen
	await get_tree().process_frame


func _snapshot(world: FarmWorld) -> Dictionary:
	var obstacles: Array = world.obstacles.to_data()
	obstacles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return DataFile.to_vector2i(a.cell) < DataFile.to_vector2i(b.cell))
	return {
		"game": GameState.to_data(),
		"farm": world.farm.to_data(),
		"build": world.build.to_data(),
		"obstacles": obstacles,
		"player_pos": world.player.global_position,
	}


func _write_test_save(text: String) -> void:
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _remove_test_save() -> void:
	for path in [TEST_SAVE, TEST_SAVE + ".bak", TEST_SAVE + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 장애물·밭·시설이 없는 농장 칸
func _free_clear_cell(world: FarmWorld) -> Vector2i:
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		if not world.obstacles.is_blocked(c) and not world.farm.tiles.has(c) and not world.build.is_occupied(c) \
				and MapLayout.char_at(c) == "g":
			return c
	return cells[0]


## def 를 놓을 수 있는 경작지 칸 (avoid 근처는 피한다)
func _free_origin(world: FarmWorld, def: PlaceableDef, avoid: Vector2i) -> Vector2i:
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		if avoid.x >= 0 and absi(c.x - avoid.x) < 4 and absi(c.y - avoid.y) < 4:
			continue
		if world.build.check(def, c).ok:
			return c
	return cells[0]


func _find_char(ch: String) -> Vector2i:
	var size := MapLayout.size()
	for y in size.y:
		for x in size.x:
			if MapLayout.char_at(Vector2i(x, y)) == ch:
				return Vector2i(x, y)
	return Vector2i.ZERO


## 위 칸도 경작지인 경작지 칸 (플레이어가 위에 서서 아래를 보고 일한다)
func _open_farm_cell(farm: FarmGrid) -> Vector2i:
	var cells: Array = farm.farmable_cells.keys()
	cells.sort()
	var obstacles: ObstacleGrid = farm.get_parent().obstacles
	for c: Vector2i in cells:
		var clear := true
		for k in 3:
			var cc: Vector2i = c + Vector2i.UP * k
			if not farm.is_farmable(cc) or obstacles.is_blocked(cc):
				clear = false
		if clear:
			return c
	return cells[0]


func _farm_origin(farm: FarmGrid) -> Vector2i:
	var origin := Vector2i(9999, 9999)
	for c: Vector2i in farm.farmable_cells:
		origin = Vector2i(mini(origin.x, c.x), mini(origin.y, c.y))
	return origin


## 바로 아래가 물인 잔디 칸
func _shore_cell() -> Vector2i:
	var size := MapLayout.size()
	for y in size.y - 1:
		for x in size.x:
			if MapLayout.char_at(Vector2i(x, y)) == "." and MapLayout.char_at(Vector2i(x, y + 1)) == "~":
				return Vector2i(x, y)
	return Vector2i.ZERO


## 경제 기준값 (data/balance/economy_v1.json, tools/apply_economy.py 가 게임 데이터에 써 넣은 값과 같아야 함)
var _econ_cache := {}


func _econ() -> Dictionary:
	if _econ_cache.is_empty():
		_econ_cache = DataFile.load_dict("res://data/balance/economy_v1.json")
	return _econ_cache


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failures += 1
