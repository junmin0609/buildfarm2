class_name HUD
extends CanvasLayer
## 화면 UI 전체: 날짜·시간·돈, 핫바, 안내 문구, 가방 창, 상점 창.
## 상점·건설 창이 열리면 게임과 시간을 멈춘다 (HUD 자신은 계속 동작).
## 가방 창은 시간을 멈추지 않는다 (BUILD_FARM_PLAN §94). 대신 열려 있는 동안 플레이어 조작만 막는다.

const WEEKDAYS := ["월", "화", "수", "목", "금", "토", "일"]
const TEXT := Color("5b3a29")        # 크림색 패널 위 진한 갈색 글씨
const TEXT_SOFT := Color("9a7457")
const ACCENT := Color("d9604f")

var _root: Control
var _day_label: Label
var _time_label: Label
var _money_label: Label
var _power_label: Label
var _water_label: Label
var _prompt: Label
var _prompt_box: PanelContainer
var _clock_icon: TextureRect
var _toast: Label
var _toast_tween: Tween
var _fade: ColorRect
var _hotbar: Hotbar
var _inventory: InventoryPanel
var _shop: ShopPanel
var _build: BuildPanel
var _build_hint: PanelContainer
var _build_hint_label: Label
var _crop_info: CropInfoPopup
var _weather_fx: WeatherOverlay
var _item_tip: ItemTooltip
var _menu: SystemMenu
var _bin_panel: ShippingBinPanel
var _summary: SalesSummaryPanel
var _night: NightSummaryPanel
## 판매 요약을 닫은 뒤 보여 줄 야간 생산 결과 (report.night_production). 비어 있으면 없음
var _pending_night := {}
var _pending_night_day := 0
var _smith: BlacksmithPanel
var _recipes: RecipeShopPanel
var _router: RouterPanel
var _sky_station: SkyStationPanel
var _sky_market: SkyMarketPanel
var _dialog: DialogPanel
var _compost: CompostBinPanel
var _warehouse: WarehousePanel
var _processor: ProcessorPanel
var _generator: GeneratorPanel
## 마지막 하루 마감 이유 ("time_up" / "sleep")
var _end_reason := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)

	# 비·눈 효과는 게임 화면 바로 위, 다른 UI 보다 아래
	_weather_fx = WeatherOverlay.new()
	_root.add_child(_weather_fx)
	_build_info()
	_hotbar = Hotbar.new()
	_place(_hotbar, Vector2(0.5, 1.0), Vector2(0, -12), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)

	_build_prompt()
	_toast = _make_float_label(Art.FONT_SIZE)
	_place(_toast, Vector2(0.5, 0.0), Vector2(0, 20), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_END)

	_inventory = InventoryPanel.new()
	_place(_inventory, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_inventory.hide()
	_inventory.close_requested.connect(_close_panels)
	_shop = ShopPanel.new()
	_place(_shop, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_shop.hide()
	_shop.close_requested.connect(_close_panels)
	_build = BuildPanel.new()
	_place(_build, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_build.hide()
	_build.close_requested.connect(_close_panels)
	_menu = SystemMenu.new()
	_place(_menu, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_menu.hide()
	_menu.close_requested.connect(_close_panels)
	_bin_panel = ShippingBinPanel.new()
	_place(_bin_panel, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_bin_panel.hide()
	_bin_panel.close_requested.connect(_close_panels)
	_summary = SalesSummaryPanel.new()
	_place(_summary, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_summary.hide()
	_summary.close_requested.connect(_on_sales_closed)
	_night = NightSummaryPanel.new()
	_place(_night, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_night.hide()
	_night.close_requested.connect(_close_panels)
	_smith = BlacksmithPanel.new()
	_place(_smith, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_smith.hide()
	_smith.close_requested.connect(_close_panels)
	_recipes = RecipeShopPanel.new()
	_place(_recipes, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_recipes.hide()
	_recipes.close_requested.connect(_close_panels)
	_router = RouterPanel.new()
	_place(_router, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_router.hide()
	_router.close_requested.connect(_close_panels)
	_sky_station = SkyStationPanel.new()
	_place(_sky_station, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_sky_station.hide()
	_sky_station.close_requested.connect(_close_panels)
	_sky_market = SkyMarketPanel.new()
	_place(_sky_market, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_sky_market.hide()
	_sky_market.close_requested.connect(_close_panels)
	_dialog = DialogPanel.new()
	_place(_dialog, Vector2(0.5, 1.0), Vector2(0, -124), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_dialog.hide()
	_dialog.close_requested.connect(_close_panels)
	_dialog.chosen.connect(_on_dialog_chosen)
	_compost = CompostBinPanel.new()
	_place(_compost, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_compost.hide()
	_compost.close_requested.connect(_close_panels)
	_warehouse = WarehousePanel.new()
	_place(_warehouse, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_warehouse.hide()
	_warehouse.close_requested.connect(_close_panels)
	_processor = ProcessorPanel.new()
	_place(_processor, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_processor.hide()
	_processor.close_requested.connect(_close_panels)
	_generator = GeneratorPanel.new()
	_place(_generator, Vector2(0.5, 0.5), Vector2.ZERO, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_generator.hide()
	_generator.close_requested.connect(_close_panels)
	_build_hint_label = Label.new()
	_build_hint = PanelContainer.new()
	_build_hint.add_theme_stylebox_override("panel", _panel_style(12))
	_build_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_hint.add_child(_build_hint_label)
	_place(_build_hint, Vector2(0.5, 1.0), Vector2(0, -98), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)
	_build_hint.hide()
	Events.build_hint_changed.connect(_on_build_hint)

	_crop_info = CropInfoPopup.new()
	_crop_info.add_theme_stylebox_override("panel", _panel_style(10))
	_root.add_child(_crop_info)

	# 아이템 툴팁은 모든 창 위에
	_item_tip = ItemTooltip.new()
	_item_tip.add_theme_stylebox_override("panel", _panel_style(10))
	_root.add_child(_item_tip)

	_fade = ColorRect.new()
	_fade.color = Color("3b2a20")
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_root.add_child(_fade)

	Events.time_changed.connect(_on_time_changed)
	Events.money_changed.connect(_on_money_changed)
	Events.day_started.connect(_on_day_started)
	Events.day_ending.connect(_on_day_ending)
	Events.weather_changed.connect(func(_w: String) -> void: _on_time_changed(GameState.day, GameState.minutes))
	Events.game_loading.connect(_close_panels)
	Events.game_loading.connect(func() -> void: _pending_night = {})
	Events.shipping_bin_requested.connect(open_shipping_bin)
	Events.compost_bin_requested.connect(open_compost_bin)
	Events.warehouse_requested.connect(open_warehouse)
	Events.processor_requested.connect(open_processor)
	Events.generator_requested.connect(open_generator)
	Events.blacksmith_requested.connect(open_blacksmith)
	Events.recipe_shop_requested.connect(open_recipe_shop)
	Events.router_requested.connect(open_router)
	Events.sky_station_requested.connect(open_sky_station)
	Events.sky_market_requested.connect(open_sky_market)
	Events.npc_talk_requested.connect(open_dialog)
	Events.travelled.connect(func(_to: String) -> void: _flash())
	Events.day_ended.connect(_on_day_ended)
	Events.day_ending_soon.connect(_on_day_ending_soon)
	Events.toast.connect(show_toast)
	Events.prompt_changed.connect(_on_prompt_changed)
	Events.shop_requested.connect(_open_shop)
	_on_time_changed(GameState.day, GameState.minutes)
	_on_money_changed(GameState.money)
	_prompt_box.hide()
	_toast.hide()
	show_toast("WASD 이동 · 클릭 도구 · E 상호작용 · I 가방 · B 건설")


func _unhandled_input(event: InputEvent) -> void:
	var panel_open := _inventory.visible or _shop.visible or _build.visible or _menu.visible \
			or _bin_panel.visible or _summary.visible or _night.visible or _smith.visible or _recipes.visible or _router.visible or _sky_station.visible or _sky_market.visible or _dialog.visible or _compost.visible or _warehouse.visible or _processor.visible or _generator.visible
	if (_menu.visible or _summary.visible or _night.visible) and not event.is_action_pressed("cancel"):
		return  # 메뉴·요약이 열려 있으면 다른 키는 무시 (버튼은 GUI 가 처리)
	var blocking := _shop.visible or _bin_panel.visible or _smith.visible or _recipes.visible or _router.visible or _sky_station.visible or _sky_market.visible or _dialog.visible or _compost.visible or _warehouse.visible or _processor.visible or _generator.visible  # 이 창이 열려 있으면 B·I 로 다른 창을 열지 않는다
	if event.is_action_pressed("cancel") and not panel_open and not _build_hint.visible:
		open_menu()  # 건설 모드 중 Esc 는 건설 모드가 받는다
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_menu") and not blocking and not _inventory.visible:
		if _build.visible:
			_close_panels()
		else:
			open_build_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_inventory") and not blocking and not _build.visible:
		if _inventory.visible:
			_close_panels()
		else:
			open_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("cancel") and panel_open:
		if _summary.visible:
			_on_sales_closed()  # 판매 요약을 Esc 로 닫아도 야간 생산 요약은 이어서 뜬다
		else:
			_close_panels()
		get_viewport().set_input_as_handled()
	elif not panel_open:
		_handle_hotbar_keys(event)


func _handle_hotbar_keys(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if k >= KEY_1 and k <= KEY_9:
			GameState.select_slot(k - KEY_1)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			GameState.select_slot(GameState.selected_slot - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			GameState.select_slot(GameState.selected_slot + 1)


func _open_shop(mode: String = "all") -> void:
	_close_inventory()
	_shop.open(mode)
	_center(_shop)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("shop")


func open_build_panel() -> void:
	_close_inventory()
	_build.open()
	_center(_build)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("build_menu")


## 시스템 메뉴 (Esc): 게임과 시간을 멈춘다
func open_menu() -> void:
	_close_inventory()
	_menu.open()
	_center(_menu)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("menu")


## 출하함: 상점처럼 게임과 시간을 멈춘다
func open_shipping_bin(bin: Node) -> void:
	_close_inventory()
	_bin_panel.open(bin as ShippingBin)
	_center(_bin_panel)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("shipping_bin")


## 퇴비통: 출하함처럼 게임과 시간을 멈춘다
func open_compost_bin(bin: Node) -> void:
	_close_inventory()
	_compost.open(bin as CompostBin)
	_center(_compost)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("compost_bin")


## 창고: 출하함처럼 게임과 시간을 멈춘다
func open_warehouse(warehouse: Node) -> void:
	_close_inventory()
	_warehouse.open(warehouse as Warehouse)
	_center(_warehouse)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("warehouse")


## 가공기: 출하함처럼 게임과 시간을 멈춘다 (가공도 시계 기준이라 창을 연 동안은 진행되지 않는다)
func open_processor(processor: Node) -> void:
	_close_inventory()
	_processor.open(processor as Processor)
	_center(_processor)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("processor")


## 발전기: 출하함처럼 게임과 시간을 멈춘다
func open_generator(generator: Node) -> void:
	_close_inventory()
	_generator.open(generator as Generator)
	_center(_generator)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("generator")


## 대장간: 상점처럼 게임과 시간을 멈춘다
func open_blacksmith() -> void:
	_close_inventory()
	_smith.open()
	_center(_smith)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("blacksmith")


## 레시피 상점 (셰프 §71): 상점처럼 게임과 시간을 멈춘다
func open_recipe_shop() -> void:
	_close_inventory()
	_recipes.open()
	_center(_recipes)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("recipe_shop")


## 필터 분배기 (§62): 게임과 시간을 멈춘다
func open_router(router: Node) -> void:
	_close_inventory()
	_router.open(router as Router)
	_center(_router)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("router")


## 비행선 정류장 복구 창 (§89)
func open_sky_station() -> void:
	_close_inventory()
	_sky_station.open()
	_center(_sky_station)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("sky_station")


## 하늘시장 가판대 창 (§84~§88)
func open_sky_market() -> void:
	_close_inventory()
	_sky_market.open()
	_center(_sky_market)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("sky_market")


## 상점 NPC 대화 창 (사용자 요청): 게임과 시간을 멈춘다
func open_dialog(npc: Node) -> void:
	_close_inventory()
	_dialog.open(npc)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("dialog")


## 대화에서 고른 일: 상점 창(사기·팔기·기계) 또는 대장간 강화 창을 연다
func _on_dialog_chosen(action: String) -> void:
	_close_panels()
	if action.begins_with("mine:"):  # 광산 엘리베이터: 고른 층으로
		Events.mine_requested.emit(int(action.trim_prefix("mine:")))
		return
	match action:
		"smith":
			open_blacksmith()
		"buy", "sell", "machine":
			_open_shop(action)


## 비행: 화면을 잠깐 어둡게 했다 밝힌다
func _flash() -> void:
	_fade.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.2)
	tween.tween_property(_fade, "modulate:a", 0.0, 0.6)


## 하루가 끝났을 때: 오늘 번 돈이 있으면 판매 수익 요약(§99), 그다음 밤새 만든 것이 있으면 야간 생산 요약(§98).
## 두 창은 섞지 않고 차례로 띄운다 (게임·시간 멈춤).
func _on_day_ended(report: Dictionary) -> void:
	var night: Dictionary = report.get("night_production", {})
	_pending_night = night if NightSummaryPanel.has_content(night) else {}
	_pending_night_day = GameState.day
	var sales: Dictionary = report.get("sales", {})
	if int(sales.get("total", 0)) <= 0:
		_show_pending_night()
		return
	_summary.open(int(report.get("from_day", GameState.day - 1)), sales)
	_center(_summary)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("summary")


func _on_sales_closed() -> void:
	_close_panels()
	_show_pending_night()


func _show_pending_night() -> void:
	if _pending_night.is_empty():
		return
	var night := _pending_night
	_pending_night = {}
	_night.open(_pending_night_day, night)
	_center(_night)
	_prompt_box.hide()
	_crop_info.suppressed = true
	_pause_for("night_summary")


## 가방: 시간은 계속 흐르고, 플레이어 이동·도구 사용만 막는다
func open_inventory() -> void:
	_inventory.open()
	_center(_inventory)
	_prompt_box.hide()
	_crop_info.suppressed = true
	GameState.set_input_locked("inventory", true)


func _close_inventory() -> void:
	_inventory.hide()
	GameState.set_input_locked("inventory", false)


## 게임(플레이어·월드)과 시계를 함께 멈춘다
func _pause_for(reason: String) -> void:
	get_tree().paused = true
	GameState.set_time_paused(reason, true)


func _close_panels() -> void:
	_close_inventory()
	_shop.hide()
	_build.hide()
	_menu.hide()
	_bin_panel.hide()
	_summary.hide()
	_night.hide()
	GameState.set_time_paused("night_summary", false)
	_smith.hide()
	_recipes.hide()
	_router.hide()
	_sky_station.hide()
	_sky_market.hide()
	_dialog.hide()
	_compost.hide()
	_warehouse.hide()
	_processor.hide()
	_generator.hide()
	GameState.set_time_paused("processor", false)
	GameState.set_time_paused("generator", false)
	GameState.set_time_paused("blacksmith", false)
	GameState.set_time_paused("recipe_shop", false)
	GameState.set_time_paused("router", false)
	GameState.set_time_paused("sky_station", false)
	GameState.set_time_paused("sky_market", false)
	GameState.set_time_paused("dialog", false)
	GameState.set_time_paused("compost_bin", false)
	GameState.set_time_paused("warehouse", false)
	GameState.set_time_paused("shipping_bin", false)
	GameState.set_time_paused("summary", false)
	_prompt_box.visible = _prompt.text != "" and not _build_hint.visible
	_crop_info.suppressed = false
	get_tree().paused = false
	GameState.set_time_paused("shop", false)
	GameState.set_time_paused("build_menu", false)
	GameState.set_time_paused("menu", false)


# ---------- 표시 갱신

func _on_time_changed(day: int, minutes: int) -> void:
	_day_label.text = "%s (%s) · %s" % [Calendar.date_text(day), WEEKDAYS[(day - 1) % 7], Weather.name_of(GameState.weather)]
	_time_label.text = GameState.format_clock(minutes)
	_time_label.add_theme_color_override("font_color", ACCENT if GameState.is_day_ending_soon() else TEXT)
	_clock_icon.texture = _icon(1 if minutes >= 18 * 60 else 0)


func _on_money_changed(amount: int) -> void:
	_money_label.text = "%d G" % amount


func _on_prompt_changed(text: String) -> void:
	# "[E] 잠자기" 처럼 오면 [E] 는 키 모양으로 따로 그린다
	_prompt.text = text.trim_prefix("[E]").strip_edges()
	_prompt_box.visible = text != "" and not (_inventory.visible or _shop.visible or _build.visible or _build_hint.visible)


func _on_build_hint(text: String) -> void:
	_build_hint_label.text = text
	_build_hint.visible = text != ""
	_prompt_box.visible = _prompt.text != "" and text == ""


## 하루 마감 시작: 열린 창을 모두 닫는다
func _on_day_ending(reason: String) -> void:
	_end_reason = reason
	_close_panels()


func _on_day_started(day: int) -> void:
	_fade.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.3)
	tween.tween_property(_fade, "modulate:a", 0.0, 0.8)
	var date := Calendar.date_text(day)
	var weather := Weather.morning_text(GameState.weather)
	if day > 1 and Calendar.day_in_season(day) == 1:
		show_toast("%s이 시작됐어요! 계절에 맞지 않는 작물은 시들었어요. %s" % [Calendar.season_name(Calendar.season_of(day)), weather])
	elif _end_reason == "time_up":
		show_toast("하루가 끝나 집으로 돌아왔어요. %s 아침, %s" % [date, weather])
	else:
		show_toast("%s 아침이 밝았어요. %s" % [date, weather])
	_end_reason = ""


func _on_day_ending_soon(seconds_left: float) -> void:
	_time_label.add_theme_color_override("font_color", ACCENT)
	show_toast("하루가 %d분 남았어요. 슬슬 마무리해요." % maxi(1, roundi(seconds_left / 60.0)))


func show_toast(text: String) -> void:
	_toast.text = text
	_toast.show()
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.6)
	_toast_tween.tween_callback(_toast.hide)


# ---------- 만들기 도우미

func _build_info() -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(16))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	_day_label = Label.new()
	_day_label.add_theme_color_override("font_color", TEXT_SOFT)
	_day_label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_day_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_day_label)

	_clock_icon = _icon_rect(0)
	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", Art.FONT_SIZE)
	_time_label.add_theme_font_override("font", Art.pixel_font(true))
	box.add_child(_icon_row(_clock_icon, _time_label))

	_money_label = Label.new()
	_money_label.add_theme_color_override("font_color", Color("c98a2e"))
	box.add_child(_icon_row(_icon_rect(2), _money_label))

	# 지역 전력 (§75): 발전기나 전기 시설이 있을 때만 보인다
	_power_label = Label.new()
	_power_label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_power_label.hide()
	box.add_child(_power_label)
	# 지역 물통 (§14): 물탱크나 스프링클러가 있을 때만 보인다
	_water_label = Label.new()
	_water_label.add_theme_font_size_override("font_size", Art.FONT_SIZE_SMALL)
	_water_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_water_label.hide()
	box.add_child(_water_label)
	Events.power_changed.connect(_update_power)
	Events.game_loaded.connect(_update_power)
	Events.time_changed.connect(func(_d: int, _m: int) -> void: _update_power())  # 전기 양은 시간에 따라 계속 바뀐다
	panel.custom_minimum_size = Vector2(230, 0)
	_place(panel, Vector2(1.0, 0.0), Vector2(-16, 16), Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)


## "전기 350 / 600" (지역 전기 통에 남은 전기 / 통 크기). 비어 있으면 빨간색. 발전기가 없으면 숨김
func _update_power() -> void:
	var world := get_tree().get_first_node_in_group("farm_world") as FarmWorld
	if world == null or not is_instance_valid(world.build):
		return
	var st := world.build.power_status()
	_power_label.visible = st.capacity > 0.0 or st.demand > 0
	var empty: bool = st.stored < 1.0
	_power_label.text = "전기 %d / %d%s" % [floori(st.stored), roundi(st.capacity), " 없음!" if empty else ""]
	_power_label.add_theme_color_override("font_color", Color("c0503a") if empty else TEXT_SOFT)
	# "물 92 / 200" (지역 물통). 스프링클러는 있는데 물탱크가 없거나 비어 있으면 빨간 "없음!"
	var ws := world.build.water_status()
	_water_label.visible = ws.capacity > 0.0 or ws.sprinklers > 0
	var dry: bool = ws.stored < 1.0
	_water_label.text = "물 %d / %d%s" % [floori(ws.stored), roundi(ws.capacity), " 없음!" if dry else ""]
	_water_label.add_theme_color_override("font_color", Color("c0503a") if dry else TEXT_SOFT)


func _icon_row(icon: Control, label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(icon)
	row.add_child(label)
	return row


## ui_icons.png: 0 해, 1 달, 2 동전, 3 말풍선
func _icon(index: int) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = Art.UI_ICONS
	t.region = Rect2(index * Art.TILE, 0, Art.TILE, Art.TILE)
	return t


func _icon_rect(index: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _icon(index)
	r.custom_minimum_size = Vector2(32, 32)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


## 상호작용 안내: [E 키 모양] + 설명
func _build_prompt() -> void:
	_prompt_box = PanelContainer.new()
	_prompt_box.add_theme_stylebox_override("panel", _panel_style(12))
	_prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_prompt_box.add_child(row)
	var key := Label.new()
	key.text = "E"
	key.add_theme_font_override("font", Art.pixel_font(true))
	key.add_theme_stylebox_override("normal", _key_style())
	row.add_child(key)
	_prompt = Label.new()
	_prompt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_prompt)
	_place(_prompt_box, Vector2(0.5, 1.0), Vector2(0, -98), Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BEGIN)


func _key_style() -> StyleBoxTexture:
	var sb := Art.box(Art.UI_KEY, 4, 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 8
	return sb


func _make_float_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_stylebox_override("normal", _panel_style(14))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## 창 내용이 다 채워진 다음 프레임에 크기를 다시 재고 화면 한가운데에 맞춘다
## (내용이 늘면서 한쪽으로만 커져 화면 밖으로 나가는 것을 막는다). 창은 화면 가운데(0.5, 0.5)에 붙어 있어야 한다.
func _center(panel: Control) -> void:
	await get_tree().process_frame
	if not panel.visible:
		return
	panel.reset_size()
	_recenter(panel)


## 화면 가운데(0.5, 0.5)에 붙은 창을 지금 크기 그대로 한가운데로 옮긴다.
## 글자 배치가 끝나 창이 나중에 커질 때도 resized 로 다시 불린다.
## 위치만 옮기므로(크기는 그대로) resized 가 다시 일어나지 않는다.
func _recenter(panel: Control) -> void:
	var target := ((panel.get_parent_area_size() - panel.size) / 2.0).floor()
	if panel.position != target:
		panel.position = target


## anchor 지점에 offset만큼 떨어뜨려 붙인다. 크기는 내용에 맞춰 grow 방향으로 커진다.
func _place(ctrl: Control, anchor: Vector2, pos: Vector2, grow_h: Control.GrowDirection, grow_v: Control.GrowDirection) -> void:
	ctrl.anchor_left = anchor.x
	ctrl.anchor_right = anchor.x
	ctrl.anchor_top = anchor.y
	ctrl.anchor_bottom = anchor.y
	ctrl.offset_left = pos.x
	ctrl.offset_right = pos.x
	ctrl.offset_top = pos.y
	ctrl.offset_bottom = pos.y
	ctrl.grow_horizontal = grow_h
	ctrl.grow_vertical = grow_v
	_root.add_child(ctrl)
	if anchor == Vector2(0.5, 0.5):
		ctrl.resized.connect(_recenter.bind(ctrl))


static func _panel_style(margin: float) -> StyleBoxTexture:
	return Art.box(Art.UI_PANEL, 5, margin)


static func _button_style(texture: Texture2D) -> StyleBoxTexture:
	var sb := Art.box(texture, 4, 0)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 12
	return sb


## 게임 UI 공통 테마 (시작 화면도 같은 모양을 쓴다)
static func ui_theme() -> Theme:
	return _make_theme()


static func _make_theme() -> Theme:
	var theme := Theme.new()
	# 둥근 한글 도트 폰트 Neo둥근모 (OFL). 16px 의 배수 크기에서 가장 선명하다.
	theme.default_font = Art.pixel_font()
	theme.default_font_size = Art.FONT_SIZE
	theme.set_stylebox("panel", "PanelContainer", _panel_style(18))
	theme.set_color("font_color", "Label", TEXT)
	theme.set_stylebox("normal", "Button", _button_style(Art.UI_BUTTON))
	theme.set_stylebox("hover", "Button", _button_style(Art.UI_BUTTON_HOVER))
	theme.set_stylebox("pressed", "Button", _button_style(Art.UI_BUTTON_PRESSED))
	theme.set_stylebox("disabled", "Button", _button_style(Art.UI_BUTTON_DISABLED))
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", TEXT)
	theme.set_color("font_pressed_color", "Button", TEXT)
	theme.set_color("font_disabled_color", "Button", Color(TEXT, 0.35))
	theme.set_font_size("font_size", "Button", Art.FONT_SIZE)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "TooltipPanel", _panel_style(14))
	return theme
