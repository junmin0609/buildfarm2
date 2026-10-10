class_name QuestManager
extends Node
## 메인 퀘스트 · 기술 발전 상태 (스토리·퀘스트·기술 발전 명세 v1.0). 데이터는 data/quests.json.
## 기존 시스템이 보내는 신호(Events, 장애물 cleared)를 듣기만 하는 얇은 층이라 게임 규칙은 바꾸지 않는다.
##
## 퀘스트 상태: locked → active → completed → rewarded
##   - 앞 퀘스트(prerequisites)가 모두 rewarded 면 active 가 된다 (새 게임은 MQ01 부터)
##   - 목표를 다 채우면 completed, 보상을 주면 rewarded. 보상은 rewarded 로 바꾸는 것과 같은 자리에서 한 번만 준다
##   - 가방이 모자라 보상을 못 주면 completed 로 남고, 가방이 바뀔 때마다 다시 시도한다
##   - 이벤트형 목표(치우기·갈기·심기·물 주기·수확…)는 진행 중일 때만 센다. 상태형(방문)은 그 전에 해 둔 것도 인정
## 기술: era(지금 시대) · techs(연 기술). 새 게임은 개척시대 + start 기술. 기존 저장(버전 5 이하)은 legacy:
##   모든 기술이 열린 것으로 보고(사용자 결정 3: 돈·아이템·건물·해금 유지), 퀘스트는 MQ01 부터 직접 진행해 보상을 받는다.
##   실제 구매·설치 제한은 3단계 (지금은 상태만).

const DATA_PATH := "res://data/quests.json"
const LOCKED := "locked"
const ACTIVE := "active"
const COMPLETED := "completed"
const REWARDED := "rewarded"

## 상태형 목표: 해 둔 일 (방문 등). 이벤트형 목표 집계와 따로 저장한다
const STATE_TYPES := ["visit"]
## 복구 프로젝트 납품을 받는 NPC 이름 (대화 창·HUD 안내)
const NPC_NAMES := {"store": "잡화점 하나", "smith": "대장장이 철수", "machine": "기계상점 미나"}
## 도구 강화 목표의 target: 강화된 도구 등급 → 재료 이름
const TOOL_TIERS := {2: "copper", 3: "iron", 4: "gold"}

static var _data: Dictionary = {}
## 지금 게임의 QuestManager (상점·건설·대장간·광산 입구 같은 곳이 잠금을 물어볼 때, 3단계)
static var current: QuestManager = null

var world: FarmWorld
## 퀘스트 id → {"state", "progress": [목표별 수], "granted": 받을 때 주는 물건을 다 줬는가 (예전 저장 호환용)}
var quests := {}
## 받을 때 주는 지원 물건 (MQ17 밀 4 · MQ20 밀가루 3). 퀘스트 상태와 따로 저장한다
##   퀘스트 id → {"owed": {아이템: 줄 개수}, "given": {아이템: 준 개수}}
##   받는 순간 owed 를 기록하고, 가방에 들어가는 만큼만 주고 given 에 더한다 (Inventory.add 가 남긴 수만큼은 대기).
##   가방이 바뀔 때마다 남은 것을 다시 준다 → 일부만 들어가도 중복·유실 없음. owed 가 생긴 뒤에는 퀘스트를 끝내도 마저 준다
var support := {}
## 지원 물건을 주는 중 (주면서 생긴 가방 신호로 다시 들어오지 않게)
var _paying := false
## 한 번이라도 일어난 일 (예: "visited:plaza") — 상태형 목표가 받기 전 일도 인정하려고
var flags := {}
var era := "pioneer"
var techs := {}
## 기존 저장 (버전 5 이하): 모든 기술이 열린 것으로 본다
var legacy := false
## 복구 프로젝트: 넣은 재료·돈 {프로젝트: {아이템 id 또는 "money": 개수}}, 끝난 프로젝트 {프로젝트: true}
var project_given := {}
var projects_done := {}
## 보상을 주는 중 (보상 아이템이 가방 신호로 다시 이 함수를 부르지 않게)
var _rewarding := false


static func data() -> Dictionary:
	if _data.is_empty():
		_data = DataFile.load_dict(DATA_PATH)
	return _data


static func quest_defs() -> Array:
	return data().get("quests", [])


static func quest_def(id: String) -> Dictionary:
	for q: Dictionary in quest_defs():
		if q.id == id:
			return q
	return {}


static func era_ids() -> Array:
	return data().get("eras", []).map(func(e: Dictionary) -> String: return e.id)


func _ready() -> void:
	name = "Quests"
	current = self
	new_game()
	Events.sign_read.connect(func(sign_id: String) -> void: _on_event("talk_sign", sign_id, 1))
	Events.soil_tilled.connect(func(_cell: Vector2i) -> void: _on_event("till", "", 1))
	Events.seed_planted.connect(func(_cell: Vector2i, seed_id: String) -> void: _on_event("plant", seed_id, 1))
	Events.crop_watered.connect(func(_cell: Vector2i) -> void: _on_event("water", "", 1))
	Events.watering_can_refilled.connect(func(amount: int) -> void: _on_event("refill", "", 1 if amount > 0 else 0))
	Events.crop_harvested.connect(func(item_id: String, count: int) -> void: _on_event("harvest", item_id, count))
	Events.inventory_changed.connect(_try_rewards)
	Events.inventory_changed.connect(_pay_support)
	# 가게 NPC 에게 말을 걸면 (Npc.room_id: store · smith · machine)
	Events.npc_talk_requested.connect(func(npc: Node) -> void:
		if "room_id" in npc and str(npc.room_id) != "":
			_on_event("talk_npc", str(npc.room_id), 1))
	if world:
		world.obstacles.cleared.connect(func(_cell: Vector2i, def: ObstacleDef) -> void: _on_event("clear_obstacle", def.id, 1))
	# 4단계: MQ06~MQ20 목표 (기존 기능이 보내는 알림을 듣기만 한다)
	Events.item_shipped.connect(func(item_id: String, count: int) -> void: _on_event("ship", item_id, count))
	Events.item_collected.connect(func(item_id: String, count: int) -> void: _on_event("collect", item_id, count))
	Events.item_made.connect(func(item_id: String, machine_id: String, count: int) -> void:
		_on_event("smelt" if machine_id == "furnace" else "process", item_id, count, {"machine": machine_id}))
	Events.tool_upgraded.connect(func(item_id: String) -> void:
		var it := ItemDB.get_item(item_id)
		if it:
			_on_event("upgrade_tool", str(TOOL_TIERS.get(it.tier, "")), 1))
	Events.mine_floor_reached.connect(_on_floor)
	Events.facility_placed.connect(func(def_id: String) -> void: _on_event("place", def_id, 1))
	Events.belt_delivered.connect(_on_belt_delivered)
	Events.item_split.connect(_on_split)
	Events.game_loaded.connect(ensure_quest_objects)
	Events.day_started.connect(func(_d: int) -> void: ensure_quest_objects())


func _process(_delta: float) -> void:
	# 방문 판정 (상태형): 광장 — 농장 맵에서 개울 다리 동쪽
	if world == null or world.area != "farm":
		return
	var plaza: Dictionary = data().get("areas", {}).get("plaza", {})
	var cell := world.player.my_cell()
	if not flags.has("visited:plaza") and cell.x >= int(plaza.get("min_x", 9999)):
		mark("visited:plaza")
	# 광산 입구 앞 (MQ10)
	var r: Array = data().get("areas", {}).get("mine_entrance", {}).get("rect", [])
	if not flags.has("visited:mine_entrance") and r.size() == 4 and cell.x >= int(r[0]) and cell.y >= int(r[1]) and cell.x <= int(r[2]) and cell.y <= int(r[3]):
		mark("visited:mine_entrance")


# ---------- 새 게임 · 상태

## 새 게임: 개척시대 + 시작 기술, MQ01 진행 중
func new_game() -> void:
	quests.clear()
	flags.clear()
	techs.clear()
	project_given.clear()
	projects_done.clear()
	support.clear()
	legacy = false
	era = era_ids()[0] if not era_ids().is_empty() else "pioneer"
	for tech_id: String in data().get("techs", {}):
		if data().techs[tech_id].get("start", false):
			techs[tech_id] = true
	for q: Dictionary in quest_defs():
		quests[q.id] = {"state": LOCKED, "progress": _zeros(q), "granted": false}
	_activate_ready()


func _zeros(q: Dictionary) -> Array:
	var out := []
	for o in q.get("objectives", []):
		out.append(0)
	return out


func state_of(id: String) -> String:
	return str(quests.get(id, {}).get("state", LOCKED))


func progress_of(id: String) -> Array:
	return quests.get(id, {}).get("progress", [])


func active_quests() -> Array:
	return quest_defs().filter(func(q: Dictionary) -> bool: return state_of(q.id) == ACTIVE)


## 기술이 열렸는가. 기존 저장은 모두 열림
func is_unlocked(tech_id: String) -> bool:
	return legacy or techs.get(tech_id, false)


## 이 아이템·시설을 여는 기술 (없으면 "" = 제한 없음)
static func tech_for_item(item_id: String) -> String:
	var all: Dictionary = data().get("techs", {})
	for tech_id: String in all:
		if item_id in all[tech_id].get("items", []):
			return tech_id
	return ""


func item_unlocked(item_id: String) -> bool:
	var t := tech_for_item(item_id)
	return t == "" or is_unlocked(t)


## 이 기술이 어디서 열리는지 (해금 조건 글): "광산 입구 수리 복구 프로젝트 (MQ11)" · "MQ18 '…' 보상" · "시작부터"
static func tech_source(tech_id: String) -> String:
	var t: Dictionary = data().get("techs", {}).get(tech_id, {})
	if t.get("start", false):
		return "시작부터"
	var projects: Dictionary = data().get("projects", {})
	for pid: String in projects:
		if tech_id in projects[pid].get("unlock", []):
			var p: Dictionary = projects[pid]
			var where := str(p.get("quest", "")) if p.has("quest") else ("MQ20 뒤" if p.has("flag") else "추후 공개")
			return "%s 프로젝트 (%s)" % [p.name, where]
	for q: Dictionary in quest_defs():
		if tech_id in q.get("rewards", {}).get("unlock", []):
			return "%s '%s' 보상" % [q.id, q.title]
	return "추후 공개"


## 짧은 해금 조건 (상점·건설 창): "MQ16 · 기계 기술 복구" · "MQ18 보상" · "MQ20 뒤 · 전력 복구"
static func tech_source_short(tech_id: String) -> String:
	var t: Dictionary = data().get("techs", {}).get(tech_id, {})
	if t.get("start", false):
		return "시작부터"
	var projects: Dictionary = data().get("projects", {})
	for pid: String in projects:
		var p: Dictionary = projects[pid]
		if tech_id in p.get("unlock", []):
			return "%s · %s" % [str(p.quest) if p.has("quest") else ("MQ20 뒤" if p.has("flag") else "추후"), p.name]
	for q: Dictionary in quest_defs():
		if tech_id in q.get("rewards", {}).get("unlock", []):
			return "%s 보상" % q.id
	return "추후 공개"


## 짧은 잠김 글 (열려 있으면 ""): "잠김 · MQ16 · 기계 기술 복구"
func lock_short(item_id: String) -> String:
	var t := tech_for_item(item_id)
	return "잠김 · " + tech_source_short(t) if tech_lock_reason(t) != "" else ""


static func lock_short_now(item_id: String) -> String:
	return current.lock_short(item_id) if is_instance_valid(current) else ""


## 잠긴 이유 (열려 있으면 ""). 기술 id
func tech_lock_reason(tech_id: String) -> String:
	if tech_id == "" or is_unlocked(tech_id):
		return ""
	if not data().get("techs", {}).has(tech_id):
		return ""
	return "잠김 · %s에서 해금" % tech_source(tech_id)


## 잠긴 이유 (열려 있으면 ""). 아이템·시설 id
func lock_reason(item_id: String) -> String:
	return tech_lock_reason(tech_for_item(item_id))


## 지금 게임 기준 잠긴 이유 (QuestManager 가 없으면 잠기지 않음 — 시작 화면 등)
static func lock_reason_now(item_id: String) -> String:
	return current.lock_reason(item_id) if is_instance_valid(current) else ""


static func tech_lock_reason_now(tech_id: String) -> String:
	return current.tech_lock_reason(tech_id) if is_instance_valid(current) else ""


## 화면에 보여 줄 시대 (기존 저장은 따로, 사용자 결정)
func era_label() -> String:
	return "기존 저장 · 모든 기술 해금" if legacy else era_name()


## 열린 기술 이름 (기존 저장은 전부)
func unlocked_tech_names() -> Array[String]:
	var out: Array[String] = []
	var all: Dictionary = data().get("techs", {})
	for tech_id: String in all:
		if is_unlocked(tech_id):
			out.append(str(all[tech_id].get("name", tech_id)))
	return out


## HUD 가 따라갈 퀘스트 (진행 중인 것 중 첫 번째, 없으면 {})
func tracked() -> Dictionary:
	var act := active_quests()
	return act[0] if not act.is_empty() else {}


## 목표 한 줄 ("잡초 치우기 3/10")
func objective_line(q: Dictionary, i: int) -> String:
	var o: Dictionary = q.objectives[i]
	var need := int(o.get("count", 1))
	var done := mini(int(progress_of(q.id)[i]), need) if i < progress_of(q.id).size() else 0
	if state_of(q.id) in [COMPLETED, REWARDED]:
		done = need
	return "%s %d/%d" % [str(o.get("text", o.type)), done, need]


## 보상 글 ("감자 씨앗 5 · 100 G")
func reward_text(q: Dictionary) -> String:
	var r: Dictionary = q.get("rewards", {})
	var parts: Array[String] = []
	for item_id: String in r.get("items", {}):
		parts.append("%s %d" % [ItemDB.get_item(item_id).name, int(r.items[item_id])])
	if int(r.get("money", 0)) > 0:
		parts.append("%d G" % int(r.money))
	var all: Dictionary = data().get("techs", {})
	for tech_id: String in r.get("unlock", []):
		parts.append("%s 해금" % all.get(tech_id, {}).get("name", tech_id))
	for o: Dictionary in q.get("objectives", []):
		if o.type == "project":
			var pr: Dictionary = data().get("projects", {}).get(str(o.get("target", "")), {})
			for tech_id: String in pr.get("unlock", []):
				parts.append("%s 해금" % all.get(tech_id, {}).get("name", tech_id))
	return " · ".join(parts) if not parts.is_empty() else "없음"


func era_name() -> String:
	for e: Dictionary in data().get("eras", []):
		if e.id == era:
			return e.name
	return era


## 상태형 기록 (방문 등). 진행 중인 퀘스트의 상태형 목표를 다시 센다
func mark(flag: String) -> void:
	if flags.has(flag):
		return
	flags[flag] = true
	_refresh_state_objectives()


# ---------- 목표 집계

func _on_event(type: String, target: String, amount: int, extra := {}) -> void:
	if amount <= 0:
		return
	var changed := false
	for q: Dictionary in quest_defs():
		if state_of(q.id) != ACTIVE:
			continue
		var objs: Array = q.get("objectives", [])
		var prog: Array = quests[q.id].progress
		for i in objs.size():
			var o: Dictionary = objs[i]
			if o.type != type or not _target_matches(str(o.get("target", "")), target):
				continue
			if o.has("machine") and str(extra.get("machine", "")) != str(o.machine):
				continue  # 예: MQ17 은 수동 가공기로 만든 것만
			var need := int(o.get("count", 1))
			if int(prog[i]) < need:
				prog[i] = mini(need, int(prog[i]) + amount)
				changed = true
		if changed:
			_check_complete(q)
	if changed:
		Events.quest_changed.emit("")


## 광산 층 도달: 진행도 = 이번에 닿은 가장 깊은 층 (진행 중일 때만)
func _on_floor(n: int) -> void:
	var changed := false
	for q: Dictionary in active_quests():
		var objs: Array = q.get("objectives", [])
		for i in objs.size():
			if objs[i].type == "mine_floor" and n > int(quests[q.id].progress[i]):
				quests[q.id].progress[i] = mini(n, int(objs[i].get("count", 1)))
				changed = true
		_check_complete(q)
	if changed:
		Events.quest_changed.emit("")


## 컨베이어가 시설 입구에 넣었다: 운송(convey) 1, 그게 창고에 들어간 가공품이면 입고(store_processed) 1
func _on_belt_delivered(facility: Node, item_id: String) -> void:
	_on_event("convey", item_id, 1)
	var it := ItemDB.get_item(item_id)
	if facility is Warehouse and it and it.kind == ItemDef.Kind.PROCESSED:
		_on_event("store_processed", item_id, 1)


## 분배기가 한 출구로 내보냈다: 같은 분배기의 서로 다른 출구 수가 진행도 (진행 중일 때만, 저장됨)
func _on_split(router: Node, d: Vector2i) -> void:
	var key := "%d,%d" % [router.cell.x, router.cell.y] if "cell" in router else str(router.get_instance_id())
	var changed := false
	for q: Dictionary in active_quests():
		var objs: Array = q.get("objectives", [])
		for i in objs.size():
			if objs[i].type != "split":
				continue
			var st: Dictionary = quests[q.id]
			if not st.has("seen"):
				st["seen"] = {}
			var dirs: Array = st.seen.get(key, [])
			var dk := "%d,%d" % [d.x, d.y]
			if dk not in dirs:
				dirs.append(dk)
				st.seen[key] = dirs
			var best := 0
			for k: String in st.seen:
				best = maxi(best, (st.seen[k] as Array).size())
			if mini(best, int(objs[i].get("count", 1))) > int(st.progress[i]):
				st.progress[i] = mini(best, int(objs[i].get("count", 1)))
				changed = true
		_check_complete(q)
	if changed:
		Events.quest_changed.emit("")


## 광산 5층 오래된 설계도를 조사했다. MQ15 의 설계도 목표가 진행 중이면 찾음 (true)
func find_blueprint() -> bool:
	for q: Dictionary in active_quests():
		for o: Dictionary in q.get("objectives", []):
			if o.type == "find_blueprint":
				flags["found:blueprint"] = true
				_on_event("find_blueprint", "", 1)
				return true
	return false


## 설계도를 광산에 놓을까: 아직 찾지 않았으면 (QuestManager 가 없으면 놓지 않음)
static func blueprint_wanted_now() -> bool:
	return is_instance_valid(current) and not current.flags.has("found:blueprint")


# ---------- 퀘스트 물건 (4단계): MQ09 폐탄더미 · MQ10 입구 잔해. 진행 중에만, 모자란 만큼 채운다

func ensure_quest_objects() -> void:
	if world == null or world.obstacles == null:
		return
	var areas: Dictionary = data().get("areas", {})
	# MQ10: 남은 치우기 수만큼 잔해 (이미 있는 것 포함)
	var debris_left := _objective_left("clear_obstacle", "mine_debris")
	if debris_left > 0:
		_fill_spawns(areas.get("debris", []), "mine_debris", debris_left)
	# MQ09: 석탄 납품이 남았으면 폐탄더미 3개까지
	if _objective_left("deliver", "coal") > 0:
		_fill_spawns(areas.get("coal_piles", []), "coal_pile", 3)


## 진행 중인 퀘스트의 이 목표가 몇 남았나 (없으면 0)
func _objective_left(type: String, target: String) -> int:
	var left := 0
	for q: Dictionary in active_quests():
		var objs: Array = q.get("objectives", [])
		for i in objs.size():
			if objs[i].type == type and str(objs[i].get("target", "")) == target:
				left += maxi(0, int(objs[i].get("count", 1)) - int(quests[q.id].progress[i]))
	return left


## cells 중 비어 있는 칸에 type_id 를 want 개가 될 때까지 깐다 (이미 있는 것도 셈)
func _fill_spawns(cells: Array, type_id: String, want: int) -> void:
	var have := 0
	var free: Array[Vector2i] = []
	for c: Variant in cells:
		var cell := DataFile.to_vector2i(c, Vector2i(-1, -1))
		var ob := world.obstacles.obstacle_at(cell)
		if ob and ob.def.id == type_id:
			have += 1
		elif ob == null and not world.build.is_occupied(cell):
			free.append(cell)
	for cell in free:
		if have >= want:
			break
		if world.obstacles.spawn(cell, type_id, cell.x * 31 + cell.y):
			have += 1


func _target_matches(want: String, got: String) -> bool:
	if want == "":
		return true
	if want.begins_with("kind:"):
		var it := ItemDB.get_item(got)
		return it != null and ItemDef.Kind.keys()[it.kind].to_lower() == want.trim_prefix("kind:")
	return want == got


func _refresh_state_objectives() -> void:
	for q: Dictionary in quest_defs():
		if state_of(q.id) != ACTIVE:
			continue
		var objs: Array = q.get("objectives", [])
		for i in objs.size():
			var o: Dictionary = objs[i]
			var key := ("visited:" if o.type == "visit" else str(o.type) + ":") + str(o.get("target", ""))
			if o.type in STATE_TYPES and flags.has(key):
				quests[q.id].progress[i] = int(o.get("count", 1))
		_check_complete(q)
	Events.quest_changed.emit("")


func _check_complete(q: Dictionary) -> void:
	var st: Dictionary = quests[q.id]
	if st.state != ACTIVE:
		return
	var objs: Array = q.get("objectives", [])
	for i in objs.size():
		if int(st.progress[i]) < int(objs[i].get("count", 1)):
			return
	st.state = COMPLETED
	_try_rewards()


# ---------- NPC 납품 (사용자 결정: 필요한 재료를 모두 가졌을 때만, 한꺼번에 차감)

## 이 NPC(room_id) 에게 지금 할 수 있는 납품: [{quest, index, text, have, need, ok}]
func deliveries_for(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q: Dictionary in quest_defs():
		if state_of(q.id) != ACTIVE:
			continue
		var objs: Array = q.get("objectives", [])
		for i in objs.size():
			var o: Dictionary = objs[i]
			if o.type != "deliver" or str(o.get("npc", "")) != npc_id:
				continue
			var need := int(o.get("count", 1))
			if int(progress_of(q.id)[i]) >= need:
				continue
			var have := deliver_have(str(o.get("target", "")))
			out.append({"quest": q.id, "index": i, "text": str(o.get("text", "")), "have": have, "need": need, "ok": have >= need})
	return out


## 진행 중인 퀘스트 중 이 NPC 와 관련된 것 (대화 창에 한 줄 안내). 복구 프로젝트를 이 NPC 가 받으면 그 퀘스트도
func quests_for_npc(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q: Dictionary in active_quests():
		for o: Dictionary in q.get("objectives", []):
			var project_npc := str(project_defs().get(str(o.get("target", "")), {}).get("npc", "")) if o.type == "project" else ""
			if (str(o.get("npc", o.get("target", ""))) == npc_id and o.type in ["deliver", "talk_npc"]) or project_npc == npc_id:
				out.append(q)
				break
	return out


## 이 NPC 가 지금 받는 복구 프로젝트 (넣을 수 있는 것만)
func projects_for_npc(npc_id: String) -> Array[String]:
	var out: Array[String] = []
	for pid: String in project_defs():
		if str(project_defs()[pid].get("npc", "")) == npc_id and project_problem(pid) == "":
			out.append(pid)
	return out


## HUD 안내: 지금 따라가는 퀘스트에 넣을 수 있는 복구 프로젝트가 있으면 "Q → 기술·복구 탭에서 납품 (또는 대장장이 철수)"
func project_hint() -> String:
	var q := tracked()
	for o: Dictionary in q.get("objectives", []):
		var pid := str(o.get("target", ""))
		if o.type == "project" and project_problem(pid) == "":
			var npc := str(NPC_NAMES.get(str(project_defs()[pid].get("npc", "")), ""))
			return "Q → 기술·복구 탭에서 납품" + (" (또는 %s)" % npc if npc != "" else "")
	return ""


## 가방에서 납품할 수 있는 개수 (kind:crop 이면 작물 전부)
func deliver_have(target: String) -> int:
	if not target.begins_with("kind:"):
		return GameState.inventory.count_of(target)
	var n := 0
	for st: Dictionary in GameState.inventory.stacks():
		if _target_matches(target, str(st.id)):
			n += GameState.inventory.count_of(str(st.id), str(st.get("quality", "")))
	return n


## 납품한다. 모자라면 아무것도 빼지 않고 이유를 돌려준다. 성공하면 ""
func deliver(quest_id: String, index: int) -> String:
	var q := quest_def(quest_id)
	if q.is_empty() or state_of(quest_id) != ACTIVE or index < 0 or index >= q.objectives.size():
		return "지금 할 수 있는 납품이 아니에요."
	var o: Dictionary = q.objectives[index]
	var need := int(o.get("count", 1))
	if o.type != "deliver" or int(progress_of(quest_id)[index]) >= need:
		return "이미 납품했어요."
	var target := str(o.get("target", ""))
	var have := deliver_have(target)
	if have < need:
		return "%s이(가) 모자라요. (%d/%d)" % [str(o.get("text", "재료")), have, need]
	# 다 있을 때만 차감: 같은 아이템이면 낮은 품질부터, '작물 아무거나' 면 싼 작물·낮은 품질부터
	var stacks := GameState.inventory.stacks().filter(func(st: Dictionary) -> bool: return _target_matches(target, str(st.id)) if target.begins_with("kind:") else str(st.id) == target)
	var order := Quality.ids()
	stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := ItemDB.get_item(a.id).sell_price
		var pb := ItemDB.get_item(b.id).sell_price
		if pa != pb:
			return pa < pb
		return order.find(str(a.get("quality", ""))) < order.find(str(b.get("quality", ""))))
	var left := need
	for st: Dictionary in stacks:
		if left <= 0:
			break
		var take := mini(left, GameState.inventory.count_of(str(st.id), str(st.get("quality", ""))))
		GameState.inventory.remove(str(st.id), take, str(st.get("quality", "")))
		left -= take
	quests[quest_id].progress[index] = need
	_check_complete(q)
	Events.quest_changed.emit(quest_id)
	return ""


# ---------- 복구 프로젝트 (3단계): 재료·돈을 나눠 넣고, 다 차면 한 번 완료

static func project_defs() -> Dictionary:
	return data().get("projects", {})


func project_done(pid: String) -> bool:
	return projects_done.get(pid, false)


## 지금 넣을 수 있는가 (연결된 퀘스트가 진행 중이거나 기록이 생김). 못 넣으면 이유
func project_problem(pid: String) -> String:
	var p: Dictionary = project_defs().get(pid, {})
	if p.is_empty():
		return "없는 프로젝트예요."
	if project_done(pid):
		return "이미 끝났어요."
	if p.get("todo", false):
		return "아직 준비 중이에요."
	if p.has("quest") and state_of(str(p.quest)) != ACTIVE:
		return "%s 퀘스트를 받으면 시작할 수 있어요." % p.quest
	if p.has("flag") and not flags.has(str(p.flag)):
		return "MQ20 을 끝내면 시작할 수 있어요."
	return ""


## 프로젝트 요구 줄: [{key: 아이템 id 또는 "money", name, need, given, have}]
func project_rows(pid: String) -> Array[Dictionary]:
	var p: Dictionary = project_defs().get(pid, {})
	var given: Dictionary = project_given.get(pid, {})
	var rows: Array[Dictionary] = []
	for item_id: String in p.get("items", {}):
		rows.append({"key": item_id, "name": ItemDB.get_item(item_id).name, "need": int(p.items[item_id]), "given": int(given.get(item_id, 0)), "have": GameState.inventory.count_of(item_id)})
	if int(p.get("money", 0)) > 0:
		rows.append({"key": "money", "name": "돈", "need": int(p.money), "given": int(given.get("money", 0)), "have": GameState.money})
	return rows


## key(아이템 id 또는 "money")를 가진 만큼 (남은 만큼까지) 넣는다. 넣은 수 (0 이면 못 넣음)
func donate(pid: String, key: String) -> int:
	if project_problem(pid) != "":
		return 0
	for row: Dictionary in project_rows(pid):
		if row.key != key:
			continue
		var n := mini(int(row.need) - int(row.given), int(row.have))
		if n <= 0:
			return 0
		if key == "money":
			if not GameState.try_spend(n):
				return 0
		elif not GameState.inventory.remove(key, n):
			return 0
		if not project_given.has(pid):
			project_given[pid] = {}
		project_given[pid][key] = int(row.given) + n
		_try_finish_project(pid)
		Events.quest_changed.emit("")
		return n
	return 0


func _try_finish_project(pid: String) -> void:
	if project_done(pid):
		return
	for row: Dictionary in project_rows(pid):
		if int(row.given) < int(row.need):
			return
	# 해금과 완료 기록을 한자리에서 (두 번 적용되지 않게)
	projects_done[pid] = true
	var p: Dictionary = project_defs()[pid]
	for tech_id: String in p.get("unlock", []):
		techs[tech_id] = true
	if p.has("era"):
		_set_era(str(p.era))
	var unlock: Array = p.get("unlock", [])
	Events.toast.emit("복구 완료: %s%s" % [p.name, " — " + _unlock_names(unlock) if not unlock.is_empty() else ""])
	_on_event("project", pid, 1)


func _unlock_names(ids: Array) -> String:
	var all: Dictionary = data().get("techs", {})
	return " · ".join(ids.map(func(t: String) -> String: return str(all.get(t, {}).get("name", t)))) + " 해금"


# ---------- 보상 · 다음 퀘스트

## 다 한 퀘스트의 보상을 준다. 가방에 다 안 들어가면 그 퀘스트는 completed 로 두고 다음에 다시
func _try_rewards() -> void:
	if _rewarding:
		return
	_rewarding = true
	var gave := false
	for q: Dictionary in quest_defs():
		if state_of(q.id) != COMPLETED:
			continue
		var r: Dictionary = q.get("rewards", {})
		var items: Dictionary = r.get("items", {})
		if not GameState.inventory.can_add_all(items):
			Events.toast.emit("가방이 가득 차서 '%s' 보상을 받을 수 없어요. 자리를 비워 주세요." % q.title)
			continue
		# 보상과 상태 바꾸기를 한자리에서 (중간에 끊겨 두 번 받는 일이 없게)
		quests[q.id].state = REWARDED
		for item_id: String in items:
			GameState.inventory.add(item_id, int(items[item_id]))
		if int(r.get("money", 0)) > 0:
			GameState.add_money(int(r.money))
		for tech_id: String in r.get("unlock", []):
			techs[tech_id] = true
		for f: String in r.get("flags", []):
			flags[f] = true
		if r.has("era"):
			_set_era(str(r.era))
		Events.toast.emit("퀘스트 완료: %s%s" % [q.title, _reward_text(r)])
		gave = true
	_rewarding = false
	if gave:
		_activate_ready()
		Events.quest_changed.emit("")


func _reward_text(r: Dictionary) -> String:
	var parts: Array[String] = []
	for item_id: String in r.get("items", {}):
		parts.append("%s %d" % [ItemDB.get_item(item_id).name, int(r.items[item_id])])
	if int(r.get("money", 0)) > 0:
		parts.append("%d G" % int(r.money))
	return " — " + " · ".join(parts) if not parts.is_empty() else ""


func _set_era(new_era: String) -> void:
	var ids := era_ids()
	if ids.find(new_era) > ids.find(era):
		era = new_era


## 앞 퀘스트를 다 끝낸 잠긴 퀘스트를 연다. 받을 때 주는 아이템은 한 번만 (granted 저장)
func _activate_ready() -> void:
	for q: Dictionary in quest_defs():
		if state_of(q.id) != LOCKED:
			continue
		if not q.get("prerequisites", []).all(func(p: String) -> bool: return state_of(p) == REWARDED):
			continue
		quests[q.id].state = ACTIVE
		_owe_support(q)
	_refresh_state_objectives()
	_pay_support(true)
	ensure_quest_objects.call_deferred()


# ---------- 받을 때 주는 지원 물건 (MQ17 밀 4 · MQ20 밀가루 3)

## 이 퀘스트의 지원 물건을 '줄 것'으로 기록한다 (이미 기록이 있으면 그대로 — 두 번 주지 않음)
func _owe_support(q: Dictionary, given := {}) -> void:
	var give: Dictionary = q.get("on_activate_items", {})
	if give.is_empty() or support.has(q.id):
		return
	var owed := {}
	for item_id: String in give:
		if ItemDB.has_item(item_id) and int(give[item_id]) > 0:
			owed[item_id] = int(give[item_id])
	if owed.is_empty():
		return
	var got := {}
	for item_id: String in owed:
		got[item_id] = clampi(int(given.get(item_id, 0)), 0, int(owed[item_id]))
	support[q.id] = {"owed": owed, "given": got}
	quests[q.id].granted = _support_left(q.id).is_empty()


## 아직 못 준 지원 물건 {아이템: 개수}
func _support_left(quest_id: String) -> Dictionary:
	var left := {}
	var s: Dictionary = support.get(quest_id, {})
	for item_id: String in s.get("owed", {}):
		var n := int(s.owed[item_id]) - int(s.given.get(item_id, 0))
		if n > 0:
			left[item_id] = n
	return left


## 못 준 지원 물건 전체 (퀘스트 창·HUD 안내용) [{quest, item, count}]
func support_waiting() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for qid: String in support:
		var left := _support_left(qid)
		for item_id: String in left:
			out.append({"quest": qid, "item": item_id, "count": int(left[item_id])})
	return out


## 남은 지원 물건을 가방에 들어가는 만큼 준다 (기존 Inventory.add: 못 넣은 수를 돌려줌 → 그만큼은 대기).
## notify: 받는 순간·불러올 때만 '가방이 가득' 안내 (가방이 바뀔 때마다 띄우지 않게)
func _pay_support(notify := false) -> void:
	if _paying:
		return
	_paying = true
	var got: Array[String] = []
	var waiting: Array[String] = []
	for qid: String in support:
		var s: Dictionary = support[qid]
		var left := _support_left(qid)
		for item_id: String in left:
			var n := int(left[item_id])
			var put := n - GameState.inventory.add(item_id, n)
			if put > 0:
				s.given[item_id] = int(s.given.get(item_id, 0)) + put
				got.append("%s +%d" % [ItemDB.get_item(item_id).name, put])
			if put < n:
				waiting.append("%s %d개" % [ItemDB.get_item(item_id).name, n - put])
		if quests.has(qid):
			quests[qid].granted = _support_left(qid).is_empty()
	_paying = false
	if not got.is_empty():
		Events.toast.emit("퀘스트 지원: " + " · ".join(got))
	if not waiting.is_empty() and (notify or not got.is_empty()):
		Events.toast.emit("가방이 가득 차서 %s은(는) 자리가 생기면 드릴게요." % " · ".join(waiting))
	if not got.is_empty():
		Events.quest_changed.emit("")


# ---------- 저장 ("story" 섹션)

func to_data() -> Dictionary:
	return {"era": era, "techs": techs.duplicate(), "quests": quests.duplicate(true), "flags": flags.duplicate(), "legacy": legacy,
		"projects": {"given": project_given.duplicate(true), "done": projects_done.duplicate()},
		"support": support.duplicate(true)}


## 받은 데이터가 통째로 틀리면 false. 퀘스트 id 가 데이터에 없으면 건너뛰고, 데이터에 새로 생긴 퀘스트는 잠긴 상태로 시작
func load_data(d: Variant) -> bool:
	if not d is Dictionary:
		return false
	new_game()
	legacy = d.get("legacy", false) == true
	var saved_era := str(d.get("era", era))
	if saved_era in era_ids():
		era = saved_era
	var t: Variant = d.get("techs", {})
	if t is Dictionary:
		for k: Variant in t:
			if data().get("techs", {}).has(str(k)):
				techs[str(k)] = t[k] == true
	var f: Variant = d.get("flags", {})
	if f is Dictionary:
		for k: Variant in f:
			flags[str(k)] = true
	var pr: Variant = d.get("projects", {})
	if pr is Dictionary:
		var given: Variant = pr.get("given", {})
		if given is Dictionary:
			for pid: Variant in given:
				var p: Dictionary = project_defs().get(str(pid), {})
				if p.is_empty() or not given[pid] is Dictionary:
					continue
				var row := {}
				for key: Variant in given[pid]:
					var need := int(p.get("money", 0)) if str(key) == "money" else int(p.get("items", {}).get(str(key), 0))
					if need > 0:
						row[str(key)] = clampi(int(given[pid][key]), 0, need)
				project_given[str(pid)] = row
		var done: Variant = pr.get("done", {})
		if done is Dictionary:
			for pid: Variant in done:
				if project_defs().has(str(pid)) and done[pid] == true:
					projects_done[str(pid)] = true
	var qs: Variant = d.get("quests", {})
	if qs is Dictionary:
		for id: Variant in qs:
			var q := quest_def(str(id))
			var st: Variant = qs[id]
			if q.is_empty() or not st is Dictionary or not str(st.get("state", "")) in [LOCKED, ACTIVE, COMPLETED, REWARDED]:
				continue
			var prog := _zeros(q)
			var saved_prog: Variant = st.get("progress", [])
			if saved_prog is Array:
				for i in mini(prog.size(), saved_prog.size()):
					prog[i] = clampi(int(saved_prog[i]), 0, int(q.objectives[i].get("count", 1)))
			quests[q.id] = {"state": str(st.state), "progress": prog, "granted": st.get("granted", false) == true}
			if not st.has("granted"):
				quests[q.id]["_unknown_grant"] = true  # 지급 기록이 아예 없음: 아래 이전(migration)에서 주지 않는다
			var seen: Variant = st.get("seen", {})
			if seen is Dictionary and not seen.is_empty():
				var keep := {}
				for k: Variant in seen:
					if seen[k] is Array:
						keep[str(k)] = (seen[k] as Array).map(func(v: Variant) -> String: return str(v))
				quests[q.id]["seen"] = keep
	_load_support(d.get("support", null))
	_activate_ready()
	_try_rewards()
	Events.quest_changed.emit("")
	return true


## 지원 물건 기록을 되살린다. 기록이 없는 예전 저장(4단계 후속 이전)은 퀘스트의 granted 로 옮긴다:
##   granted = true  → 이미 다 줌 (그때 코드는 다 들어갈 때만 주고 같은 자리에서 true 로 바꿨다)
##   granted = false · 진행 중 → 아직 못 받음 → 지금 줄 것으로 기록 (가방이 가득했거나, 밀가루가 생기기 전에 MQ20 을 받은 저장)
##   granted = false · 완료/보상받음/잠김 → 주지 않음 (사용자 결정: 끝난 퀘스트에는 주지 않음)
##   granted 키가 아예 없음 → 줬는지 알 수 없으니 주지 않음
func _load_support(saved: Variant) -> void:
	support.clear()
	if saved is Dictionary:
		for qid: Variant in saved:
			var q := quest_def(str(qid))
			var s: Variant = saved[qid]
			if q.is_empty() or not s is Dictionary or not s.get("given", null) is Dictionary:
				continue
			_owe_support(q, s.given)
	for q: Dictionary in quest_defs():
		if q.get("on_activate_items", {}).is_empty() or support.has(q.id):
			continue
		var st: Dictionary = quests.get(q.id, {})
		if st.get("_unknown_grant", false):
			continue
		if st.get("granted", false):
			_owe_support(q, q.on_activate_items)
		elif str(st.get("state", LOCKED)) == ACTIVE:
			_owe_support(q)
	for qid: String in quests:
		quests[qid].erase("_unknown_grant")
