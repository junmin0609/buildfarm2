extends Node
## 5단계 화면 확인: 창 크기를 바꿔 가며 스토리 UI(퀘스트 HUD · 퀘스트 창 · 지원 물건 · 기술 탭 · NPC 납품 대화 · 기계상점 잠김)가
## 화면 밖으로 잘리는지 숫자로 재고 스크린샷을 남긴다 (user://uires_<크기>_<창>.png). 화면 상태는 강제로 맞춘다 (MQ11 진행 중).

const SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1200, 1000), Vector2i(2400, 1000)]


func _ready() -> void:
	SaveManager.load_on_start = false
	SaveManager.slot_path = "user://uires_save.json"
	Weather.forced = "sunny"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	var world: FarmWorld = main.get_node("FarmWorld")
	var hud: HUD = main.get_node("HUD")
	var qm := world.quests
	for q: Dictionary in QuestManager.quest_defs():
		if q.id == "MQ11":
			break
		qm.quests[q.id].state = QuestManager.REWARDED
	qm._activate_ready()
	qm.techs["basic_buildings"] = true
	GameState.inventory.add("wood", 12)
	GameState.inventory.add("stone", 4)
	qm.donate("mine_repair", "stone")
	qm.support["MQ17"] = {"owed": {"wheat": 4}, "given": {"wheat": 1}}
	qm.support["MQ20"] = {"owed": {"flour": 3}, "given": {}}
	var worst := ""
	for s: Vector2i in SIZES:
		DisplayServer.window_set_size(s)
		for f in 20:
			await get_tree().process_frame
		var tag := "%dx%d" % [s.x, s.y]
		for what: String in ["hud", "quest_log", "tech", "dialog", "shop"]:
			match what:
				"quest_log":
					hud.open_quest_log()
					hud._quest_log.show_tab("quests")
				"tech":
					hud.open_quest_log()
					hud._quest_log.show_tab("tech")
				"dialog":
					world.interiors["smith"].npc.interact(world.player)
				"shop":
					Events.shop_requested.emit("machine")
			for f in 6:
				await get_tree().process_frame
			var panel: Control = {"hud": hud._quest_tracker, "quest_log": hud._quest_log, "tech": hud._quest_log, "dialog": hud._dialog, "shop": hud._shop}[what]
			var view := panel.get_viewport_rect()
			var r := panel.get_global_rect()
			var inside := view.encloses(r.grow(-1))
			var line := "UIRES %s %s panel=%s view=%s inside=%s" % [tag, what, r, view.size, inside]
			print(line)
			if not inside:
				worst += line + "\n"
			if s in [Vector2i(1280, 720), Vector2i(2560, 1440)] or not inside:
				get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://uires_%s_%s.png" % [tag, what]))
			hud._close_panels()
			await get_tree().process_frame
	print("UIRES_DONE clipped=%s" % ("없음" if worst == "" else "\n" + worst))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://uires_save.json"))
	get_tree().quit()
