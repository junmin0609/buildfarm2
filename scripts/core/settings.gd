class_name Settings
extends RefCounted
## 게임 설정 (저장 파일과 따로, user://settings.cfg). 시작 화면의 [설정]에서 바꾼다.
## 지금 있는 설정: 전체 화면. 소리·키 바꾸기 같은 설정은 생기면 여기에 더한다.

static var path := "user://settings.cfg"

static var fullscreen := false
static var _loaded := false


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		fullscreen = bool(cfg.get_value("display", "fullscreen", false))
	_loaded = true


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.save(path)


## 저장된 설정을 읽어 화면에 적용한다 (게임을 켤 때 한 번, GameState 가 부른다)
static func apply_saved() -> void:
	if _loaded:
		return
	load_settings()
	if _can_control_window() and not fullscreen:
		_fit_window_to_screen()
	_apply_window()


static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	save_settings()
	_apply_window()


static func _apply_window() -> void:
	if not _can_control_window():
		return
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)


## 창을 직접 다룰 수 있는가. 점검(headless)이나 에디터 안 Game 탭에 끼워 실행 중이면 창 크기·전체 화면을 건드리지 않는다
static func _can_control_window() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	return not (Engine.has_method("is_embedded_in_editor") and Engine.call("is_embedded_in_editor"))


## 처음 창 크기: 기본 1280x720 은 고해상도·배율 높은 모니터에서 너무 작게 뜬다.
## 화면 작업 영역의 90% 안에 들어가는 가장 큰 640x360 배수(16:9)로 키우고 가운데에 놓는다.
static func _fit_window_to_screen() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var k := 2
	while 640 * (k + 1) <= usable.size.x * 0.9 and 360 * (k + 1) <= usable.size.y * 0.9:
		k += 1
	var size := Vector2i(640 * k, 360 * k)
	if size.x > usable.size.x or size.y > usable.size.y:
		return
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)
