extends Node
## 자동 점검: 메인 씬을 띄워 핵심 플레이 흐름을 한 바퀴 돌려 본다.
## 실행: Godot --headless --path . res://scenes/tests/smoke_test.tscn

var _failures := 0
## 시작 직후(하루도 지나기 전) 집 근처 장애물 수. 날이 지나면 작은 장애물이 무작위로 다시 자라서 나중에 세면 안 된다.
var _near_home_at_start := -1


const TEST_SAVE := "user://smoke_test_save.json"


func _ready() -> void:
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

	_check(farm.farmable_cells.size() >= 100, "밭 칸 (실제 %d)" % farm.farmable_cells.size())
	_check(world.buildings.size() == 6, "건물 6개 배치 (집·씨앗 상점·작물 판매처·우물·출하함·대장간)")
	_check(world.fences.get_used_cells().is_empty(), "농장에 울타리 없음")
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
	for d in 3:
		# 매일 아침 집에서 깨어나므로 밭으로 다시 간다
		player.global_position = world.cell_center(cell + Vector2i.UP)
		player.facing = Vector2i.DOWN
		GameState.select_slot(1)
		player._use_selected()
		_check(farm.get_tile(cell).watered, "%d일째 물 주기" % (d + 1))
		GameState.sleep()
	_check(WateringCan.water_left(inv, 1) == 9, "물 줄 때마다 1씩 줄어듦 (남은 물 %d)" % WateringCan.water_left(inv, 1))
	_check(farm.get_tile(cell).is_mature(), "3일 물 주고 당근 다 자람")
	_check(GameState.day == 5, "5일차 (실제 %d)" % GameState.day)

	player.global_position = world.cell_center(cell + Vector2i.UP)
	player.facing = Vector2i.DOWN
	GameState.select_slot(0)
	player._use_selected()
	_check(inv.count_of("carrot") == 1, "당근 1개 수확")
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
	hud._shop._buy("potato_seed", 2)
	_check(GameState.money == money + carrot_price - 90 and inv.count_of("potato_seed") == 2, "감자 씨앗 2개 구매 (45G × 2)")
	hud._shop._buy("strawberry_seed", 99)
	_check(inv.count_of("strawberry_seed") == 0, "돈 부족하면 못 삼")

	# 집 앞 상호작용
	var house: Interactable = world.buildings.filter(func(b: Interactable) -> bool: return b is House)[0]
	player.global_position = house.interact_point()
	_check(player._nearest_interactable() == house, "집 앞에서 잠자기 안내")
	house.interact(player)
	_check(GameState.day == 6, "집에서 자면 다음 날")

	# 상점 창 열기/닫기
	Events.shop_requested.emit("buy")
	_check(hud._shop.visible and get_tree().paused, "상점 열면 일시정지")
	_check(hud._shop._buy_list.get_parent().visible and not hud._shop._sell_list.get_parent().visible, "씨앗 상점은 사기만")
	hud._close_panels()
	Events.shop_requested.emit("sell")
	_check(hud._shop._sell_list.get_parent().visible and not hud._shop._buy_list.get_parent().visible, "판매처는 팔기만")
	var stands := world.buildings.filter(func(b: Interactable) -> bool: return b is ShopStall)
	_check(stands.size() == 2 and stands.any(func(b: ShopStall) -> bool: return b.shop_mode == "sell"), "광장에 상점·판매처")
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

	# ---------- 게임을 켤 때 이어하기 / 새 게임
	await _test_continue_on_start(main)

	# ---------- 시작 화면 (이어하기 / 새 게임 / 설정)
	await _test_title()

	_remove_test_save()
	print("SMOKE TEST %s (%d 실패)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures else 0)


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
	_check(bm.try_place(soil) and grid.objects().size() == 1, "갈아 둔 밭 위에 허수아비 설치")
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
	_check(all_cells.size() == world.farm.farmable_cells.size() and all_cells.all(grid.is_buildable_ground), "격자는 지을 수 있는 농장 땅에만 (%d칸)" % all_cells.size())
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
	_check(obs.count() > farm_n * 0.4 and obs.count() < farm_n * 0.8, "시작 농장 장애물 분포 (약 %d%%)" % (obs.count() * 100 / farm_n))
	_check(big > farm_n * 0.1 and big < farm_n * 0.3, "강화 도구가 필요한 땅 약 20%% (실제 %d%%)" % (big * 100 / farm_n))
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

	# 큰 바위: 기본 곡괭이로는 안 됨
	obs.spawn(spot, "big_rock")
	for i in 10:
		obs.try_clear(spot, pick)
	_check(obs.is_blocked(spot) and obs.obstacle_at(spot).hp == 6, "큰 바위는 기본 곡괭이로 못 깸")
	var strong := ItemDef.from_dict("pickaxe", {"kind": "tool", "tool": "pickaxe", "tier": 2})
	for i in 6:
		obs.try_clear(spot, strong)
	_check(not obs.is_blocked(spot), "강화 곡괭이(등급 2)로는 깸")
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
		if ob.def.id in ["big_rock", "big_stump"] and ob.def.tier < 2:
			bad += 1
	_check(bad == 0 and not obs.can_grow_at(tilled), "밭·시설 위에는 안 자람")


func _test_crops_and_quality(world: FarmWorld, hud: HUD) -> void:
	var inv := GameState.inventory
	var farm := world.farm
	var saved := inv.to_data()

	# 작물 데이터 (BUILD_FARM_PLAN §36)
	_check(ItemDB.get_item("turnip_seed") == null and ItemDB.get_item("turnip") == null, "순무 제거됨")
	var cs := ItemDB.get_item("carrot_seed")
	_check(cs.grow_days == 3 and not cs.regrows() and cs.yield_max == 1 and cs.buy_price == 20 and ItemDB.get_item("carrot").sell_price == 35, "당근: 3일 · 1개 · 씨앗 20G · 35G")
	var ps := ItemDB.get_item("potato_seed")
	_check(ps.grow_days == 5 and not ps.regrows() and ps.yield_min == 1 and ps.yield_max == 3 and ps.buy_price == 45 and ItemDB.get_item("potato").sell_price == 30, "감자: 5일 · 1~3개 · 씨앗 45G · 30G")
	var ss := ItemDB.get_item("strawberry_seed")
	_check(ss.grow_days == 7 and ss.regrow_days == 3 and ss.yield_max == 3 and ss.buy_price == 120 and ItemDB.get_item("strawberry").sell_price == 45, "딸기: 7일 · 3일마다 · 1~3개 · 씨앗 120G · 45G")

	# 품질 가격 (§24, §36) + 판매 방식 배율
	for row: Array in [["carrot", [35, 44, 56]], ["potato", [30, 38, 48]], ["strawberry", [45, 56, 72]]]:
		var it := ItemDB.get_item(row[0])
		var got := Quality.ids().map(func(q: String) -> int: return Pricing.quality_price(it, q))
		_check(got == row[1], "%s 브론즈·실버·골드 %s (실제 %s)" % [it.name, row[1], got])
	var carrot := ItemDB.get_item("carrot")
	_check(Pricing.unit_price(carrot, "bronze", Pricing.PLAZA) == 28 and Pricing.unit_price(carrot, "gold", Pricing.PLAZA) == 45, "광장 즉시 판매 = 품질가의 80%")
	_check(Pricing.unit_price(carrot, "silver", Pricing.SHIPPING_BIN) == 44, "출하함 = 품질가의 100%")
	_check(Pricing.unit_price(ItemDB.get_item("wood"), "", Pricing.PLAZA) == 0, "판매가 없는 아이템은 0")

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
	for d in 3:
		farm.water(c)
		GameState.sleep()
	_check(farm.get_tile(c).is_mature(), "3일 뒤 다시 열림")

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
	_check(info.name == "당근" and not info.mature and info.days == 1 and info.need == 3 and info.days_left == 2 and info.watered, "작물 정보: 당근 1/3일, 물 줌, 2일 남음")
	var texts := CropInfoPopup.lines(info).map(func(l: Array) -> String: return l[0])
	_check(texts == ["자라는 중", "1 / 3일", "오늘 물: 줬어요", "수확까지 2일"], "정보 문구 %s" % [texts])
	farm.get_tile(c).watered = false
	texts = CropInfoPopup.lines(farm.crop_info(c)).map(func(l: Array) -> String: return l[0])
	_check(texts.has("오늘 물: 안 줬어요") and texts.has("오늘은 자라지 않아요"), "물 안 주면 '오늘은 자라지 않아요'")
	farm.get_tile(c).days_grown = 3
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
	_check(inv.count_of("carrot") == carrots + 1 and not farm.get_tile(c).has_crop(), "다 자란 작물은 괭이로 쳐도 수확이 먼저")
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
	var on_sales := func(rep: Dictionary) -> void: calls.append(["sales", GameState.day])
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
	var expect := 2 * 44 + 2 * 48
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
	hud._shop._sell("carrot", 1, "silver")
	_check(GameState.money == money + 35 and int(GameState.today_sales.get(Pricing.PLAZA, 0)) >= 35, "광장 즉시 판매는 80%% (실버 당근 35 G), 오늘 장부에 기록")

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
	var plan := {"none": [80, 18, 2], "basic": [60, 35, 5], "advanced": [35, 50, 15], "premium": [15, 45, 40]}
	var chances: Dictionary = DataFile.load_dict(Quality.DATA_PATH).get("harvest_chances", {})
	var same := true
	for t: String in plan:
		var row: Dictionary = chances.get(t, {})
		same = same and [int(row.get("bronze", -1)), int(row.get("silver", -1)), int(row.get("gold", -1))] == plan[t]
	_check(same, "품질 확률표 = 기획서 §25 (무비료·기본·고급·최상급)")
	_check(ids.map(func(id: String) -> String: return ItemDB.get_item(id).quality_table) == ["basic", "advanced", "premium"], "비료 → 확률표 연결")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var counts := {"bronze": 0, "silver": 0, "gold": 0}
	for i in 4000:
		counts[Quality.roll(rng, "premium")] += 1
	_check(absf(counts.gold / 4000.0 - 0.40) < 0.03 and absf(counts.bronze / 4000.0 - 0.15) < 0.03, "최상급 비료 품질 분포 %s" % counts)

	# 뿌리기 규칙: 갈아 둔 빈 밭에, 심기 전에만
	var c := _free_clear_cell(world)
	var basic := ItemDB.get_item("basic_fertilizer")
	var premium := ItemDB.get_item("premium_fertilizer")
	var carrot_seed := ItemDB.get_item("carrot_seed")
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
	var strawberry := ItemDB.get_item("strawberry_seed")
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
	var smith_cell := Vector2i(floori(smith.global_position.x / Art.TILE), floori(smith.global_position.y / Art.TILE) - 2)
	_check(smith_cell == _find_char("K") and smith_cell.x > _find_char("#").x, "대장간은 메인 광장 (맵의 K, 3x2)")
	player.global_position = smith.interact_point()
	_check(player._nearest_interactable() == smith, "대장간 앞에서 [E] 안내")
	smith.interact(player)
	_check(hud._smith.visible and GameState.is_time_paused() and get_tree().paused, "대장간 창을 열면 시간 정지")

	# 데이터: 네 도구 모두 강화 경로 (돈 + 자원)
	var paths_ok := true
	for id: String in ["hoe", "watering_can", "axe", "pickaxe"]:
		var item := ItemDB.get_item(id)
		var next := ToolUpgrade.next_of(item)
		paths_ok = paths_ok and next != null and next.tier == item.tier + 1 and next.tool_type == item.tool_type 				and ToolUpgrade.price_of(item) > 0 and not ToolUpgrade.materials_of(item).is_empty()
	_check(paths_ok, "괭이·물뿌리개·도끼·곡괭이 강화 경로 (돈 + 자원, items.json)")
	_check(ItemDB.get_item("pickaxe_2").tier >= ObstacleDB.get_def("big_rock").tier and ItemDB.get_item("axe_2").tier >= ObstacleDB.get_def("big_stump").tier 			and ItemDB.get_item("pickaxe").tier < ObstacleDB.get_def("big_rock").tier, "강한 장애물(약 20%)은 강화 도끼·곡괭이가 있어야 치움")

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
	inv.add("stone", 99)
	inv.add("wood", 99)
	hud._smith.refresh()
	_check(hud._smith._list.get_child_count() == 4, "대장간 창에 도구 4개")

	# 괭이 강화: 즉시, 같은 칸
	var hoe := ItemDB.get_item("hoe")
	var price := ToolUpgrade.price_of(hoe)
	var mats := ToolUpgrade.materials_of(hoe)
	_check(ToolUpgrade.apply(inv, hoe_slot) and inv.item_at(hoe_slot).id == "hoe_2", "강화하면 바로 강화 괭이 (같은 칸)")
	_check(GameState.money == 10000 - price and inv.count_of("stone") == 99 - int(mats.stone) and inv.count_of("wood") == 99 - int(mats.wood), "강화 비용: %d G + 돌 %d + 나무 %d" % [price, int(mats.stone), int(mats.wood)])
	_check(ToolUpgrade.next_of(inv.item_at(hoe_slot)) == null and not ToolUpgrade.check(inv, hoe_slot).ok, "최고 단계는 더 강화 안 됨")

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
	_check(farm.use_item(start, inv.item_at(hoe_slot), Vector2i.DOWN) and farm.tiles.has(start) and farm.tiles.has(start + Vector2i.DOWN) and farm.tiles.has(start + Vector2i.DOWN * 2), "강화 괭이는 바라보는 방향으로 3칸을 한 번에 갊")
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
	await get_tree().process_frame


func _test_seasonal_crops(world: FarmWorld, hud: HUD) -> void:
	var farm := world.farm
	var start_day := GameState.day
	# 기획서 수치: [성장, 재수확, 수확량 최소, 최대, 씨앗가, 판매가(브론즈), 계절]
	var plan := {
		"wheat": [4, 0, 1, 1, 25, 35, ["spring", "summer"]],
		"tomato": [6, 3, 1, 3, 90, 38, ["summer"]],
		"blueberry": [8, 4, 2, 4, 140, 32, ["summer"]],
		"corn": [9, 4, 1, 2, 110, 60, ["summer", "autumn"]],
		"watermelon": [10, 5, 1, 1, 120, 110, ["summer"]],
		"sweet_potato": [5, 0, 1, 3, 65, 50, ["autumn"]],
		"eggplant": [6, 3, 1, 2, 100, 60, ["autumn"]],
		"pumpkin": [10, 0, 1, 1, 140, 300, ["autumn"]],
		"radish": [4, 0, 1, 1, 35, 60, ["autumn"]],
	}
	var bad := []
	for id: String in plan:
		var row: Array = plan[id]
		var sd := ItemDB.get_item(id + "_seed")
		var crop := ItemDB.get_item(id)
		if sd == null or crop == null or sd.grows != id or [sd.grow_days, sd.regrow_days, sd.yield_min, sd.yield_max, sd.buy_price, crop.sell_price] != row.slice(0, 6) or sd.seasons != row[6]:
			bad.append(id)
	_check(bad.is_empty(), "여름·가을 작물 9종 = 기획서 §36~§38 (성장·재수확·수확량·씨앗가·판매가·계절) %s" % [bad])
	var q_ok := true
	for row: Array in [["tomato", [38, 48, 61]], ["blueberry", [32, 40, 51]], ["watermelon", [110, 138, 176]], ["pumpkin", [300, 375, 480]]]:
		var it := ItemDB.get_item(row[0])
		q_ok = q_ok and Quality.ids().map(func(q: String) -> int: return Pricing.quality_price(it, q)) == row[1]
	_check(q_ok, "품질 가격 = 기획서 (토마토 38/48/61, 호박 300/375/480 ...)")
	_check(ItemDB.get_item("golden_pumpkin") == null and ItemDB.get_item("golden_pumpkin_seed") == null, "황금호박 같은 특수작물은 아직 없음")
	var rows := {}
	var art_ok := true
	for id: String in plan:
		var sd := ItemDB.get_item(id + "_seed")
		art_ok = art_ok and not rows.has(sd.crop_row) and (sd.crop_row + 1) * Art.TILE <= Art.CROPS.get_height() 				and (ItemDB.get_item(id).icon + 1) * Art.TILE <= Art.ITEMS.get_width()
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
	_check(shop_seeds.call(1) == ["carrot", "potato", "strawberry", "wheat"], "봄 상점 씨앗 %s" % [shop_seeds.call(1)])
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

	# 토마토: 6일 뒤 열리고 3일마다 다시
	farm.get_tile(a).days_grown = 6
	var got := farm.harvest(a)
	_check(got.get("id") == "tomato" and got.count >= 1 and got.count <= 3 and farm.get_tile(a).regrowing, "토마토 수확 (%d개), 포기 남음" % got.get("count", 0))
	farm.get_tile(a).days_grown = 3
	_check(farm.get_tile(a).is_mature(), "3일 뒤 다시 열림")

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
	var need := ["성장 6일", "다시 열림: 3일마다", "수확량 1~3개", "계절: 여름", "씨앗 가격 90 G", "토마토 기본 판매가 38 G"]
	_check(need.all(func(t: String) -> bool: return t in texts), "씨앗 툴팁: 성장·다시 열림·수확량·계절·씨앗 가격·판매가 %s" % [texts])
	var can_lines := ItemTooltip.lines(ItemDB.get_item("watering_can"), "", 5).map(func(l: Array) -> String: return l[0])
	_check("등급 1" in can_lines and "물 5 / 12" in can_lines and "대장간에서 강화할 수 있어요" in can_lines, "도구 툴팁: 등급·물·강화 가능")
	var hoe2_lines := ItemTooltip.lines(ItemDB.get_item("hoe_2")).map(func(l: Array) -> String: return l[0])
	_check("등급 2" in hoe2_lines and "한 번에 3칸 갈기" in hoe2_lines, "강화 도구 툴팁: 등급·범위")
	var crop_lines := ItemTooltip.lines(ItemDB.get_item("potato"), "gold").map(func(l: Array) -> String: return l[0])
	_check("기준가 48 G" in crop_lines and "출하함 48 G · 광장 38 G" in crop_lines, "작물 툴팁: 품질 기준가·판매 방식별 가격")
	var fert_lines := ItemTooltip.lines(ItemDB.get_item("premium_fertilizer")).map(func(l: Array) -> String: return l[0])
	_check("수확 품질: 브론즈 15% · 실버 45% · 골드 40%" in fert_lines, "비료 툴팁: 품질 확률")
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
	_check(def != null and def.size == Vector2i(4, 4) and def.cost_text() == "1500 G + 나무 80 + 돌 40", "창고 정의 (4x4, %s)" % (def.cost_text() if def else ""))

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
	inv.add("wood", 80)
	inv.add("stone", 40)
	GameState.add_money(2000)
	bm.start_place("warehouse")
	_check(bm.try_place(origin) and inv.count_of("wood") == 0 and inv.count_of("stone") == 0, "창고 짓기 (나무 80 + 돌 40 사용)")
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
	var mats_back := inv.count_of("wood") == 80 + 60 + 120 and inv.count_of("stone") == 40 + 60 + 120
	_check(inv.count_of("tomato", "gold") == tomato_before + 4 and mats_back and GameState.money == money + 1500 + 1000 + 2500, "철거하면 안의 물건 + 건설비 + 증축 비용 모두 돌려받음")
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
	_check(def != null and def.size == Vector2i(2, 2) and def.cost_text() == "800 G + 나무 50 + 돌 30", "수동 가공기 정의 (2x2, %s)" % (def.cost_text() if def else ""))

	# 레시피 데이터 (§73): 지금 있는 작물로 만들 수 있는 20개, 기초 6개만 처음부터 앎
	var recipes := RecipeDB.all()
	var known := recipes.filter(func(r: Dictionary) -> bool: return RecipeDB.is_known(r.id)).map(func(r: Dictionary) -> String: return r.id)
	_check(recipes.size() == 20, "레시피 20개 (%d)" % recipes.size())
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
	inv.add("wood", 50)
	inv.add("stone", 30)
	GameState.add_money(1000)
	bm.start_place("manual_processor")
	_check(bm.try_place(origin) and inv.count_of("wood") == 0 and inv.count_of("stone") == 0, "수동 가공기 짓기 (나무 50 + 돌 30 사용)")
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
	_check(panel._list.get_child_count() == 20 and panel.selected == "flour", "창에 레시피 20개, 첫 레시피 선택")
	hud._close_panels()

	# 모르는 레시피는 못 씀 → 배우면 영구 (저장됨)
	inv.add("strawberry", 3)
	inv.add("sugar", 1)
	_check(pr.recipe_problem("strawberry_jam") != "" and pr.start(inv, "strawberry_jam", 1) == 0, "안 배운 레시피(딸기잼)는 못 돌림")
	_check(RecipeDB.learn("strawberry_jam") and RecipeDB.is_known("strawberry_jam") and pr.recipe_problem("strawberry_jam") == "", "레시피 배우기 (영구 해금)")
	world.save_manager.save_game("manual")
	GameState.unlocks.erase("recipe:strawberry_jam")
	world.save_manager.load_game()
	pr = grid.object_at(origin) as Processor
	_check(RecipeDB.is_known("strawberry_jam"), "배운 레시피는 저장·불러오기 후에도 앎")
	GameState.unlocks.erase("recipe:strawberry_jam")
	inv.remove("strawberry", 3)
	inv.remove("sugar", 1)

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
	_check(inv.count_of("tomato") == 6 and inv.count_of("wood") == 50 and inv.count_of("stone") == 30 and GameState.money == money + 800, "철거하면 남은 재료(토마토 6) + 건설비 돌려받음")
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
	_check(gen_def != null and gen_def.size == Vector2i(2, 2) and gen_def.cost_text() == "1200 G + 나무 40 + 돌 60", "소형 발전기 정의 (2x2)")
	_check(ep_def != null and ep_def.size == Vector2i(3, 3) and ep_def.cost_text() == "2500 G + 나무 60 + 돌 80", "전기 가공기 정의 (3x3, %s)" % (ep_def.cost_text() if ep_def else ""))
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

	# 발전기 짓기 (돈 + 재료)
	inv.remove("wood", inv.count_of("wood"))
	inv.remove("stone", inv.count_of("stone"))
	inv.add("wood", 40)
	inv.add("stone", 60)
	GameState.add_money(1200)
	bm.start_place("small_generator")
	_check(bm.try_place(origin + Vector2i(7, 0)) and inv.count_of("stone") == 0, "소형 발전기 짓기 (나무 40 + 돌 60)")
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
	_check(bm.try_remove(origin + Vector2i(7, 0)) and inv.count_of("wood") == 40 + fuel_left, "발전기 철거 → 남은 연료 + 건설 재료 돌려받음")
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
	Settings.path = "user://smoke_test_settings.cfg"
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
	Settings.path = "user://settings.cfg"
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


func _check(ok: bool, label: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		_failures += 1
