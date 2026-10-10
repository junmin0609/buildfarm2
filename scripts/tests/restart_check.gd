extends Node
## 5단계 재시작 검증: 새 프로세스에서 저장 파일 하나를 불러와 (게임을 다시 켠 것과 같음) 곧바로 다시 저장하고,
## 두 저장의 내용이 같은지 본다 (복제·보상 중복·잠금 오류·손상이 있으면 달라진다). 불러온 뒤 몇 프레임 돌려도 돈·가방이 그대로인지도.
## 실행: Godot --headless --path . res://scenes/tests/restart_check.tscn -- --file=user://ckpt_xxx.json
## 원본 파일은 읽기만 한다 (불러온 뒤 저장은 user://restart_resave.json 에).

func _ready() -> void:
	var file := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			file = a.trim_prefix("--file=")
	var before_text := FileAccess.get_file_as_string(file)
	var original: Variant = JSON.parse_string(before_text)
	SaveManager.slot_path = file
	SaveManager.load_on_start = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	# 불러온 바로 그 상태를 비교하려고 게임 시계를 멈춘다 (멈추지 않으면 기계가 몇 프레임만큼 일해 결과물이 벨트로 나가는 등 '정상 진행'이 차이로 보인다)
	GameState.set_time_paused("restart_check", true)
	for i in 5:
		await get_tree().process_frame
	var world: FarmWorld = main.get_node("FarmWorld")
	var ok_load: bool = world.save_manager.last_load.get("ok", false)
	var failed: Array = world.save_manager.last_load.get("failed", [])
	var money := GameState.money
	var bag := GameState.inventory.to_data()
	for i in 30:
		await get_tree().process_frame
	var stable := GameState.money == money and GameState.inventory.to_data() == bag
	SaveManager.slot_path = "user://restart_resave.json"
	world.save_manager.save_game("manual")
	var resaved: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://restart_resave.json"))
	var diffs: Array[String] = []
	# 불러온 뒤 몇 프레임 동안 시계가 흐른 것(게임 시계 초)은 차이로 보지 않는다
	var clock_drift := float(resaved.sections.game.day_seconds) - float(original.sections.game.day_seconds)
	resaved.sections.game.day_seconds = original.sections.game.day_seconds
	for key: String in original.sections:
		if JSON.stringify(original.sections[key]) != JSON.stringify(resaved.sections.get(key)):
			diffs.append(key + _first_diff(original.sections[key], resaved.sections.get(key), key))
	var untouched := FileAccess.get_file_as_string(file) == before_text
	print("RESTART %s load=%s failed=%s stable=%s same=%s original_untouched=%s clock_drift=%.2fs diffs=%s" % [file.get_file(), ok_load, failed, stable, diffs.is_empty(), untouched, clock_drift, diffs])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://restart_resave.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://restart_resave.json.bak"))
	get_tree().quit()


## 처음 다른 곳 (어디가 다른지 보고용)
func _first_diff(a: Variant, b: Variant, path: String) -> String:
	if a is Dictionary and b is Dictionary:
		for k: Variant in a:
			if JSON.stringify(a[k]) != JSON.stringify(b.get(k)):
				return _first_diff(a[k], b.get(k), path + "." + str(k))
		for k: Variant in b:
			if not a.has(k):
				return " (%s.%s 새로 생김)" % [path, k]
	if a is Array and b is Array:
		if a.size() != b.size():
			return " (%s 길이 %d → %d)" % [path, a.size(), b.size()]
		for i in a.size():
			if JSON.stringify(a[i]) != JSON.stringify(b[i]):
				return _first_diff(a[i], b[i], "%s[%d]" % [path, i])
	return " (%s: %s → %s)" % [path, str(a).left(80), str(b).left(80)]
