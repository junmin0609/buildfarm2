class_name SaveManager
extends Node
## 저장 / 불러오기 (BUILD_FARM_PLAN §102). 세이브 슬롯 1개 (slot_path).
##   - 하루 전환 자동 저장: DayCycle 의 마지막 단계(save). 날짜 → 07:00 → 집 앞 시작 위치가 반영된 뒤 저장한다.
##   - 수동 저장: 지금 상태 그대로 (위치·시각 포함). 불러오면 그 자리·그 시각에서 다시 시작한다.
##   - 게임을 켤 때 저장이 있으면 이어서 한다 (load_on_start).
##
## 각 시스템은 자기 데이터를 직접 만들고 되살린다. 여기서는 섹션 이름과 순서만 관리한다.
##   새 시스템 추가: world.save_manager.register("warehouses", my_to_data, my_load_data)
##   my_load_data(data: Variant) -> bool  모양이 틀린 데이터면 false 를 돌려주고 멈추지 않아야 한다.
## 불러오는 순서 = 등록 순서. 저장 파일에 없는 섹션은 그 시스템의 지금 상태(새 게임 상태)를 그대로 둔다.
##
## 파일 형식 (JSON): {"version": 1, "kind": "auto"/"manual", "saved_at": "...", "sections": {이름: 데이터}}
## 쓸 때는 임시 파일에 먼저 쓰고 바꿔치기한다. 이전 저장은 .bak 으로 하나 남긴다.

const VERSION := 1

## 세이브 파일 위치 (점검·화면 확인 스크립트는 다른 파일을 쓰도록 바꾼다)
static var slot_path := "user://save_slot_1.json"
## 게임을 켤 때 저장이 있으면 불러올지
static var load_on_start := true
## 새 게임을 고른 직후 한 번은 불러오지 않는다
static var skip_load_once := false

var world: FarmWorld
## 마지막 불러오기 결과 {"ok": bool, "error": String, "failed": [섹션 이름], "missing": [섹션 이름]}
var last_load := {}

var _sections: Array[Dictionary] = []   # {"key", "save": Callable, "load": Callable}


func _ready() -> void:
	# 불러오는 순서: 돈·시간·가방 → 밭 → 장애물 → 시설 → 플레이어 위치
	register("game", GameState.to_data, GameState.load_data)
	register("farm", world.farm.to_data, world.farm.load_data)
	register("obstacles", world.obstacles.to_data, world.obstacles.load_data)
	register("build", world.build.to_data, func(d: Variant) -> bool: return world.build.load_data(d) != [null])
	register("player", world.player.to_data, world.player.load_data)
	if world.shipping_bin:
		register("shipping_bin", world.shipping_bin.to_data, world.shipping_bin.load_data)
	world.day_cycle.add_step(DayCycle.SAVE, func(_report: Dictionary) -> void: save_game("auto"))
	Events.save_requested.connect(_on_save_requested)
	Events.load_requested.connect(_on_load_requested)
	Events.new_game_requested.connect(start_new_game)
	if skip_load_once:
		skip_load_once = false
	elif load_on_start and has_save():
		load_game()


func register(key: String, save_func: Callable, load_func: Callable) -> void:
	for section in _sections:
		if section.key == key:
			push_error("저장 섹션 이름이 겹칩니다: %s" % key)
			return
	_sections.append({"key": key, "save": save_func, "load": load_func})


func has_save() -> bool:
	return FileAccess.file_exists(slot_path)


## 저장한다. kind: "manual" / "auto". 성공하면 true.
func save_game(kind := "manual") -> bool:
	var sections := {}
	for section in _sections:
		sections[section.key] = section.save.call()
	var data := {
		"version": VERSION,
		"kind": kind,
		"saved_at": Time.get_datetime_string_from_system(),
		"sections": sections,
	}
	var tmp := slot_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("저장 파일을 쓸 수 없습니다: %s" % tmp)
		return false
	# full_precision: 시각·위치 소수점을 잘라 먹지 않게
	file.store_string(JSON.stringify(data, "\t", true, true))
	file.close()
	if has_save():
		DirAccess.copy_absolute(_abs(slot_path), _abs(slot_path + ".bak"))
	if DirAccess.rename_absolute(_abs(tmp), _abs(slot_path)) != OK:
		push_warning("저장 파일을 바꿔치기하지 못했습니다: %s" % slot_path)
		return false
	Events.game_saved.emit(kind)
	return true


## 불러온다. 파일이 없거나 읽을 수 없으면 지금 상태를 그대로 두고 false.
## 섹션 하나가 손상됐으면 그 섹션만 건너뛰고 나머지는 불러온다 (last_load.failed 에 기록).
func load_game() -> bool:
	last_load = {"ok": false, "error": "", "failed": [], "missing": []}
	var data := read_save()
	if data.has("error"):
		last_load.error = data.error
		push_warning("저장을 불러오지 못했습니다: %s" % data.error)
		return false
	Events.game_loading.emit()
	world.build_mode.stop()
	GameState.clear_pauses_and_locks()
	var sections: Dictionary = data.sections
	for section in _sections:
		if not sections.has(section.key):
			last_load.missing.append(section.key)
			continue
		if not section.load.call(sections[section.key]):
			last_load.failed.append(section.key)
			push_warning("저장 섹션이 손상돼 건너뜁니다: %s" % section.key)
	last_load.ok = true
	Events.game_loaded.emit()
	return true


## 저장 파일을 읽어 검사한다. 문제가 있으면 {"error": 이유}.
func read_save() -> Dictionary:
	if not has_save():
		return {"error": "저장 파일이 없어요."}
	var file := FileAccess.open(slot_path, FileAccess.READ)
	if file == null:
		return {"error": "저장 파일을 열 수 없어요."}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return {"error": "저장 파일이 손상됐어요."}
	var data: Dictionary = json.data
	var version: Variant = data.get("version")
	if typeof(version) != TYPE_INT and typeof(version) != TYPE_FLOAT:
		return {"error": "저장 파일 버전을 알 수 없어요."}
	if int(version) > VERSION:
		return {"error": "더 새로운 버전의 저장 파일이에요. (파일 %d, 게임 %d)" % [int(version), VERSION]}
	if not data.get("sections") is Dictionary:
		return {"error": "저장 파일이 손상됐어요."}
	return _migrate(data)


## 예전 버전 저장을 지금 형식으로 바꾼다. 형식이 바뀔 때 VERSION 을 올리고 여기에 변환을 추가한다.
func _migrate(data: Dictionary) -> Dictionary:
	data.version = VERSION
	return data


func _on_save_requested() -> void:
	Events.toast.emit("저장했어요." if save_game("manual") else "저장하지 못했어요.")


func _on_load_requested() -> void:
	if load_game():
		var broken: Array = last_load.failed
		Events.toast.emit("불러왔어요." if broken.is_empty() else "불러왔어요. 일부 정보가 손상돼 처음 상태로 뒀어요.")
	else:
		Events.toast.emit(str(last_load.error))


## 새 게임: 처음 상태로 맵을 다시 만든다. 저장 파일은 다음 저장 때 덮어쓴다.
func start_new_game() -> void:
	skip_load_once = true
	GameState.new_game()
	get_tree().paused = false
	get_tree().reload_current_scene()


## 메뉴에 보여 줄 저장 설명 ("3일차 오전 9:20 · 수동 저장"). 없거나 읽을 수 없으면 "".
static func describe_save() -> String:
	if not FileAccess.file_exists(slot_path):
		return ""
	var file := FileAccess.open(slot_path, FileAccess.READ)
	var json := JSON.new()
	if file == null or json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return "읽을 수 없음"
	var game: Variant = json.data.get("sections", {}).get("game") if json.data.get("sections") is Dictionary else null
	if not game is Dictionary:
		return "읽을 수 없음"
	var kind := "자동 저장" if json.data.get("kind") == "auto" else "수동 저장"
	return "%d일차 · %s" % [int(game.get("day", 1)), kind]


static func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)
