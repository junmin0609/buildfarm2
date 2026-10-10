extends Node
## 5단계 재시작 검증용 (퀘스트 상태 강제): 가방이 가득한 채 MQ17 을 받아 지원 물건 대기 → 저장 (ckpt_support_pending),
## 가방 한 칸 비움 → 저장 (ckpt_support_space). 두 파일을 restart_check 로 새 프로세스에서 불러 본다.
## 2단계: --verify 로 다시 켜서 대기 파일을 불러와 저절로 안 주는지 · [받기] 한 번만 되는지 확인

func _ready() -> void:
	var verify := "--verify" in OS.get_cmdline_user_args()
	SaveManager.slot_path = "user://ckpt_support_space.json" if verify else "user://support_tmp.json"
	SaveManager.load_on_start = verify
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 3:
		await get_tree().process_frame
	var world: FarmWorld = main.get_node("FarmWorld")
	var qm := world.quests
	var inv := GameState.inventory
	if verify:
		var wheat0 := inv.count_of("wheat")
		var left: Dictionary = qm._support_left("MQ17")
		for i in 5:
			qm.claim_support("MQ17", "wheat")
		print("SUPPORT_VERIFY loaded_wheat=%d waiting=%s after_5_claims=%d left=%s" % [wheat0, left, inv.count_of("wheat"), qm._support_left("MQ17")])
		get_tree().quit()
		return
	inv.load_data([])
	while inv.add("stone", 999) == 0:
		pass
	for q: Dictionary in QuestManager.quest_defs():
		if q.id == "MQ17":
			break
		qm.quests[q.id].state = QuestManager.REWARDED
	qm._activate_ready()
	world.save_manager.save_game("manual")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SaveManager.slot_path), ProjectSettings.globalize_path("user://ckpt_support_pending.json"))
	inv.remove_at(0, inv.get_slot(0).count)
	world.save_manager.save_game("manual")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SaveManager.slot_path), ProjectSettings.globalize_path("user://ckpt_support_space.json"))
	print("SUPPORT_CKPT pending=%s wheat=%d" % [qm._support_left("MQ17"), inv.count_of("wheat")])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://support_tmp.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://support_tmp.json.bak"))
	get_tree().quit()
