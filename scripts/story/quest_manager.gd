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

static var _data: Dictionary = {}
## 지금 게임의 QuestManager (상점·건설·대장간·광산 입구 같은 곳이 잠금을 물어볼 때, 3단계)
static var current: QuestManager = null

var world: FarmWorld
## 퀘스트 id → {"state", "progress": [목표별 수], "granted": on_activate_items 를 줬는가}
var quests := {}
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
	# 가게 NPC 에게 말을 걸면 (Npc.room_id: store · smith · machine)
	Events.npc_talk_requested.connect(func(npc: Node) -> void:
		if "room_id" in npc and str(npc.room_id) != "":
			_on_event("talk_npc", str(npc.room_id), 1))
	if world:
		world.obstacles.cleared.connect(func(_cell: Vector2i, def: ObstacleDef) -> void: _on_event("clear_obstacle", def.id, 1))


func _process(_delta: float) -> void:
	# 방문 판정 (상태형): 광장 — 농장 맵에서 개울 다리 동쪽
	if world == null or world.area != "farm":
		return
	var plaza: Dictionary = data().get("areas", {}).get("plaza", {})
	if not flags.has("visited:plaza") and world.player.my_cell().x >= int(plaza.get("min_x", 9999)):
		mark("visited:plaza")


# ---------- 새 게임 · 상태

## 새 게임: 개척시대 + 시작 기술, MQ01 진행 중
func new_game() -> void:
	quests.clear()
	flags.clear()
	techs.clear()
	project_given.clear()
	projects_done.clear()
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

func _on_event(type: String, target: String, amount: int) -> void:
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
			var need := int(o.get("count", 1))
			if int(prog[i]) < need:
				prog[i] = mini(need, int(prog[i]) + amount)
				changed = true
		if changed:
			_check_complete(q)
	if changed:
		Events.quest_changed.emit("")


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


## 진행 중인 퀘스트 중 이 NPC 와 관련된 것 (대화 창에 한 줄 안내)
func quests_for_npc(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for q: Dictionary in active_quests():
		for o: Dictionary in q.get("objectives", []):
			if str(o.get("npc", o.get("target", ""))) == npc_id and o.type in ["deliver", "talk_npc"]:
				out.append(q)
				break
	return out


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
		var give: Dictionary = q.get("on_activate_items", {})
		if not give.is_empty() and not quests[q.id].granted and GameState.inventory.can_add_all(give):
			quests[q.id].granted = true
			for item_id: String in give:
				GameState.inventory.add(item_id, int(give[item_id]))
	_refresh_state_objectives()


# ---------- 저장 ("story" 섹션)

func to_data() -> Dictionary:
	return {"era": era, "techs": techs.duplicate(), "quests": quests.duplicate(true), "flags": flags.duplicate(), "legacy": legacy,
		"projects": {"given": project_given.duplicate(true), "done": projects_done.duplicate()}}


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
	_activate_ready()
	_try_rewards()
	Events.quest_changed.emit("")
	return true
