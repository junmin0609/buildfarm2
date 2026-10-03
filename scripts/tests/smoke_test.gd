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
	_check(world.buildings.size() == 5, "건물 5개 배치 (집·씨앗 상점·작물 판매처·우물·출하함)")
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

	# ---------- 게임을 켤 때 이어하기 / 새 게임
	await _test_continue_on_start(main)

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
	var new_c: Vector2i = cells[2]
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
