class_name Townsfolk
extends Node2D
## 광장 주민·동물 하나 (사용자 요청: 무드 이미지의 고양이·강아지·벤치 할머니·바구니 든 아이). 정의는 data/townsfolk.json.
##   cat    분수 둘레를 어슬렁거리다 낮잠, 플레이어가 가까이 오면 몇 걸음 따라옴
##   dog    잔디밭을 뛰어다니다 앉아서 꼬리 흔들기
##   sitter 제자리 (벤치 할머니: 뜨개질)
##   walker 정해진 곳(stops) 사이를 돌길로 오감
## [E]: 동물은 쓰다듬기(하트, 보상 없음 — 사용자 결정), 사람은 대화 창 (날마다·계절·날씨에 따라 대사가 바뀜).
## 지나갈 수 있다 (길을 막지 않음). 밤 9시 이후 night_away 인 주민은 집에 가서 안 보이고, 고양이는 잠든다.
## 그림은 오른쪽을 보는 프레임을 가로로 늘어놓은 한 장 (make_art.make_townsfolk). 왼쪽으로 갈 때는 뒤집는다.

const DATA_PATH := "res://data/townsfolk.json"
const TILE := Art.TILE
const REACH := 16.0
const NIGHT_FROM := 21 * 60
## 고양이가 따라오기 시작하는 거리(칸) / 따라오는 시간(초)
const FOLLOW_NEAR := 3.0
const FOLLOW_SECONDS := 4.0

var data := {}
var kind := ""
var npc_name := ""
var greeting := ""
var options: Array = [["고마워요", ""]]
var prompt := ""
var world: FarmWorld
var home := Vector2.ZERO
var path: Array[Vector2] = []
var away := false

var _sprite: Sprite2D
var _anim := 0.0
var _rest := 1.0
var _napping := false
var _follow_left := 0.0
var _follow_cooldown := 0.0
var _stop := 0
var _rng := RandomNumberGenerator.new()


static func all_defs() -> Array:
	return DataFile.load_dict(DATA_PATH).get("folk", [])


## 광장에 정의된 주민·동물을 모두 만든다
static func spawn_all(farm_world: FarmWorld) -> Array[Townsfolk]:
	var out: Array[Townsfolk] = []
	for d: Variant in all_defs():
		if d is Dictionary:
			var t := Townsfolk.new()
			t.setup(d, farm_world)
			farm_world.objects.add_child(t)
			out.append(t)
	return out


func setup(d: Dictionary, farm_world: FarmWorld) -> void:
	data = d
	world = farm_world
	kind = str(d.get("kind", "sitter"))
	npc_name = str(d.get("name", ""))
	name = "Folk_" + str(d.get("id", kind))
	home = world.cell_center(DataFile.to_vector2i(d.get("home"), Vector2i.ZERO)) + Vector2(0, 4)
	if kind == "sitter":
		home.y += 3   # 벤치(소품)보다 앞에 그려지게 발밑을 조금 아래로
	position = home
	_rng.seed = hash(str(d.get("id", "")))
	prompt = "[E] %s 쓰다듬기" % npc_name if is_animal() else "[E] %s에게 말 걸기" % npc_name


func is_animal() -> bool:
	return kind in ["cat", "dog"]


func _ready() -> void:
	add_to_group("interactables")
	add_to_group("townsfolk")
	_sprite = Sprite2D.new()
	_sprite.texture = load(str(data.get("texture", "")))
	_sprite.hframes = maxi(1, int(data.get("frames", 1)))
	_sprite.centered = true
	if _sprite.texture:
		_sprite.offset = Vector2(0, -_sprite.texture.get_height() / 2.0)
		if kind == "sitter":
			_sprite.offset.y -= 6   # 벤치 앉는 판 위에 앉은 모습
	add_child(_sprite)
	_update_away()


func _process(delta: float) -> void:
	step(delta)


## 한 번에 delta 초만큼 움직인다 (점검에서 직접 부른다)
func step(delta: float) -> void:
	_update_away()
	if away:
		return
	_anim += delta
	match kind:
		"cat":
			_step_cat(delta)
		"dog":
			_step_dog(delta)
		"walker":
			_step_walker(delta)
		_:
			_sprite.frame = int(_anim / 0.5) % _sprite.hframes   # 뜨개질


# ---------- 움직임

func _speed() -> float:
	return float(data.get("speed", 20))


func _roam() -> float:
	return float(data.get("roam", 5)) * TILE


## 목표 쪽으로 걸어간다. 도착하면 true
func _walk_to(target: Vector2, delta: float, speed: float) -> bool:
	var to := target - position
	if to.length() <= speed * delta + 0.5:
		position = target
		return true
	position += to.normalized() * speed * delta
	if absf(to.x) > 0.5:
		_sprite.flip_h = to.x < 0.0
	return false


func _pick_spot() -> Vector2:
	for i in 12:
		var off := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _roam()
		var cell := world.world_to_cell(home + off)
		if MapLayout.char_at(cell) in ["p", ".", ","]:
			return world.cell_center(cell) + Vector2(0, 4)
	return home


func _player_dist() -> float:
	return world.player.global_position.distance_to(global_position) / TILE


func _step_cat(delta: float) -> void:
	_follow_cooldown = maxf(0.0, _follow_cooldown - delta)
	if _napping:
		_sprite.frame = 3
		_rest -= delta
		if _rest <= 0.0:
			_napping = false
			_rest = 1.0
		return
	# 플레이어가 가까이 오면 몇 걸음 따라옴
	if _follow_left <= 0.0 and _follow_cooldown <= 0.0 and _player_dist() < FOLLOW_NEAR:
		_follow_left = FOLLOW_SECONDS
	if _follow_left > 0.0:
		_follow_left -= delta
		if _follow_left <= 0.0:
			_follow_cooldown = 10.0
		var target := world.player.global_position + Vector2(-14 if world.player.global_position.x > position.x else 14, 2)
		if position.distance_to(home) < _roam() * 1.5 and not _walk_to(target, delta, _speed() * 1.6):
			_sprite.frame = 1 + int(_anim / 0.2) % 2
		else:
			_sprite.frame = 0
		return
	_wander(delta, 0.25)


func _step_dog(delta: float) -> void:
	_wander(delta, 0.0)
	if _rest > 0.0:
		_sprite.frame = 3 if int(_anim / 0.25) % 2 == 0 else 0   # 앉아서 꼬리 흔들기


## 쉬었다가 근처 빈 땅으로 걸어가기를 되풀이. nap_chance: 쉬는 대신 낮잠 잘 확률
func _wander(delta: float, nap_chance: float) -> void:
	if _rest > 0.0:
		_rest -= delta
		_sprite.frame = 0
		if _rest <= 0.0:
			if _rng.randf() < nap_chance:
				_napping = true
				_rest = _rng.randf_range(6.0, 12.0)
			else:
				path = [_pick_spot()]
		return
	if path.is_empty():
		_rest = _rng.randf_range(1.5, 4.0)
		return
	_sprite.frame = 1 + int(_anim / (0.12 if kind == "dog" else 0.2)) % 2
	if _walk_to(path[0], delta, _speed()):
		path.remove_at(0)
		if path.is_empty():
			_rest = _rng.randf_range(1.5, 4.0)


func _step_walker(delta: float) -> void:
	var stops: Array = data.get("stops", [])
	if stops.is_empty():
		return
	if _rest > 0.0:
		_rest -= delta
		_sprite.frame = 0
		_sprite.flip_h = false
		if _rest <= 0.0:
			_stop = (_stop + 1) % stops.size()
			path = TownPaths.route(world, world.world_to_cell(position), DataFile.to_vector2i(stops[_stop], Vector2i.ZERO))
		return
	if path.is_empty():
		_rest = _rng.randf_range(3.0, 6.0)
		return
	var to := path[0] - position
	_sprite.frame = 3 if absf(to.x) > absf(to.y) else 1 + int(_anim / 0.25) % 2
	if _walk_to(path[0], delta, _speed()):
		path.remove_at(0)


# ---------- 밤

func _update_away() -> void:
	var night := GameState.minutes >= NIGHT_FROM
	var was := away
	away = night and data.get("night_away", false)
	visible = not away
	if night and kind == "cat":
		_napping = true
		_rest = 999.0
	if was and not away:
		position = home   # 아침: 처음 자리로
		path.clear()


# ---------- [E]

func interact_point() -> Vector2:
	return global_position + Vector2(0, 2)


func can_interact(from: Vector2) -> bool:
	return not away and from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	if away:
		return
	if is_animal():
		_heart()
		Events.toast.emit(str(data.get("pet", "")))
		return
	greeting = line_for(GameState.day)
	Events.npc_talk_requested.emit(self)


## 오늘 할 말: 비·눈이 오면 날씨 대사가 섞이고, 아니면 계절 대사 중 날마다 하나
func line_for(day: int) -> String:
	var lines: Dictionary = data.get("lines", {})
	var pool: Array = []
	if GameState.weather in ["rain", "storm"] and lines.has("rain"):
		pool = lines.rain
	else:
		pool = lines.get(Calendar.season_of(day), [])
	if pool.is_empty():
		return "안녕!"
	return str(pool[posmod(day + hash(npc_name), pool.size())])


## 머리 위로 떠오르는 하트 (쓰다듬기)
func _heart() -> void:
	var heart := Node2D.new()
	heart.position = Vector2(0, -_sprite.texture.get_height() - 2 if _sprite.texture else -16)
	heart.draw.connect(func() -> void:
		var c := Color("e0607e")
		for r: Array in [[-3, -2, 2, 1], [1, -2, 2, 1], [-4, -1, 8, 2], [-3, 1, 6, 1], [-2, 2, 4, 1], [-1, 3, 2, 1]]:
			heart.draw_rect(Rect2(r[0], r[1], r[2], r[3]), c))
	add_child(heart)
	var tween := heart.create_tween()
	tween.tween_property(heart, "position:y", heart.position.y - 10, 0.9)
	tween.parallel().tween_property(heart, "modulate:a", 0.0, 0.9)
	tween.tween_callback(heart.queue_free)
