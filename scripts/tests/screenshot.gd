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
	var origin := Vector2i(9999, 9999)
	for c: Vector2i in farm.farmable_cells:
		if MapLayout.char_at(c) == "d":
			origin = Vector2i(mini(origin.x, c.x), mini(origin.y, c.y))
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
	print("SHOTS ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()
