extends Node
## 5단계 전체 플레이 검증 봇 (스토리 MQ01~MQ20). 새 게임에서 퀘스트 상태를 건드리지 않고, 플레이어 입력이 부르는 것과
## 같은 함수(도구 사용 _use_selected 와 같은 순서, [E] interact, 대화·상점·건설 버튼 함수)만 불러 끝까지 진행한다.
## 행동마다 실제 시간을 흘린다: 도구 1번 = tool_cooldown(0.5초), 걷기 = 거리 / 68px/초 × 1.3 (돌아가는 길), 창 조작 몇 초.
## 그래서 게임 시계·하루 마감·작물 성장·용광로·가공기·컨베이어가 실제 규칙대로 돌아간다. 하루는 일이 끝나면 집에서 잔다.
##
## 실행: Godot --headless --path . res://scenes/tests/playthrough.tscn -- --season=spring --plot=24 --seed=1
##   season: 시작 계절 (새 게임은 봄 1일. 여름·가을·겨울은 '그 계절에 처음부터 진행하면' 가정 시나리오)
##   plot: 봇이 매일 가꾸는 밭 칸 수, seed: 난수 (수확량·품질·광산 바위·날씨)
## 결과: user://playthrough_<season>_<plot>_<seed>.json (퀘스트별 완료 시점 · 수입/지출 장부 · 막힌 곳) + 콘솔 요약
##
## 이 봇은 '그럴듯한 보통 플레이어' 한 명의 전략일 뿐이다 (최적 경로가 아님). 숫자는 이 전략 기준의 측정값.

const TILE := 16.0
const WALK_SPEED := 68.0          # Player.SPEED (px/초)
const DETOUR := 1.3               # 직선 거리 → 실제 걷는 거리
const TOOL_TIME := 0.5            # data/player.json tool_cooldown
const UI_TIME := 3.0              # 창 열고 버튼 누르고 닫기
const MAX_DAYS := 140
const RESERVE_CROPS := 3          # MQ07 납품용으로 남겨 둘 작물 수

var season := "spring"
var plot_size := 24
var rng_seed := 1
## --checkpoints: 정한 순간마다 저장 파일을 user://ckpt_<이름>.json 으로 복사 (재시작 검증용, restart_check.tscn 이 하나씩 불러 봄)
var checkpoints := false
## --day=N: 시작 날짜 (1년 중 N일째, 계절 시작이 아닌 날로 시작해 특정 퀘스트를 특정 계절에 맞추는 가정 시나리오)
var start_day_override := 0
## --keep-support: MQ17 진행 중에는 받은 밀을 팔지 않는 플레이어 (기본 봇은 작물을 모두 출하함에 넣는다)
var keep_support := false
var _ckpt_done := {}
var _last_era := ""

var world: FarmWorld
var hud: HUD
var qm: QuestManager
var inv: Inventory
var player: Player

var pos := Vector2.ZERO           # 봇이 지금 있는 곳 (걷기 시간 계산용)
var active_seconds := 0.0         # 봇이 실제로 움직인 시간 합 (현실 플레이 시간 하한 추정)
var plot: Array[Vector2i] = []
## 가공 재료 전용 밭 (MQ16 뒤에 새 땅 8칸)
var recipe_plot: Array[Vector2i] = []
var factory_origin := Vector2i(-1, -1)
var furnace: Furnace
var processor: Processor
var warehouse: Warehouse

## 장부: 분류 → G (수입 +, 지출 −)
var ledger := {}
var timeline: Array[Dictionary] = []
var _rewarded := {}
var notes: Array[String] = []
var stuck := ""
var counters := {"tool_uses": 0, "rocks_broken": 0, "mine_floors_entered": 0, "days_slept": 0, "crops_harvested": 0, "seeds_bought": 0}
var _day_spent := 0.0
## 날마다: 날짜 · 따라가는 퀘스트 · 막힌 이유 · 돈 · 그날 봇 시간
var daily: Array[Dictionary] = []


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--season="):
			season = a.trim_prefix("--season=")
		elif a.begins_with("--plot="):
			plot_size = int(a.trim_prefix("--plot="))
		elif a.begins_with("--seed="):
			rng_seed = int(a.trim_prefix("--seed="))
		elif a.begins_with("--day="):
			start_day_override = int(a.trim_prefix("--day="))
		elif a == "--keep-support":
			keep_support = true
		elif a == "--checkpoints":
			checkpoints = true
	seed(rng_seed)
	SaveManager.load_on_start = false
	SaveManager.slot_path = "user://playthrough_save_%s_%d_%d.json" % [season, plot_size, rng_seed]
	Weather.forced = ""
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().physics_frame
	world = main.get_node("FarmWorld")
	hud = main.get_node("HUD")
	qm = world.quests
	inv = GameState.inventory
	player = world.player
	world.day_cycle.rng.seed = rng_seed
	world.mine.rng.seed = rng_seed
	world.obstacles.rng.seed = rng_seed
	for t: Townsfolk in world.townsfolk:
		t.process_mode = Node.PROCESS_MODE_DISABLED
	var offset: int = ["spring", "summer", "autumn", "winter"].find(season) * 28
	if start_day_override > 0:
		offset = start_day_override - 1
		season = "day%d" % start_day_override
	if offset > 0:
		# 가정 시나리오: 같은 새 게임을 그 계절 1일에 시작 (날짜만 옮김, 다른 상태는 새 게임 그대로)
		GameState.day = 1 + offset
		world.farm.change_season(Calendar.season_of(GameState.day))
	pos = player.global_position
	_choose_plot()
	var start_money := GameState.money
	_note("시작: %s %d일, 돈 %d G, 밭 %d칸" % [Calendar.season_name(Calendar.season_of(GameState.day)), Calendar.day_in_season(GameState.day), start_money, plot.size()])
	await _run()
	_finish(start_money)


# ---------- 시간 · 걷기

func _spend(seconds: float) -> void:
	# 시간이 멈춘 창이 열려 있으면 그만큼은 시계가 안 간다 (실제 게임과 같음). 봇은 창을 닫은 상태에서만 걷고 일한다
	active_seconds += seconds
	_day_spent += seconds
	var left := seconds
	while left > 0.0:
		var step := minf(left, 5.0)
		GameState.advance_time(step)
		left -= step
		if hud._night.visible or hud._summary.visible:
			hud._close_panels()


func _walk_to(target: Vector2) -> void:
	var d := pos.distance_to(target) * DETOUR
	pos = target
	_spend(d / WALK_SPEED)


func _tool(cell: Vector2i, slot: int) -> void:
	## Player._use_selected 와 같은 순서 (수확 → 시설 → 장애물·광산 바위 → 물뿌리개 / 괭이·씨앗)
	_walk_to(world.cell_center(cell) + Vector2(0, TILE))
	counters.tool_uses += 1
	_spend(TOOL_TIME)
	GameState.select_slot(slot)
	var item := inv.item_at(slot)
	if player._try_harvest(cell):
		counters.crops_harvested += 1
		return
	var obj := world.build.object_at(cell)
	if obj and obj.has_method("use_held_item") and obj.use_held_item(inv, slot):
		return
	if world.obstacles.try_clear(cell, item) or world.mine.rocks.try_clear(cell, item):
		return
	if item == null:
		return
	if item.tool_type == "watering_can":
		WateringCan.use(world, cell, inv, slot, Vector2i.UP, 1)
		return
	if world.farm.use_item(cell, item, Vector2i.UP, 1) and item.kind in [ItemDef.Kind.SEED, ItemDef.Kind.FERTILIZER]:
		inv.remove_at(slot, 1)


func _slot_of(pred: Callable) -> int:
	for i in inv.size():
		var it := inv.item_at(i)
		if it and pred.call(it):
			return i
	return -1


func _tool_slot(tool_type: String) -> int:
	return _slot_of(func(it: ItemDef) -> bool: return it.kind == ItemDef.Kind.TOOL and it.tool_type == tool_type)


func _building(cls: String, room := "") -> Node2D:
	for b: Interactable in world.buildings:
		if b.get_script() and b.get_script().get_global_name() == cls and (room == "" or ("room_id" in b and b.room_id == room)):
			return b
	return null


# ---------- 장부

func _money_action(category: String, action: Callable) -> Variant:
	var before := GameState.money
	var quest_before := _quest_money_now()
	var result: Variant = await action.call()
	var delta := GameState.money - before
	var quest_part := _quest_money_now() - quest_before
	_book(category, delta - quest_part)  # 퀘스트 보상은 _track_quests 가 따로 적는다
	_track_quests()
	return result


## 지금까지 받은 퀘스트 보상 돈 합 (rewarded 상태 기준)
func _quest_money_now() -> int:
	var total := 0
	for q: Dictionary in QuestManager.quest_defs():
		if qm.state_of(q.id) == QuestManager.REWARDED:
			total += int(q.get("rewards", {}).get("money", 0))
	return total


func _book(category: String, amount: int) -> void:
	if amount != 0:
		ledger[category] = int(ledger.get(category, 0)) + amount


func _ckpt(name: String) -> void:
	if not checkpoints or _ckpt_done.has(name):
		return
	_ckpt_done[name] = true
	world.save_manager.save_game("manual")
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SaveManager.slot_path), ProjectSettings.globalize_path("user://ckpt_%s.json" % name))
	_note("저장 지점: %s" % name)


func _track_quests() -> void:
	if _last_era != "" and qm.era != _last_era:
		_ckpt("era_" + qm.era)
	_last_era = qm.era
	if qm.state_of("MQ02") == QuestManager.ACTIVE and int(qm.progress_of("MQ02")[0]) > 0:
		_ckpt("quest_in_progress")
	for q: Dictionary in QuestManager.quest_defs():
		if qm.state_of(q.id) == QuestManager.REWARDED and not _rewarded.has(q.id):
			_rewarded[q.id] = true
			_book("퀘스트 보상", int(q.get("rewards", {}).get("money", 0)))
			timeline.append({"quest": q.id, "title": q.title, "game_day": GameState.day - _start_day(), "date": "%s %d일 %s" % [Calendar.season_name(Calendar.season_of(GameState.day)), Calendar.day_in_season(GameState.day), GameState.format_clock(GameState.minutes)],
				"active_minutes": snappedf(active_seconds / 60.0, 0.1), "money": GameState.money, "era": qm.era})
			print("  [%s] %s 완료 — %d일째 · 봇 시간 %.0f분 · 돈 %d G" % [q.id, q.title, GameState.day - _start_day() + 1, active_seconds / 60.0, GameState.money])
			if q.id in ["MQ07", "MQ12", "MQ20"]:
				_ckpt("rewarded_" + str(q.id))


func _start_day() -> int:
	if start_day_override > 0:
		return start_day_override
	return 1 + ["spring", "summer", "autumn", "winter"].find(season) * 28


func _note(text: String) -> void:
	notes.append("[%d일째] %s" % [GameState.day - _start_day() + 1, text])
	print("  · ", notes[-1])


# ---------- 하루

func _run() -> void:
	var last_progress_day := GameState.day
	var last_count := 0
	while GameState.day - _start_day() < MAX_DAYS:
		var today := GameState.day
		_day_spent = 0.0
		await _morning_farm()
		if GameState.day != today:
			continue
		await _quest_work()
		if _rewarded.size() >= 20:
			break
		if GameState.day == today:
			await _gather()
		if GameState.day == today:
			await _evening()
		_track_quests()
		daily.append({"day": today - _start_day() + 1, "quest": qm.tracked().get("id", "-"), "state": _why_stuck() if not qm.tracked().is_empty() else "", "money": GameState.money, "bot_seconds": roundi(_day_spent)})
		if _rewarded.size() != last_count:
			last_count = _rewarded.size()
			last_progress_day = GameState.day
		elif GameState.day - last_progress_day > 40:
			stuck = "%s 에서 40일 동안 진행 없음 (%s)" % [qm.tracked().get("id", "?"), _why_stuck()]
			_note("막힘: " + stuck)
			break


func _time_left() -> float:
	return GameState.seconds_left()


## 아침: 다 자란 작물 거두기 → 물 주기 → 빈 칸에 씨앗
func _morning_farm() -> void:
	var today := GameState.day
	var outdoor_ok := not Calendar.season_of(GameState.day) in ["winter"]
	if _recipe_seed() != "" and recipe_plot.is_empty():
		recipe_plot = _new_land(8)
		_note("가공 재료 밭 8칸 (%s)" % _recipe_seed())
	var fields: Array[Vector2i] = plot + recipe_plot
	for c in fields:
		if GameState.day != today:
			return
		if world.farm.mature_produce_at(c) != "":
			var before := inv.count_of(world.farm.mature_produce_at(c))
			_tool(c, _tool_slot("hoe"))
			if inv.count_of(world.farm.mature_produce_at(c)) == before and world.farm.mature_produce_at(c) != "":
				break  # 가방이 가득
	if not outdoor_ok:
		return
	# 씨앗 사기 (빈 칸 수만큼, 돈이 되는 만큼)
	var empty := fields.filter(func(c: Vector2i) -> bool: var t := world.farm.get_tile(c); return t == null or not t.has_crop())
	var seed_id := _best_seed()
	# 가공 재료 작물 (MQ16 뒤): 밭 앞 8칸
	var rs := _recipe_seed()
	if rs != "":
		var need_r := empty.filter(func(c: Vector2i) -> bool: return c in recipe_plot).size() - inv.count_of(rs)
		if need_r > 0:
			await _buy_at_store(rs, need_r)
	if seed_id != "" and not empty.is_empty():
		var have := inv.count_of(seed_id)
		var price := ItemDB.get_item(seed_id).buy_price
		var want := mini(empty.filter(func(c: Vector2i) -> bool: return not c in recipe_plot).size() - have, int((GameState.money - _money_reserve()) / maxf(1, price)))
		if want > 0:
			await _buy_at_store(seed_id, want)
	for c in empty:
		if GameState.day != today or _time_left() < 60:
			return
		var t := world.farm.get_tile(c)
		if t == null:
			_tool(c, _tool_slot("hoe"))
			t = world.farm.get_tile(c)
		var want_seed := _recipe_seed() if c in recipe_plot else ""
		if c in recipe_plot and want_seed == "":
			continue
		var s := _slot_of(func(it: ItemDef) -> bool: return it.id == want_seed) if want_seed != "" else -1
		if s < 0:
			s = _slot_of(func(it: ItemDef) -> bool: return it.kind == ItemDef.Kind.SEED and Calendar.in_season_for_shop(it, GameState.day) and it.grow_days < 28 - Calendar.day_in_season(GameState.day) + 1)
		if t != null and s >= 0:
			_tool(c, s)
	# 물 주기
	for c in fields:
		if GameState.day != today or _time_left() < 40:
			return
		var t := world.farm.get_tile(c)
		if t and t.has_crop() and not t.watered:
			var can := _tool_slot("watering_can")
			if WateringCan.water_left(inv, can) <= 0:
				await _refill()
			_tool(c, can)


func _refill() -> void:
	var well := _building("Well")
	_walk_to(well.interact_point())
	_spend(1.0)
	well.interact(player)


## 남겨 둘 돈: 다음 퀘스트에 꼭 필요한 큰 지출 (씨앗을 사느라 못 사는 일이 없게)
func _money_reserve() -> int:
	var id: String = qm.tracked().get("id", "")
	return {"MQ13": 1000, "MQ14": 500, "MQ16": 500, "MQ17": 450, "MQ18": 1400, "MQ19": 250}.get(id, 0)


## 이번 계절에 남은 날 안에 자라고 칸당 하루 이익이 가장 큰 씨앗 (상점에 있는 것)
func _best_seed() -> String:
	var best := ""
	var best_v := -INF
	var left := 28 - Calendar.day_in_season(GameState.day) + 1
	for it: ItemDef in ItemDB.shop_items():
		if it.kind != ItemDef.Kind.SEED or it.shop != "general" or not Calendar.in_season_for_shop(it, GameState.day):
			continue
		if it.grow_days >= left:
			continue
		var crop := ItemDB.get_item(it.grows)
		var y := (it.yield_min + it.yield_max) / 2.0
		var harvests := 1
		if it.regrow_days > 0:
			harvests = 1 + int((left - 1 - it.grow_days) / it.regrow_days)
		var v := (y * crop.sell_price * harvests - it.buy_price) / float(left)
		if v > best_v:
			best_v = v
			best = it.id
	return best


func _evening() -> void:
	await _ship_crops()
	# 집에 가서 잔다
	_walk_to(world.home_position)
	await _money_action("작물 판매 (출하함 정산)", func() -> void:
		counters.days_slept += 1
		GameState.sleep()
		await get_tree().process_frame
		hud._close_panels())
	pos = player.global_position


func _ship_crops() -> void:
	var keep := {}
	var keep_n := RESERVE_CROPS if qm.state_of("MQ07") in [QuestManager.LOCKED, QuestManager.ACTIVE] else 0
	for item_id: String in _recipe_inputs_needed():
		keep[item_id] = _recipe_inputs_needed()[item_id]
	if keep_support and qm.state_of("MQ17") == QuestManager.ACTIVE:
		keep["wheat"] = int(keep.get("wheat", 0)) + 4
	var bin := world.shipping_bin
	var shipped := false
	for st: Dictionary in inv.stacks():
		var it := ItemDB.get_item(st.id)
		if it.kind != ItemDef.Kind.CROP:
			continue
		var n := inv.count_of(st.id, st.quality)
		if keep.has(st.id):
			var k := mini(n, int(keep[st.id]))
			keep[st.id] = int(keep[st.id]) - k
			n -= k
		elif keep_n > 0:
			var k2 := mini(n, keep_n)
			keep_n -= k2
			n -= k2
		if n > 0:
			if not shipped:
				_walk_to(bin.interact_point())
				_spend(UI_TIME)
				shipped = true
			bin.deposit(inv, st.id, st.quality, n)


# ---------- 상점 · 대화

func _enter(room: String) -> void:
	var b := _building("Blacksmith") if room == "smith" else _building("ShopBuilding", room)
	_walk_to(b.interact_point())
	b.interact(player)
	await get_tree().process_frame
	pos = player.global_position
	_walk_to(world.interiors[room].npc.interact_point())


func _leave() -> void:
	hud._close_panels()
	world.exit_interior()
	await get_tree().process_frame
	pos = player.global_position


func _talk(room: String) -> void:
	world.interiors[room].npc.interact(player)
	_spend(UI_TIME)


func _buy_at_store(item_id: String, qty: int) -> void:
	await _enter("store")
	await _money_action("씨앗 구매", func() -> void:
		_talk("store")
		hud._dialog.choose("buy")
		var before := inv.count_of(item_id)
		for i in qty:
			hud._shop._buy(item_id, 1)
		counters.seeds_bought += inv.count_of(item_id) - before
		_spend(UI_TIME))
	await _leave()


func _buy_machine(room: String, mode: String, item_id: String, qty: int, category: String) -> bool:
	await _enter(room)
	var before := inv.count_of(item_id)
	await _money_action(category, func() -> void:
		_talk(room)
		hud._dialog.choose(mode)
		hud._shop._buy(item_id, qty)
		_spend(UI_TIME))
	await _leave()
	return inv.count_of(item_id) >= before + qty


func _donate_at(room: String, pid: String) -> void:
	await _enter(room)
	for key: String in ["wood", "stone", "copper_bar", "iron_bar", "money"]:
		await _money_action("복구 프로젝트 (돈)", func() -> void:
			_talk(room)
			hud._dialog.choose("project:%s:%s" % [pid, key]))
		if not qm.project_done(pid) and not qm.project_given.get(pid, {}).is_empty():
			hud._close_panels()
			_ckpt("project_partial_" + pid)
	await _leave()


# ---------- 퀘스트별 행동 (퀘스트 상태는 건드리지 않는다)

func _quest_work() -> void:
	var today := GameState.day
	var q := qm.tracked()
	if q.is_empty():
		return
	match str(q.id):
		"MQ01":
			var sign := world.objects.get_children().filter(func(n: Node) -> bool: return n is InfoSign)[0] as InfoSign
			_walk_to(sign.interact_point())
			sign.interact(player)
			_spend(UI_TIME)
			hud._close_panels()
			var plaza := Vector2i(int(QuestManager.data().areas.plaza.min_x) + 2, world.world_to_cell(world.home_position).y)
			_walk_to(world.cell_center(plaza))
			player.global_position = world.cell_center(plaza)
			await get_tree().process_frame
			await get_tree().process_frame
			player.global_position = world.home_position
		"MQ02":
			await _clear_types(["weed", "branch"], 30)
		"MQ03":
			# 밭 갈기는 MQ03 을 받은 뒤에 간 칸만 센다 → 밭을 미리 다 갈았으면 새 땅을 갈아야 한다 (5단계 발견)
			var left := 5 - int(qm.progress_of("MQ03")[0])
			if left > 0:
				_note("MQ03: 이미 간 밭은 세지 않아 새 땅 %d칸을 감" % left)
				for c: Vector2i in _new_land(left):
					var ob := world.obstacles.obstacle_at(c)
					if ob:
						continue
					_tool(c, _tool_slot("hoe"))
		"MQ06", "MQ04", "MQ05":
			if q.id == "MQ04" and qm.progress_of("MQ04")[1] < 1:
				# 물뿌리개가 덜 찼을 때 우물에서 채우기
				await _refill()
		"MQ07":
			await _enter("store")
			_talk("store")
			if qm.deliver_have("kind:crop") >= 3:
				await _money_action("기타", func() -> void: hud._dialog.choose("quest:MQ07:1"))
			await _leave()
		"MQ08":
			if inv.count_of("wood") >= 1 or inv.count_of("stone") >= 1:
				await _donate_at("store", "workbench_repair")
		"MQ09":
			await _enter("smith")
			_talk("smith")
			await _leave()
			await _clear_types(["coal_pile"], 6)
			if inv.count_of("coal") >= 3:
				await _enter("smith")
				_talk("smith")
				hud._dialog.choose("quest:MQ09:1")
				await _leave()
		"MQ10":
			var front := world.cell_center(Vector2i(85, 6))
			_walk_to(front)
			player.global_position = front
			await get_tree().process_frame
			await get_tree().process_frame
			player.global_position = world.home_position
			await _clear_types(["mine_debris"], 5)
		"MQ11":
			await _donate_at("smith", "mine_repair")
		"MQ12":
			await _mine(1, {"copper_ore": 6})
		"MQ13":
			await _smelt_quest()
		"MQ14":
			if inv.count_of("copper_bar") >= 3 and GameState.money >= 500:
				await _enter("smith")
				await _money_action("도구 강화", func() -> void:
					_talk("smith")
					hud._dialog.choose("smith")
					ToolUpgrade.apply(inv, _tool_slot("hoe"))
					_spend(UI_TIME))
				await _leave()
			else:
				await _smelt_bars(3)
		"MQ15":
			await _mine(5, {})
		"MQ16":
			if inv.count_of("copper_bar") < 8 and not qm.project_done("mechanical_research") and int(qm.project_rows("mechanical_research")[0].given) < 8:
				await _smelt_bars(8 - int(qm.project_rows("mechanical_research")[0].given))
			if inv.count_of("copper_bar") > 0 or GameState.money >= 500:
				await _donate_at("machine", "mechanical_research")
			if qm.project_done("mechanical_research"):
				await _enter("machine")
				_talk("machine")
				await _leave()
		"MQ17":
			await _processing_quest(false)
		"MQ18", "MQ19", "MQ20":
			await _processing_quest(true)
	if GameState.day == today:
		_track_quests()


## 밭 바깥의 갈 수 있는 빈 땅 n 칸 (장애물 없음)
func _new_land(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return world.cell_center(a).distance_squared_to(world.home_position) < world.cell_center(b).distance_squared_to(world.home_position))
	for c: Vector2i in cells:
		if out.size() >= n:
			break
		if c in plot or world.farm.tiles.has(c) or world.obstacles.obstacle_at(c) or world.build.is_occupied(c):
			continue
		if factory_origin != Vector2i(-1, -1) and Rect2i(factory_origin - Vector2i.ONE, Vector2i(14, 8)).has_point(c):
			continue  # 공장 자리는 비워 둔다
		out.append(c)
	return out


func _why_stuck() -> String:
	var q := qm.tracked()
	var parts: Array[String] = []
	for i in q.get("objectives", []).size():
		parts.append(qm.objective_line(q, i))
	return "%s · 돈 %d · 나무 %d · 돌 %d · 구리광석 %d · 석탄 %d · 주괴 %d" % [" / ".join(parts), GameState.money, inv.count_of("wood"), inv.count_of("stone"), inv.count_of("copper_ore"), inv.count_of("coal"), inv.count_of("copper_bar")]


# ---------- 자원 모으기

## 지금 퀘스트에 모자란 나무·돌 (앞으로 필요한 시설 재료 포함)
func _need() -> Dictionary:
	var id: String = qm.tracked().get("id", "")
	var need := {}
	match id:
		"MQ08": need = {"wood": 15, "stone": 10}
		"MQ09", "MQ10", "MQ11": need = {"wood": 10, "stone": 10}
		"MQ12", "MQ13": need = {"stone": 30}
		"MQ16", "MQ17": need = {"wood": 50, "stone": 30}
		"MQ18": need = {"wood": 80, "stone": 40}
		"MQ19": need = {"wood": 10, "stone": 5}
	if id == "MQ08":
		for row: Dictionary in qm.project_rows("workbench_repair"):
			need[row.key] = int(row.need) - int(row.given)
	if id == "MQ11":
		for row: Dictionary in qm.project_rows("mine_repair"):
			need[row.key] = int(row.need) - int(row.given)
	var out := {}
	for k: String in need:
		if inv.count_of(k) < int(need[k]):
			out[k] = int(need[k]) - inv.count_of(k)
	return out


func _gather() -> void:
	var need := _need()
	if need.is_empty():
		return
	if need.has("wood"):
		await _clear_types(["big_stump", "stump", "branch"], 60)
	if need.has("stone") and _time_left() > 120:
		await _clear_types(["big_rock", "small_rock"], 60)
	need = _need()
	if need.has("stone") and _time_left() > 200 and qm.is_unlocked("mine_access"):
		await _mine(1, {"stone": int(need.stone)})


## 농장의 이 종류 장애물을 가까운 것부터 max 개까지 치운다 (밭 칸 먼저)
func _clear_types(types: Array, max_n: int) -> void:
	var today := GameState.day
	for i in max_n:
		if GameState.day != today or _time_left() < 40:
			return
		var best: Obstacle = null
		var best_d := INF
		for ob: Obstacle in world.obstacles.all():
			if ob.def.id in types:
				var d := pos.distance_to(world.cell_center(ob.cell))
				if d < best_d:
					best_d = d
					best = ob
		if best == null:
			return
		var tool_type := "pickaxe" if "pickaxe" in best.def.tools and not "axe" in best.def.tools else ("axe" if "axe" in best.def.tools else "hoe")
		if best.def.id == "weed":
			tool_type = "hoe"
		var slot := _tool_slot(tool_type)
		for h in 30:
			if world.obstacles.obstacle_at(best.cell) == null or GameState.day != today:
				break
			_tool(best.cell, slot)
		await get_tree().process_frame


## 광산: target_floor 까지 내려가며 바위를 깨고, want(아이템: 개수)를 모을 때까지. 하루 시간이 모자라면 나온다
func _mine(target_floor: int, want: Dictionary) -> void:
	if not qm.is_unlocked("mine_access"):
		return
	var today := GameState.day
	_walk_to(world.mine_entrance.interact_point())
	world.mine_entrance.interact(player)
	await get_tree().process_frame
	pos = player.global_position
	var floor_no := 0
	var start: int = (Mine.elevator_stops().filter(func(n: int) -> bool: return n <= target_floor) as Array).max()
	if start > 0:
		_spend(UI_TIME)
		Events.mine_requested.emit(start)
		floor_no = start
	else:
		_walk_to(world.cell_center(Mine.ORIGIN + Mine.ENTRY_LADDER_AT))
		Events.mine_requested.emit(1)
		floor_no = 1
	await get_tree().process_frame
	pos = player.global_position
	counters.mine_floors_entered += 1
	while GameState.day == today and _time_left() > 90:
		var done := want.keys().all(func(k: String) -> bool: return inv.count_of(k) >= int(want[k]))
		if floor_no >= target_floor and done:
			# 설계도 (MQ15)
			for f: Node in world.objects.get_children():
				if f is MineFeature and f.kind == MineFeature.Kind.BLUEPRINT and not f.is_queued_for_deletion():
					_walk_to(f.interact_point())
					f.interact(player)
					_spend(UI_TIME)
			break
		var rock := _nearest_rock(want)
		if world.mine.has_ladder() and (floor_no < target_floor or rock == null) and floor_no < Mine.bottom():
			_spend(2.0)
			Events.mine_requested.emit(floor_no + 1)
			floor_no += 1
			counters.mine_floors_entered += 1
			await get_tree().process_frame
			pos = player.global_position
			continue
		if rock == null:
			break
		var cell := rock.cell
		for h in 30:
			if world.mine.rocks.obstacle_at(cell) == null:
				break
			_tool(cell, _tool_slot("pickaxe"))
		counters.rocks_broken += 1
		await get_tree().process_frame
	# 나오기 (입구층 출구까지 걸어서)
	_spend(UI_TIME)
	world.exit_mine()
	await get_tree().process_frame
	pos = player.global_position
	hud._close_panels()
	_ckpt("after_mine")


## 원하는 광석 바위를 먼저, 없으면 아무 바위 (사다리를 찾으려고)
func _nearest_rock(want: Dictionary) -> Obstacle:
	var best: Obstacle = null
	var best_score := INF
	for ob: Obstacle in world.mine.rocks.all():
		var drop: String = str(ob.def.drops[0].item) if not ob.def.drops.is_empty() else ""
		var wanted := want.has(drop) and inv.count_of(drop) < int(want[drop])
		var score := pos.distance_to(world.cell_center(ob.cell)) * (0.3 if wanted else 1.0)
		if score < best_score:
			best_score = score
			best = ob
	return best


# ---------- 용광로 · 가공

func _ensure_factory_spot() -> void:
	if factory_origin != Vector2i(-1, -1):
		return
	# 밭이 아닌 땅에서 12x6 자리를 찾고, 덮인 장애물은 도구로 치운다 (실제 플레이처럼 시간이 든다)
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return world.cell_center(a).distance_squared_to(world.home_position) < world.cell_center(b).distance_squared_to(world.home_position))
	for c: Vector2i in cells:
		var ok := true
		for y in 6:
			for x in 12:
				var cc := c + Vector2i(x, y)
				if not world.farm.farmable_cells.has(cc) or cc in plot or world.build.is_occupied(cc) or world.farm.tiles.has(cc):
					ok = false
					break
			if not ok:
				break
		if ok:
			factory_origin = c
			_note("공장 자리 %s" % c)
			for y in 6:
				for x in 12:
					var ob := world.obstacles.obstacle_at(c + Vector2i(x, y))
					if ob:
						var tool_type := "axe" if "axe" in ob.def.tools else ("pickaxe" if "pickaxe" in ob.def.tools else "hoe")
						for h in 30:
							if world.obstacles.obstacle_at(c + Vector2i(x, y)) == null:
								break
							_tool(c + Vector2i(x, y), _tool_slot(tool_type))
			return


## 이 칸들에 다시 자란 잡초·돌·가지가 있으면 도구로 치운다 (설치 전에, 실제 플레이어처럼)
func _clear_cells(cells: Array) -> void:
	for c: Vector2i in cells:
		var ob := world.obstacles.obstacle_at(c)
		if ob == null:
			continue
		var tool_type := "hoe" if ob.def.id == "weed" else ("axe" if "axe" in ob.def.tools else "pickaxe")
		for h in 30:
			if world.obstacles.obstacle_at(c) == null:
				break
			_tool(c, _tool_slot(tool_type))


func _place(def_id: String, origin: Vector2i, turns := 0) -> bool:
	var size := PlaceableDB.get_def(def_id).size
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	_clear_cells(cells)
	_walk_to(world.cell_center(origin))
	_spend(UI_TIME)
	world.build_mode.start_place(def_id)
	world.build_mode.turns = turns
	var ok := world.build_mode.try_place(origin)
	world.build_mode.stop()
	return ok


func _smelt_quest() -> void:
	if furnace == null:
		if inv.count_of("furnace") == 0:
			if GameState.money < 1000 or inv.count_of("stone") < 30:
				return
			if not await _buy_machine("smith", "smith_shop", "furnace", 1, "시설 구매"):
				_note("용광로를 사지 못함: %s" % ShopPanel.buy_problem(ItemDB.get_item("furnace"), 1))
				return
		_ensure_factory_spot()
		if _place("furnace", factory_origin + Vector2i(0, 5)):
			furnace = world.build.object_at(factory_origin + Vector2i(0, 5)) as Furnace
	await _smelt_bars(1)


## 주괴 n 개가 될 때까지: 광석·석탄 모으기 → 용광로에 넣기 (굽는 동안 다른 일) → 꺼내기
func _smelt_bars(n: int) -> void:
	if furnace == null:
		await _smelt_quest()
		return
	if furnace.output > 0:
		_walk_to(world.cell_center(furnace.cell))
		furnace.take_output(inv)
		_spend(TOOL_TIME)
	var need_bars := n - inv.count_of("copper_bar")
	if need_bars <= 0:
		return
	var queued := 1 if furnace.is_working() else 0
	var want_ore := maxi(0, (need_bars - queued) * 3)
	var want_coal := maxi(0, need_bars - queued)
	if inv.count_of("copper_ore") < want_ore or inv.count_of("coal") < want_coal:
		await _mine(1, {"copper_ore": want_ore, "coal": want_coal})
	# 넣고 → 다 구울 때까지 옆에서 기다렸다가 (60분 = 실제 약 47초) → 꺼내고 → 또 넣기. 하루 시간이 모자라면 남은 건 내일
	var today := GameState.day
	while GameState.day == today and _time_left() > 120 and inv.count_of("copper_bar") < n:
		if not furnace.is_working():
			if inv.count_of("copper_ore") < 3 or inv.count_of("coal") < 1:
				break
			var slot := _slot_of(func(it: ItemDef) -> bool: return it.id == "copper_ore")
			_tool(furnace.cell, slot)
			if not furnace.is_working():
				break
		_spend(furnace.minutes_left / (GameState.game_minutes_for(1.0)) + 1.0)
		if furnace.output > 0:
			_walk_to(world.cell_center(furnace.cell))
			furnace.take_output(inv)
			_spend(TOOL_TIME)


## 가공 재료 씨앗 (MQ16 끝 ~ MQ20 끝, 이번 계절에 심을 수 있는 것). 없으면 ""
func _recipe_seed() -> String:
	if _recipe_inputs_needed().is_empty():
		return ""
	var crop: String = RecipeDB.get_recipe(_recipe_for_season()).inputs.keys()[0]
	var sid := crop + "_seed"
	var it := ItemDB.get_item(sid)
	return sid if it and Calendar.in_season_for_shop(it, GameState.day) and it.grow_days < 28 - Calendar.day_in_season(GameState.day) + 1 else ""


func _recipe_for_season() -> String:
	var s := Calendar.season_of(GameState.day)
	if s in ["spring", "summer"]:
		return "flour"
	if s == "autumn":
		return "dried_sweet_potato"
	return "sugar"


## MQ18~MQ20 에 쓸 가공 재료 (작물). 봇은 이만큼은 팔지 않고 남긴다
func _recipe_inputs_needed() -> Dictionary:
	if qm.state_of("MQ16") != QuestManager.REWARDED or qm.state_of("MQ20") == QuestManager.REWARDED:
		return {}
	var r := RecipeDB.get_recipe(_recipe_for_season())
	var out := {}
	for k: String in r.inputs:
		out[k] = int(r.inputs[k]) * 8
	return out


func _processing_quest(conveyor: bool) -> void:
	if processor == null:
		if inv.count_of("manual_processor") == 0:
			if inv.count_of("wood") < 50 or inv.count_of("stone") < 30 or GameState.money < 450:
				return
			if not await _buy_machine("machine", "machine", "manual_processor", 1, "시설 구매"):
				_note("수동 가공기를 사지 못함: %s" % ShopPanel.buy_problem(ItemDB.get_item("manual_processor"), 1))
				return
		_ensure_factory_spot()
		if _place("manual_processor", factory_origin):
			processor = world.build.object_at(factory_origin) as Processor
	if processor == null:
		return
	if conveyor and warehouse == null:
		if inv.count_of("warehouse") == 0:
			if inv.count_of("wood") < 80 or inv.count_of("stone") < 40 or GameState.money < 1200 + 200:
				return
			await _buy_machine("machine", "machine", "warehouse", 1, "시설 구매")
		if inv.count_of("conveyor") < 5:
			await _buy_machine("machine", "machine", "conveyor", 5 - inv.count_of("conveyor"), "시설 구매")
		if _place("warehouse", factory_origin + Vector2i(7, 0)):
			warehouse = world.build.object_at(factory_origin + Vector2i(7, 0)) as Warehouse
			_clear_cells([2, 3, 4, 5, 6].map(func(x: int) -> Vector2i: return factory_origin + Vector2i(x, 1)))
			_walk_to(world.cell_center(factory_origin + Vector2i(2, 1)))
			_spend(UI_TIME)
			world.build_mode.start_place("conveyor")
			world.build_mode.place_belts(factory_origin + Vector2i(2, 1), factory_origin + Vector2i(6, 1))
			world.build_mode.stop()
			_ckpt("machines_placed")
	# 벨트가 빠진 칸이 있으면 (막혀서 건너뛴 칸) 치우고 다시 깐다
	if conveyor and warehouse != null and qm.tracked().get("id", "") == "MQ18":
		var missing := [2, 3, 4, 5, 6].filter(func(x: int) -> bool: return world.build.object_at(factory_origin + Vector2i(x, 1)) == null)
		if not missing.is_empty():
			if inv.count_of("conveyor") < missing.size():
				await _buy_machine("machine", "machine", "conveyor", missing.size() - inv.count_of("conveyor"), "시설 구매")
			_clear_cells(missing.map(func(x: int) -> Vector2i: return factory_origin + Vector2i(x, 1)))
			for x: int in missing:
				_place("conveyor", factory_origin + Vector2i(x, 1), 3)
	if qm.tracked().get("id", "") == "MQ19" and not world.build.object_at(factory_origin + Vector2i(4, 1)) is Router:
		if inv.count_of("splitter") == 0:
			if inv.count_of("wood") < 10 or inv.count_of("stone") < 5 or GameState.money < 250 + 40:
				return
			await _buy_machine("machine", "machine", "splitter", 1, "시설 구매")
			await _buy_machine("machine", "machine", "conveyor", 1, "시설 구매")
		_walk_to(world.cell_center(factory_origin + Vector2i(4, 1)))
		_spend(UI_TIME)
		world.build_mode.start(BuildMode.Mode.REMOVE)
		world.build_mode.try_remove(factory_origin + Vector2i(4, 1))  # 철거 모드: 벨트를 돌려받는다
		world.build_mode.stop()
		_place("splitter", factory_origin + Vector2i(4, 1), 3)
		_place("conveyor", factory_origin + Vector2i(4, 0), 2)
	# 가공: 레시피 재료가 있으면 정한 만큼 돌린다 (지원 밀가루 3 은 반죽 재료로)
	if processor.is_working():
		return
	if processor.output_count() > 0 and not conveyor:
		_walk_to(world.cell_center(processor.cell))
		processor.take_output(inv)
		_spend(UI_TIME)
	var rid := "flour" if qm.state_of("MQ17") == QuestManager.ACTIVE else _recipe_for_season()
	if RecipeDB.get_recipe(rid).get("unlocked", false) == false and not RecipeDB.is_known(rid):
		if GameState.money >= RecipeDB.get_recipe(rid).get("price", 0) + 100:
			await _money_action("레시피 구매", func() -> void:
				_walk_to(_building("RecipeShop").interact_point())
				_spend(UI_TIME)
				RecipeDB.buy(rid))
	for try_id: String in [rid, "dough", "flour", "potato_snack", "tomato_puree", "sugar"]:
		var runs := Processor.runs_possible(inv, RecipeDB.get_recipe(try_id), 99) if RecipeDB.has(try_id) else 0
		if runs > 0 and processor.recipe_problem(try_id) == "":
			_walk_to(world.cell_center(processor.cell))
			_spend(UI_TIME)
			processor.start(inv, try_id, runs)
			return


# ---------- 결과

func _finish(start_money: int) -> void:
	_track_quests()
	var booked := 0
	for k: String in ledger:
		booked += int(ledger[k])
	_book("미분류", GameState.money - start_money - booked)
	var total_in := 0
	var total_out := 0
	for k: String in ledger:
		if int(ledger[k]) > 0:
			total_in += int(ledger[k])
		else:
			total_out += int(ledger[k])
	var result := {"season": season, "plot": plot_size, "seed": rng_seed, "completed": _rewarded.size(), "stuck": stuck,
		"days": GameState.day - _start_day() + 1, "active_minutes": snappedf(active_seconds / 60.0, 0.1), "start_money": start_money, "end_money": GameState.money,
		"ledger": ledger, "daily": daily, "income": total_in, "expense": total_out, "timeline": timeline, "notes": notes, "counters": counters,
		"era": qm.era, "techs": qm.techs.keys(), "inventory": {"wood": inv.count_of("wood"), "stone": inv.count_of("stone"), "copper_bar": inv.count_of("copper_bar")}}
	var path := "user://playthrough_%s_%d_%d%s.json" % [season, plot_size, rng_seed, "_keep" if keep_support else ""]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("PLAYTHROUGH %s plot=%d seed=%d: 완료 %d/20 · %d일 · 봇 시간 %.0f분 · 돈 %d → %d · 막힘 '%s'" % [season, plot_size, rng_seed, _rewarded.size(), result.days, active_seconds / 60.0, start_money, GameState.money, stuck])
	print("LEDGER ", JSON.stringify(ledger))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveManager.slot_path))
	get_tree().quit()


func _choose_plot() -> void:
	# 집에서 가까운 밭 땅 (보통 흙 'g'), 장애물이 있으면 아침에 괭이·도끼로 치우며 쓴다
	var cells: Array = world.farm.farmable_cells.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return world.cell_center(a).distance_squared_to(world.home_position) < world.cell_center(b).distance_squared_to(world.home_position))
	for c: Vector2i in cells:
		if plot.size() >= plot_size:
			break
		if world.obstacles.obstacle_at(c) == null and not world.build.is_occupied(c):
			plot.append(c)
