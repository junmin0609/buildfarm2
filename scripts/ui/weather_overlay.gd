class_name WeatherOverlay
extends Control
## 비·눈 화면 효과. 화면 전체에 빗줄기나 눈송이를 그린다 (게임 화면 위, 다른 UI 아래).
## 날씨는 Events.weather_changed 로 받는다. 맑음·흐림이면 숨는다 (흐림은 FarmWorld 의 화면 색으로만).

const RAIN_COUNT := 140
const SNOW_COUNT := 90
const RAIN_COLOR := Color(0.86, 0.93, 1.0, 0.5)
const SNOW_COLOR := Color(1.0, 1.0, 1.0, 0.85)

var weather := ""
var _drops: Array[Vector3] = []   # x(0~1), y(0~1), 속도 배율
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.weather_changed.connect(set_weather)
	# 가게 안에서는 비·눈이 안 보인다 (농장·하늘섬에서만)
	Events.area_changed.connect(func(area: String) -> void:
		indoors = area not in ["farm", "sky"]
		visible = (weather == "rain" or weather == "snow") and not indoors)
	set_weather(GameState.weather)


## 가게 실내에 있는가
var indoors := false


func set_weather(new_weather: String) -> void:
	weather = new_weather
	visible = (weather == "rain" or weather == "snow") and not indoors
	_drops.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in (RAIN_COUNT if weather == "rain" else SNOW_COUNT):
		_drops.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.7, 1.3)))
	queue_redraw()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var area := size
	for d in _drops:
		if weather == "rain":
			var y := fposmod(d.y * area.y + _t * 700.0 * d.z, area.y + 40.0) - 20.0
			var x := fposmod(d.x * area.x - _t * 160.0 * d.z, area.x + 40.0) - 20.0
			draw_line(Vector2(x, y), Vector2(x - 5, y + 16), RAIN_COLOR, 2.0)
		else:
			var y := fposmod(d.y * area.y + _t * 55.0 * d.z, area.y + 10.0) - 5.0
			var x := d.x * area.x + sin(_t * 1.4 + d.x * 23.0) * 12.0
			draw_rect(Rect2(Vector2(x, y).floor(), Vector2(6, 6)), SNOW_COLOR)
