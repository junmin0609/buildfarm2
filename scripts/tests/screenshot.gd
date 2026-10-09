extends Node

## 화면 확인용: 메인 씬을 띄우고 밭을 조금 가꾼 뒤 스크린샷 두 장을 user:// 에 저장한다.

func _ready() -> void:
	# 새 게임으로 찍고, 진짜 저장 파일은 건드리지 않는다
	SaveManager.load_on_start = false
	SaveManager.slot_path = "user://screenshot_save.json"
	Weather.forced = "sunny"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var world: FarmWorld = main.get_node("FarmWorld")
	var farm := world.farm
	var origin := Vector2i(11, 14)  # 집 앞 남동쪽 (예전 흙밭 자리, 흙밭은 사용자 요청으로 없앰)
	for y in range(0, 12):
		for x in range(0, 14):
			world.obstacles.remove(origin + Vector2i(x, y))
	for x in range(10, 16):
		for y in range(4, 8):
			var cell := origin + Vector2i(x - 6, y - 2)
			farm.till(cell)
			if y == 4:
				farm.fertilize(cell, ItemDB.get_item(["basic_fertilizer", "advanced_fertilizer", "premium_fertilizer"][x % 3]))
			if y > 4:
				farm.plant(cell, ItemDB.get_item(["carrot_seed", "potato_seed", "strawberry_seed"][x % 3]))
				farm.get_tile(cell).days_grown = (x - 10) * 2
			if (x + y) % 2 == 0:
				farm.water(cell)
	world.player.global_position = world.cell_center(origin + Vector2i(7, 6))
	world.player.facing = Vector2i.UP
	GameState.inventory.add("carrot", 7)
	GameState.inventory.add("potato", 3, "silver")
	GameState.inventory.add("potato", 2, "gold")
	GameState.inventory.set_slot_value(1, "water", 7)
	GameState.inventory.add("strawberry", 2)
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_farm.png"))
	# 작물 위에 마우스를 올려 작물 정보 창 확인
	Input.warp_mouse(get_viewport().get_canvas_transform() * world.cell_center(origin + Vector2i(5, 4)))
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_crop_info.png"))
	# 비·눈 오는 날 화면
	GameState.set_weather("rain")
	farm.water_outdoor()
	await get_tree().create_timer(1.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_rain.png"))
	GameState.set_weather("snow")
	await get_tree().create_timer(1.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_snow.png"))
	GameState.set_weather("sunny")
	world.player.global_position = world.buildings[0].interact_point() + Vector2(-40, 30)
	world.player.facing = Vector2i.LEFT
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_town.png"))
	world.player.global_position = world.buildings[0].interact_point()
	world.player.facing = Vector2i.UP
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_door.png"))
	var well: Interactable = world.buildings.filter(func(b: Interactable) -> bool: return b is Well)[0]
	world.player.global_position = well.interact_point()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_well.png"))
	world.player.global_position = world.buildings[1].interact_point() + Vector2(40, 30)
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_market.png"))
	GameState.set_clock(19 * 60)
	await get_tree().create_timer(1.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_evening.png"))
	GameState.set_clock(10 * 60)
	await get_tree().create_timer(1.8).timeout
	Events.shop_requested.emit("buy")
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_shop.png"))
	# 여름 상점 (씨앗 5종 + 비료 3종 + 특별 상품) 이 화면에 들어가는지
	main.get_node("HUD")._close_panels()
	var spring_day := GameState.day
	GameState.day = 29
	Events.shop_requested.emit("buy")
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_shop_summer.png"))
	GameState.day = spring_day
	main.get_node("HUD")._close_panels()
	Events.shop_requested.emit("sell")
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_sell.png"))
	main.get_node("HUD")._close_panels()
	main.get_node("HUD")._inventory.open()
	get_tree().paused = true
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_inv.png"))
	# 아이템 툴팁 (씨앗 칸에 마우스)
	var seed_slot: Control = main.get_node("HUD")._inventory._slots[2]
	Input.warp_mouse(seed_slot.get_global_rect().get_center())
	Events.item_hover_changed.emit(seed_slot)
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_tooltip.png"))
	Events.item_hover_changed.emit(null)
	main.get_node("HUD")._close_panels()
	main.get_node("HUD").open_menu()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_menu.png"))
	main.get_node("HUD")._close_panels()
	# 건설: 창, 설치 가능/불가 미리보기
	get_tree().paused = false
	var hud = main.get_node("HUD")
	hud._close_panels()
	GameState.set_clock(10 * 60)
	world.build.place(PlaceableDB.get_def("shed"), origin + Vector2i(-1, 7))
	world.build.place(PlaceableDB.get_def("scarecrow"), origin + Vector2i(11, 3))
	world.player.global_position = world.cell_center(origin + Vector2i(6, 8))
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	hud._build.open()
	get_tree().paused = true
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_build_panel.png"))
	hud._close_panels()
	Events.build_requested.emit("place", "shed")
	var bm: BuildMode = world.build_mode
	bm._use_mouse = false
	world.player.facing = Vector2i.RIGHT
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_build_ok.png"))
	world.player.global_position = world.cell_center(origin + Vector2i(6, 6))
	world.player.facing = Vector2i.UP
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_build_bad.png"))
	bm.stop()

	# 대장간: 광장 위치·강화 창
	var smith: Interactable = world.buildings.filter(func(b: Interactable) -> bool: return b is Blacksmith)[0]
	world.player.global_position = smith.interact_point() + Vector2(0, 6)
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	GameState.inventory.add("stone", 20)
	GameState.inventory.add("wood", 12)
	GameState.add_money(500)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_smith.png"))
	hud.open_blacksmith()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_smith_panel.png"))
	hud._close_panels()

	# 집 옮기기 (사용자 결정): 집을 집어 든 모습 → 농장 땅으로 옮긴 뒤
	var house_fx: Placeable = world.build.object_at(world.fixture_buildings["house"].position / FarmWorld.TILE - Vector2(0, 1))
	var home_cell := house_fx.cell
	var to := Vector2i(-1, -1)  # 집 4x3 + 앞 한 줄이 모두 농장 땅인 첫 자리 (작물·시설 없음)
	var farm_cells: Array = world.farm.farmable_cells.keys()
	farm_cells.sort()
	for c: Vector2i in farm_cells:
		var ok := true
		for y in 4:
			for x in 4:
				var fc: Vector2i = c + Vector2i(x, y)
				if not world.farm.farmable_cells.has(fc) or world.build.is_occupied(fc) or (world.farm.get_tile(fc) != null and world.farm.get_tile(fc).has_crop()):
					ok = false
		if ok:
			to = c
			break
	for y in 5:
		for x in 4:
			world.obstacles.remove(to + Vector2i(x, y))
			world.farm.untill(to + Vector2i(x, y))
	world.player.global_position = world.cell_center(to + Vector2i(1, 3))  # 바라보는 앞 칸 기준으로 집 미리보기가 to 에
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	world.build_mode.start(BuildMode.Mode.MOVE)
	world.build_mode.pick(home_cell)
	await get_tree().create_timer(0.3).timeout
	world.build_mode._use_mouse = false
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_house_moving.png"))
	world.build_mode.try_drop(to)
	world.build_mode.stop()
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_house_moved.png"))
	world.build.move(house_fx, home_cell)

	# 가게 실내 (사용자 요청): 광장의 잡화점·기계상점 → 잡화점 안 + 대화 창 → 대장간 안 → 기계상점 안
	world.player.global_position = world.cell_center(Vector2i(60, 16))
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_plaza_shops.png"))
	# 넓힌 광장: 분수 광장·공방 거리·정류장 마당, 그리고 줌을 당긴 전체 모습
	for spot: Array in [[Vector2i(86, 33), "fountain"], [Vector2i(95, 18), "workshop"], [Vector2i(108, 50), "station"], [Vector2i(66, 17), "store"], [Vector2i(86, 49), "creek"], [Vector2i(56, 18), "entrance"]]:
		world.player.global_position = world.cell_center(spot[0])
		world.player.camera.reset_smoothing()
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_plaza_%s.png" % spot[1]))
	var zoom_before := world.player.camera.zoom
	world.player.camera.zoom = zoom_before * 0.3
	world.player.global_position = world.cell_center(Vector2i(86, 32))
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_plaza_overview.png"))
	world.player.camera.zoom = zoom_before
	# 저녁 불빛 (무드 개편): 밤 9시 광장 (가게 거리·분수)
	var clock_before := GameState.minutes
	GameState.set_clock(21 * 60)
	world._on_time_changed(GameState.day, GameState.minutes)
	for spot: Array in [[Vector2i(82, 19), "night_shops", 0.55], [Vector2i(86, 33), "night_fountain", 0.75]]:
		world.player.camera.zoom = zoom_before * float(spot[2])
		world.player.global_position = world.cell_center(spot[0])
		world.player.camera.reset_smoothing()
		await get_tree().create_timer(2.0).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_%s.png" % spot[1]))
	world.player.camera.zoom = zoom_before
	GameState.set_clock(clock_before)
	world._on_time_changed(GameState.day, GameState.minutes)
	await get_tree().create_timer(1.6).timeout
	world.enter_interior("store")
	world.player.global_position = (world.interiors["store"] as Interior).npc.interact_point()
	world.player.facing = Vector2i.UP
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_store_inside.png"))
	hud.open_dialog((world.interiors["store"] as Interior).npc)
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_store_dialog.png"))
	hud._close_panels()
	for room_id in ["smith", "machine"]:
		world.enter_interior(room_id)
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_%s_inside.png" % room_id))
	# 기계상점 [기계 사기] 창 → 가방에 기계를 산 뒤 건설 창
	hud._open_shop("machine")
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_machine_shop.png"))
	hud._close_panels()
	GameState.inventory.add("sprinkler_1", 2)
	GameState.inventory.add("warehouse", 1)
	hud.open_build_panel()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_build_machines.png"))
	hud._close_panels()
	world.exit_interior()

	# 하늘시장 (§84~§90): 부서진 정류장·복구 창 → 복구한 정류장 → 하늘섬 → 가판대 창
	var station: SkyStation = world.buildings.filter(func(b: Interactable) -> bool: return b is SkyStation)[0]
	world.player.global_position = station.interact_point() + Vector2(0, 10)
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_sky_station_broken.png"))
	GameState.inventory.add("flour", 4)
	hud.open_sky_station()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_sky_station_panel.png"))
	hud._close_panels()
	GameState.unlocks[SkyMarket.UNLOCK] = true
	Events.sky_station_restored.emit()
	await get_tree().create_timer(0.3).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_sky_station.png"))
	SkyMarket.rng.seed = 3
	GameState.sky_market = SkyMarket.roll(GameState.day)
	GameState.sky_market.event = "sky_food_festival"
	world.travel("sky")
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_sky_island.png"))
	for entry in [["strawberry", 6, "gold"], ["tomato", 4, "silver"], ["bread", 2, ""], ["flour", 3, ""]]:
		GameState.inventory.add(entry[0], entry[1], entry[2])
	hud.open_sky_market()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_sky_market.png"))
	hud._close_panels()
	world.travel("home")
	GameState.unlocks.erase(SkyMarket.UNLOCK)
	Events.sky_station_restored.emit()
	GameState.set_clock(10 * 60)

	# 레시피 상점 (셰프 §71): 광장 위치·창 (딸기·설탕·블루베리를 얻어 본 상태, 딸기잼은 배움)
	var chef: Interactable = world.buildings.filter(func(b: Interactable) -> bool: return b is RecipeShop)[0]
	world.player.global_position = chef.interact_point() + Vector2(0, 6)
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	for id in ["sugar", "blueberry", "tomato_puree", "tomato_sauce"]:
		GameState.discover(id)
	RecipeDB.learn("strawberry_jam")
	GameState.add_money(3000)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_recipe_shop.png"))
	hud.open_recipe_shop()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_recipe_panel.png"))
	hud._close_panels()

	# 출하함: 위치·창, 하루가 끝난 뒤 판매 수익 요약
	var bin: ShippingBin = world.shipping_bin
	world.player.global_position = bin.interact_point()
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	bin.deposit(GameState.inventory, "carrot", "", 4)
	bin.deposit(GameState.inventory, "potato", "gold", 2)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_bin.png"))
	hud.open_shipping_bin(bin)
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_bin_panel.png"))
	hud._close_panels()
	GameState.record_sale(Pricing.PLAZA, 120)
	GameState.sleep()
	await get_tree().create_timer(1.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_sales_summary.png"))
	hud._close_panels()

	# 온실: 겉모습, 안에서 자라는 작물, 플레이어가 벽 앞뒤로 가려지는지, 겨울 상점
	var gh_def := PlaceableDB.get_def("greenhouse")
	var gh_at := Vector2i(6, 24)
	for fc in Placeable.footprint_of(gh_def, gh_at):
		world.obstacles.remove(fc)
		var tile := farm.get_tile(fc)
		if tile:
			tile.clear_crop()
			farm.untill(fc)
	world.player.global_position = world.cell_center(gh_at + Vector2i(3, 9))
	var gh := world.build.place(gh_def, gh_at) as Greenhouse
	var seeds := ["spinach_seed", "broccoli_seed", "sugar_beet_seed", "carrot_seed", "tomato_seed", "pumpkin_seed"]
	for c in gh.indoor_cells():
		var rel := c - gh_at
		farm.till(c)
		if rel.y <= 3:
			farm.plant(c, ItemDB.get_item(seeds[rel.x - 1]))
			farm.get_tile(c).days_grown = (rel.y - 1) * 4 + 2 * (rel.x % 2)
		if (rel.x + rel.y) % 2 == 0:
			farm.water(c)
	world.player.global_position = world.cell_center(gh_at + Vector2i(2, 1)) + Vector2(0, 2)
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_greenhouse.png"))
	world.player.global_position = world.cell_center(gh_at + Vector2i(1, 5)) + Vector2(0, 2)
	world.player.facing = Vector2i.DOWN
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_greenhouse_front.png"))
	var day_before := GameState.day
	GameState.day = 85
	Events.shop_requested.emit("buy")
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_shop_winter.png"))
	hud._close_panels()
	GameState.day = day_before
	hud._build.open()
	get_tree().paused = true
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_build_panel.png"))
	hud._close_panels()

	# 퇴비통: 결과물 아이콘, 창
	var cb_at := gh_at + Vector2i(9, 2)
	for fc in [cb_at, cb_at + Vector2i(1, 0), cb_at + Vector2i(0, 1), cb_at + Vector2i(1, 1)]:
		world.obstacles.remove(fc)
	var cb := world.build.place(PlaceableDB.get_def("compost_bin"), cb_at) as CompostBin
	GameState.inventory.add("fiber", 14)
	GameState.inventory.add("carrot", 2)
	cb.deposit(GameState.inventory, "fiber", "", 10)
	cb.deposit(GameState.inventory, "fiber", "", 4)
	cb.batch_days = 2
	cb.output = 2
	cb._changed()
	world.player.global_position = cb.interact_point() + Vector2(0, 4)
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_compost.png"))
	hud.open_compost_bin(cb)
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_compost_panel.png"))
	hud._close_panels()

	# 창고: 바깥 모습, 창 (지정 아이템 필터 + 물건 몇 개)
	var wh_def := PlaceableDB.get_def("warehouse")
	var wh_at := Vector2i(-1, -1)
	for dy in range(-2, 6):
		for dx in range(3, 14):
			var c := cb_at + Vector2i(dx, dy)
			var free := true
			for y in 5:
				for x in 4:
					var fc := c + Vector2i(x, y)
					free = free and world.build.is_buildable_ground(fc) and not world.build.is_occupied(fc) and not world.farm.tiles.has(fc)
			if free and wh_at.x < 0:
				wh_at = c
	for y in 5:
		for x in 4:
			world.obstacles.remove(wh_at + Vector2i(x, y))
	await get_tree().process_frame
	var wh := world.build.place(wh_def, wh_at) as Warehouse
	wh.storage.add("carrot", 24, "silver")
	wh.storage.add("potato", 40)
	wh.storage.add("strawberry", 6, "gold")
	wh.storage.add("wood", 99)
	wh.set_filter_mode("items")
	for id: String in ["carrot", "potato", "strawberry"]:
		wh.add_filter_item(id)
	GameState.inventory.add("stone", 20)
	world.player.global_position = wh.interact_point() + Vector2(0, 4)
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_warehouse.png"))
	hud.open_warehouse(wh)
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_warehouse_panel.png"))
	hud._close_panels()

	# 수동 가공기: 밀가루 3회 중 1회 완성, 창
	var pr_at := wh_at + Vector2i(5, 1)
	for y in 3:
		for x in 2:
			world.obstacles.remove(pr_at + Vector2i(x, y))
	await get_tree().process_frame
	var pr := world.build.place(PlaceableDB.get_def("manual_processor"), pr_at) as Processor
	if pr:
		GameState.inventory.add("wheat", 4, "silver")
		GameState.inventory.add("wheat", 4, "gold")
		pr.start(GameState.inventory, "flour", 3)
		pr.advance(80.0)
		world.player.global_position = pr.interact_point() + Vector2(0, 4)
		world.player.facing = Vector2i.UP
		world.player.camera.reset_smoothing()
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_processor.png"))
		hud.open_processor(pr)
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_processor_panel.png"))
		hud._close_panels()

	# 전기 가공기 + 발전기: 창고 왼쪽에 맞닿게 (자리가 없으면 건너뜀)
	var ep_def := PlaceableDB.get_def("electric_processor")
	for off: Vector2i in [Vector2i(-3, 0), Vector2i(-3, 1), Vector2i(0, 4)]:
		var at := wh_at + off
		var gen_at := at + (Vector2i(-2, 0) if off.x < 0 else Vector2i(3, 0))
		var free := true
		for fc in Placeable.footprint_of(ep_def, at) + Placeable.footprint_of(PlaceableDB.get_def("small_generator"), gen_at):
			free = free and world.build.is_buildable_ground(fc) and not world.build.is_occupied(fc) and not world.farm.tiles.has(fc)
		if not free:
			continue
		for fc in Placeable.footprint_of(ep_def, at) + Placeable.footprint_of(PlaceableDB.get_def("small_generator"), gen_at):
			world.obstacles.remove(fc)
		for x in 3:
			world.obstacles.remove(at + Vector2i(x, 3))
		await get_tree().process_frame
		var ep := world.build.place(ep_def, at) as Processor
		var gen := world.build.place(PlaceableDB.get_def("small_generator"), gen_at) as Generator
		if gen:
			GameState.inventory.add("wood", 10)
			gen.deposit(GameState.inventory, "wood", 10)
			gen.produce(120.0)
		if ep == null:
			break
		wh.storage.add("wheat", 30, "silver")
		ep.set_recipe("flour")
		ep.set_enabled(true)
		ep.advance(25.0)
		world.player.global_position = ep.interact_point() + Vector2(0, 4)
		world.player.facing = Vector2i.UP
		world.player.camera.reset_smoothing()
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_electric.png"))
		hud.open_processor(ep)
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_electric_panel.png"))
		hud._close_panels()
		if gen:
			hud.open_generator(gen)
			await get_tree().create_timer(0.4).timeout
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_generator_panel.png"))
			hud._close_panels()
		break

	# 컨베이어: 창고 출구 → 벨트(직선·모서리) → 전기 가공기 입구, 벨트 위 물건 / 건설 모드의 입구·출구 화살표
	# 앞 장면들이 지은 시설로 밭이 차 있으므로 먼저 치운다
	for obj in world.build.objects().duplicate():
		obj.take_contents()
		world.build.remove(obj)
	await get_tree().process_frame
	var spot := Vector2i(-1, -1)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort()
	for c: Vector2i in cells:
		var ok := true
		for y in 7:
			for x in 11:
				var fc := c + Vector2i(x, y)
				ok = ok and world.build.is_buildable_ground(fc) and not world.build.is_occupied(fc) and (world.farm.get_tile(fc) == null or not world.farm.get_tile(fc).has_crop())
		if ok:
			spot = c
			break
	if spot.x >= 0:
		for y in 7:
			for x in 11:
				world.obstacles.remove(spot + Vector2i(x, y))
				world.farm.untill(spot + Vector2i(x, y))
		await get_tree().process_frame
		var cwh := world.build.place(PlaceableDB.get_def("warehouse"), spot) as Warehouse
		var cep := world.build.place(PlaceableDB.get_def("electric_processor"), spot + Vector2i(7, 4)) as Processor
		var belt_def := PlaceableDB.get_def("conveyor")
		var belts: Array[Vector2i] = []
		for p in BuildMode.belt_path(spot + Vector2i(4, 2), spot + Vector2i(6, 5)):
			world.build.place(belt_def, p.cell, int(p.turns))
			belts.append(p.cell)
		for p in BuildMode.belt_path(spot + Vector2i(10, 5), spot + Vector2i(10, 6)):
			world.build.place(belt_def, p.cell, int(p.turns))
		var put_items := ["wheat", "carrot", "wheat", "tomato"]
		for i in put_items.size():
			var b := world.build.object_at(belts[i * 2 % belts.size()]) as Conveyor
			if b:
				b.put(put_items[i], "silver", 0.4)
		if cwh and cep:
			cep.set_recipe("flour")
		world.player.global_position = world.cell_center(spot + Vector2i(5, 7))
		world.player.facing = Vector2i.UP
		world.player.camera.reset_smoothing()
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_conveyor.png"))
		world.build_mode.start_place("conveyor")
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_conveyor_build.png"))
		world.build_mode.stop()

	# 스프링클러·자동 수확기 (§14, §66): 밭 사이 기계 / 놓을 때 범위 미리보기 / 건설 창
	for obj in world.build.objects().duplicate():
		obj.take_contents()
		world.build.remove(obj)
	await get_tree().process_frame
	var fspot := Vector2i(-1, -1)
	for c: Vector2i in cells:
		var ok := true
		for y in 7:
			for x in 11:
				var fc := c + Vector2i(x, y)
				ok = ok and world.build.is_buildable_ground(fc) and (world.farm.get_tile(fc) == null or not world.farm.get_tile(fc).has_crop())
		if ok:
			fspot = c
			break
	if fspot.x >= 0:
		for y in 7:
			for x in 11:
				world.obstacles.remove(fspot + Vector2i(x, y))
		var field_seeds := ["carrot_seed", "potato_seed", "strawberry_seed"]
		for y in range(1, 6):
			for x in range(1, 10):
				var fc := fspot + Vector2i(x, y)
				world.farm.till(fc)
				if Vector2i(x, y) in [Vector2i(3, 3), Vector2i(7, 3)]:
					continue
				world.farm.plant(fc, ItemDB.get_item(field_seeds[(x + y) % 3]))
				world.farm.get_tile(fc).days_grown = 1 + (x * 3 + y) % 6
		world.build.place(PlaceableDB.get_def("sprinkler_2"), fspot + Vector2i(3, 3))
		var fh := world.build.place(PlaceableDB.get_def("harvester_1"), fspot + Vector2i(7, 3)) as AutoHarvester
		if fh:
			fh.output = [{"id": "carrot", "count": 3, "quality": "silver"}] as Array[Dictionary]
			fh._update_icon()
		world.build.start_day()
		world.player.global_position = world.cell_center(fspot + Vector2i(5, 6))
		world.player.facing = Vector2i.UP
		world.player.camera.reset_smoothing()
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_farm_machines.png"))
		world.build_mode.start_place("sprinkler_3")
		world.build_mode._use_mouse = false
		world.player.global_position = world.cell_center(fspot + Vector2i(5, 1))
		world.player.facing = Vector2i.DOWN
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_sprinkler_preview.png"))
		world.build_mode.stop()
	# 펌프·물탱크 (§14): 연못가 펌프 → 물탱크 → 스프링클러, HUD 물 표시 / 물가가 아닌 곳에 펌프를 놓으려 할 때
	for obj in world.build.objects().duplicate():
		obj.take_contents()
		world.build.remove(obj)
	for y in range(29, 35):
		for x in range(4, 16):
			world.obstacles.remove(Vector2i(x, y))
			world.farm.remove_crop(Vector2i(x, y))
			world.farm.untill(Vector2i(x, y))
	await get_tree().process_frame
	var wtank := world.build.place(PlaceableDB.get_def("water_tank"), Vector2i(12, 30)) as WaterTank
	world.build.place(PlaceableDB.get_def("pump"), Vector2i(8, 34))
	var wgen := world.build.place(PlaceableDB.get_def("small_generator"), Vector2i(14, 30)) as Generator
	if wgen:
		GameState.inventory.add("wood", 5)
		wgen.deposit(GameState.inventory, "wood", 5)
		wgen.produce(120.0)
	for c in FarmArea.cells(Vector2i(7, 31), {"shape": "square", "radius": 1}):
		world.farm.till(c)
		world.farm.plant(c, ItemDB.get_item("carrot_seed"))
	world.build.place(PlaceableDB.get_def("sprinkler_2"), Vector2i(7, 31))
	if wtank:
		wtank.water = 120.0
	world.build.start_day()
	world.player.global_position = world.cell_center(Vector2i(10, 33))
	world.player.facing = Vector2i.UP
	world.player.camera.reset_smoothing()
	Events.power_changed.emit()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_pump_tank.png"))
	world.build_mode.start_place("pump")
	world.build_mode._use_mouse = false
	world.player.global_position = world.cell_center(Vector2i(10, 31))
	world.player.facing = Vector2i.DOWN
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_pump_bad.png"))
	world.build_mode.stop()

	# 분배기·합류기·필터 분배기 (§62): 한 줄을 세 갈래로 나눴다가 다시 합침 / 건설 모드 화살표
	for obj in world.build.objects().duplicate():
		obj.take_contents()
		world.build.remove(obj)
	await get_tree().process_frame
	if fspot.x >= 0:
		for y in 7:
			for x in 11:
				world.farm.remove_crop(fspot + Vector2i(x, y))
				world.farm.untill(fspot + Vector2i(x, y))
		var bdef := PlaceableDB.get_def("conveyor")
		var place_path := func(a: Vector2i, b: Vector2i) -> void:
			for p in BuildMode.belt_path(fspot + a, fspot + b):
				world.build.place(bdef, p.cell, int(p.turns))
		place_path.call(Vector2i(0, 3), Vector2i(1, 3))
		world.build.place(PlaceableDB.get_def("splitter"), fspot + Vector2i(2, 3), 3)
		world.build.place(bdef, fspot + Vector2i(2, 2), 2)
		world.build.place(bdef, fspot + Vector2i(2, 1), 3)
		place_path.call(Vector2i(3, 1), Vector2i(6, 1))
		place_path.call(Vector2i(7, 1), Vector2i(7, 2))
		place_path.call(Vector2i(3, 3), Vector2i(6, 3))
		world.build.place(bdef, fspot + Vector2i(2, 4), 0)
		world.build.place(bdef, fspot + Vector2i(2, 5), 3)
		place_path.call(Vector2i(3, 5), Vector2i(6, 5))
		place_path.call(Vector2i(7, 5), Vector2i(7, 4))
		world.build.place(PlaceableDB.get_def("merger"), fspot + Vector2i(7, 3), 3)
		place_path.call(Vector2i(8, 3), Vector2i(10, 3))
		var items := ["carrot", "potato", "strawberry", "wheat", "tomato", "flour"]
		var k := 0
		for obj in world.build.objects():
			if obj is Conveyor and not obj is Router and k < 40:
				if k % 3 == 0:
					(obj as Conveyor).put(items[int(k / 3.0) % items.size()], "silver", 0.5)
				k += 1
		world.player.global_position = world.cell_center(fspot + Vector2i(5, 6))
		world.player.facing = Vector2i.UP
		world.player.camera.reset_smoothing()
		await get_tree().create_timer(0.6).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_routers.png"))
		world.build_mode.start(BuildMode.Mode.MOVE)
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_routers_build.png"))
		world.build_mode.stop()

	hud.open_build_panel()
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_build_menu.png"))
	hud._close_panels()

	# 아침 야간 생산 요약 (§98)
	hud._night.open(GameState.day, {"items": {"flour": 24, "bread": 10, "basic_fertilizer": 2}, "energy": 300.0})
	hud._center(hud._night)
	get_tree().paused = true
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_night_summary.png"))
	hud._close_panels()

	# 중급 가공기 (§70, 사용자 결정): 창고 | 중급 가공기 + 발전기, 채소 절임 세트 만드는 중 → 창
	var mid_def := PlaceableDB.get_def("mid_processor")
	var mid_at := Vector2i(-1, -1)
	var mcells: Array = world.farm.farmable_cells.keys()
	mcells.sort()
	for c: Vector2i in mcells:
		var ok := c.x > 14
		for y in 6:
			for x in 9:
				var fc: Vector2i = c + Vector2i(x, y)
				if not world.build.is_buildable_ground(fc) or world.build.is_occupied(fc) or world.farm.tiles.has(fc):
					ok = false
		if ok:
			mid_at = c
			break
	if mid_at.x >= 0:
		for y in 6:
			for x in 9:
				world.obstacles.remove(mid_at + Vector2i(x, y))
		await get_tree().process_frame
		var mwh := world.build.place(PlaceableDB.get_def("warehouse"), mid_at) as Warehouse
		var mid := world.build.place(mid_def, mid_at + Vector2i(4, 0)) as Processor
		var mgen := world.build.place(PlaceableDB.get_def("small_generator"), mid_at + Vector2i(7, 0)) as Generator
		if mid and mwh:
			for id: String in ["pickled_cabbage", "vegetable_pickle_set", "premium_jam_strawberry", "premium_jam_blueberry"]:
				RecipeDB.learn(id)
			if mgen:
				GameState.inventory.add("wood", 10)
				mgen.deposit(GameState.inventory, "wood", 10)
				mgen.produce(120.0)
			mwh.storage.add("pickled_cabbage", 6, "silver")
			mwh.storage.add("eggplant", 6, "gold")
			mwh.storage.add("radish", 6, "silver")
			mid.set_recipe("vegetable_pickle_set")
			mid.set_enabled(true)
			mid.advance(40.0)
			world.player.global_position = mid.interact_point() + Vector2(0, 4)
			world.player.facing = Vector2i.UP
			world.player.camera.reset_smoothing()
			await get_tree().create_timer(0.8).timeout
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_mid_processor.png"))
			hud.open_processor(mid)
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_mid_processor_panel.png"))
			hud._close_panels()

	# 용광로 (사용자 결정: 1x1, 광석 5 + 석탄 1 → 주괴): 하나는 굽는 중(불빛), 하나는 다 구움(주괴 아이콘) + 대장간 창 (철·금 단계)
	var furn_fdef := PlaceableDB.get_def("furnace")
	var furn_fspot := Vector2i(-1, -1)
	var furn_fcells: Array = world.farm.farmable_cells.keys()
	furn_fcells.sort()
	for c: Vector2i in furn_fcells:
		var ok := true
		for x in 4:
			for y in 2:
				var cc: Vector2i = c + Vector2i(x, y)
				ok = ok and world.build.is_buildable_ground(cc) and not world.build.is_occupied(cc) and not world.farm.tiles.has(cc)
		if ok:
			furn_fspot = c
			break
	if furn_fspot.x >= 0:
		for x in 4:
			for y in 2:
				world.obstacles.remove(furn_fspot + Vector2i(x, y))
		var furn_f1 := world.build.place(furn_fdef, furn_fspot) as Furnace
		var furn_f2 := world.build.place(furn_fdef, furn_fspot + Vector2i(2, 0)) as Furnace
		GameState.inventory.add("iron_ore", 10)
		GameState.inventory.add("coal", 2)
		furn_f1.start(GameState.inventory, "iron_ore")
		furn_f2.start(GameState.inventory, "iron_ore")
		furn_f2.on_time(60.0)
		world.player.global_position = world.cell_center(furn_fspot + Vector2i(1, 1))
		world.player.facing = Vector2i.UP
		world.player.camera.reset_smoothing()
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_furnace.png"))
		GameState.inventory.add("pickaxe_2")
		GameState.inventory.add("iron_bar", 3)
		hud.open_blacksmith()
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_smith_tiers.png"))
		hud._close_panels()

	# 꾹 누르기 (사용자 결정: 금 괭이 2초 → 앞쪽 3x3): 머리 위 막대 + 바닥 미리보기
	if furn_fspot.x >= 0:
		GameState.inventory.slots[0] = {"id": "hoe_4", "count": 1}
		GameState.select_slot(0)
		world.player.global_position = world.cell_center(furn_fspot + Vector2i(1, -3))
		world.player.facing = Vector2i.UP
		world.player.camera.reset_smoothing()
		world.player.start_charge()
		world.player._charge = 2.4
		await get_tree().create_timer(0.3).timeout
		world.player._charge = 2.4
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_charge.png"))
		world.player.cancel_charge()

	# 광산 (사용자 결정: 북쪽 숲길 끝 입구 · 아래로 내려가는 층 · 엘리베이터)
	var shot := func(file: String) -> void:
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://%s.png" % file))
	GameState.minutes = 14 * 60
	world.player.wake_at(world.mine_entrance.interact_point() + Vector2(0, 10))
	world.player.facing = Vector2i.UP
	world._apply_camera_area()
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	shot.call("shot_mine_entrance")
	GameState.unlocks["mine_deepest"] = 12
	Events.mine_requested.emit(0)
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	shot.call("shot_mine_floor0")
	var lift: MineFeature = world.mine._features.filter(func(f: MineFeature) -> bool: return f.kind == MineFeature.Kind.ELEVATOR)[0]
	lift.interact(world.player)
	await get_tree().create_timer(0.5).timeout
	shot.call("shot_mine_elevator")
	hud._close_panels()
	Events.mine_requested.emit(12)
	world.player.facing = Vector2i.RIGHT
	for i in 3:  # 바위 몇 개를 깨서 사다리가 보이게
		var o: Obstacle = world.mine.rocks.all()[i]
		world.mine.rocks.remove(o.cell)
		world.mine._on_rock_cleared(o.cell, o.def)
	if not world.mine.has_ladder():
		var o2: Obstacle = world.mine.rocks.all()[0]
		world.mine.rocks.remove(o2.cell)
		world.mine._ladder_found = true
		world.mine._add_feature(MineFeature.Kind.DOWN, o2.cell - Mine.ORIGIN)
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	shot.call("shot_mine_floor12")
	Events.mine_requested.emit(10)
	world.player.camera.reset_smoothing()
	await get_tree().create_timer(0.8).timeout
	shot.call("shot_mine_treasure")
	world.exit_mine()

	# 맵 전체 내려다보기
	get_tree().paused = false
	main.get_node("HUD").visible = false
	var cam := world.player.camera
	cam.limit_right = 100000
	cam.limit_bottom = 100000
	cam.limit_left = -100000
	cam.limit_top = -100000
	cam.zoom = Vector2(1.1, 1.1)
	world.player.global_position = Vector2(MapLayout.size() * Art.TILE) / 2.0 + Vector2(0, 8)
	cam.reset_smoothing()
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_overview.png"))
	# 시작 화면 (게임 화면을 치우고 그 자리에 띄운다)
	main.queue_free()
	await get_tree().process_frame
	var title: TitleScreen = load("res://scenes/title.tscn").instantiate()
	title.open_main = func() -> void: pass
	add_child(title)
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://shot_title.png"))
	print("SHOTS ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()
