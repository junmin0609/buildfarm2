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


## 저장된 설정을 읽어 화면에 적용한다 (게임을 켤 때 한 번)
static func apply_saved() -> void:
	if not _loaded:
		load_settings()
	_apply_window()


static func set_fullscreen(on: bool) -> void:
	fullscreen = on
	save_settings()
	_apply_window()


static func _apply_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
