extends Node
## 자동 점검: 메인 씬을 띄워 핵심 플레이 흐름을 한 바퀴 돌려 본다.
## 실행: Godot --headless --path . res://scenes/tests/smoke_test.tscn

var _failures := 0


func _ready() -> void:
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
	_check(world.buildings.size() == 3, "건물 3개 배치 (집·씨앗 상점·작물 판매처)")
	_check(world.fences.get_used_cells().is_empty(), "농장에 울타리 없음")
	_check(world.objects.get_children().filter(func(n: Node) -> bool: return n is Prop).size() > 100, "나무·바위 소품 배치")

	# 밭 위쪽 칸에 서서 아래를 보고 작업
	var cell := _open_farm_cell(farm)
	player.global_position = world.cell_center(cell + Vector2i.UP)
	player.facing = Vector2i.DOWN
	_check(player.target_cell() == cell, "앞 칸을 목표로 삼음 (실제 %s)" % player.target_cell())

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

	_check(WateringCan.water_left(inv, 1) == 12, "물뿌리개는 가득 찬 채로 시작 (12)")
	for d in 3:
		GameState.select_slot(1)
		player._use_selected()
		_check(farm.get_tile(cell).watered, "%d일째 물 주기" % (d + 1))
		GameState.sleep()
	_check(WateringCan.water_left(inv, 1) == 9, "물 줄 때마다 1씩 줄어듦 (남은 물 %d)" % WateringCan.water_left(inv, 1))
	_check(farm.get_tile(cell).is_mature(), "3일 물 주고 당근 다 자람")
	_check(GameState.day == 5, "5일차 (실제 %d)" % GameState.day)

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

	# 맵 밖으로는 못 나감
	player.global_position = world.cell_center(Vector2i(1, 1))
	for i in 60:
		player.velocity = Vector2(-240, -240)
		player.move_and_slide()
	_check(player.global_position.x >= 0 and player.global_position.y >= 0, "맵 밖으로 못 나감")

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
	var home := world.world_to_cell(world.cell_center(_find_char("@")))
	var near := 0
	for ob: Obstacle in obs.all():
		if Vector2(ob.cell).distance_to(Vector2(home)) < 6:
			near += 1
	_check(near == 0, "집 근처는 바로 쓸 수 있는 땅")
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
	_check(WateringCan.use(world, _find_char("~"), inv, can_slot) and WateringCan.water_left(inv, can_slot) == 12, "물가에서 가득 채움")
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
