class_name SkyStation
extends Interactable
## 광장의 오래된 비행선 정류장 (BUILD_FARM_PLAN §89, §90).
##   복구 전: [E] → 복구 창 (돈 + 재료를 한 번에 납품, SkyMarket.restore)
##   복구 뒤: [E] → 비행선을 타고 하늘섬으로 (편도 게임 시계 1시간, FarmWorld.travel)

const BROKEN := preload("res://assets/art/sky_station_broken.png")
const RESTORED := preload("res://assets/art/sky_station.png")

var _sprite: Sprite2D


func _init() -> void:
	size_tiles = Vector2i(4, 3)
	solid_height = 20.0
	door_x = 32.0


func _ready() -> void:
	texture = RESTORED if SkyMarket.is_open() else BROKEN
	super._ready()
	for child in get_children():
		if child is Sprite2D:
			_sprite = child
	Events.sky_station_restored.connect(refresh)
	Events.game_loaded.connect(refresh)
	refresh()


## 복구하면 그림·안내가 바뀐다
func refresh() -> void:
	var open := SkyMarket.is_open()
	prompt = "[E] 비행선 타기 (하늘섬)" if open else "[E] 오래된 비행선 정류장"
	if _sprite:
		_sprite.texture = RESTORED if open else BROKEN
		_sprite.offset = Vector2(0, -_sprite.texture.get_height())


func interact(_player: Node) -> void:
	if SkyMarket.is_open():
		Events.travel_requested.emit("sky")
	else:
		Events.sky_station_requested.emit()
