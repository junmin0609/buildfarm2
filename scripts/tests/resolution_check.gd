extends Node
## 화면 크기 대응 확인용: 게임 화면을 띄우고 창 크기를 바꿔 가며 스크린샷과 숫자를 남긴다 (user://res_*.png).

const SIZES := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1700, 1000), Vector2i(2400, 1000), Vector2i(1200, 1000)]


func _ready() -> void:
	SaveManager.load_on_start = false
	SaveManager.slot_path = "user://resolution_check_save.json"
	Weather.forced = "sunny"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.8).timeout
	var world: FarmWorld = main.get_node("FarmWorld")
	print("START window=%s pos=%s screen_usable=%s" % [DisplayServer.window_get_size(), DisplayServer.window_get_position(), DisplayServer.screen_get_usable_rect()])
	for i in SIZES.size() + 1:
		var s: Vector2i = SIZES[i] if i < SIZES.size() else Vector2i.ZERO
		if s == Vector2i.ZERO:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_size(s)
		print("set ", s)
		for f in 30:
			await get_tree().process_frame
		var vp := get_viewport()
		var cam := world.player.camera
		var img := vp.get_texture().get_image()
		var scale := float(get_window().size.x) / vp.get_visible_rect().size.x
		print("RES window=%s visible_rect=%s texture=%s zoom=%.3f world_view=%s screen_px_per_art_px=%.3f" % [DisplayServer.window_get_size(), vp.get_visible_rect().size, img.get_size(), cam.zoom.x, vp.get_visible_rect().size / cam.zoom, scale * cam.zoom.x])
		img.save_png(ProjectSettings.globalize_path("user://res_%d.png" % i))
	get_tree().quit()
