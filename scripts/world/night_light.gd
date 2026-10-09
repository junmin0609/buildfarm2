class_name NightLight
extends PointLight2D
## 저녁에 켜지는 따뜻한 불빛 (무드 개편: 가로등·가게 창문·문 둘레가 노랗게 밝아짐).
## FarmWorld 가 시계에 맞춰 "night_lights" 그룹 전체의 밝기(set_night)를 바꾼다. 낮에는 꺼 둔다.

const GROUP := "night_lights"
const COLOR := Color(1.0, 0.78, 0.45)
## 가장 밝을 때의 세기
const MAX_ENERGY := 0.9

static var _texture: GradientTexture2D


## radius: 빛이 닿는 반지름(px)
static func make(pos: Vector2, radius := 40.0) -> NightLight:
	var light := NightLight.new()
	light.position = pos
	light.texture_scale = radius * 2.0 / 64.0
	return light


static func shared_texture() -> GradientTexture2D:
	if _texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.45, Color(1, 1, 1, 0.45))
		_texture = GradientTexture2D.new()
		_texture.gradient = gradient
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		_texture.width = 64
		_texture.height = 64
	return _texture


func _ready() -> void:
	texture = shared_texture()
	color = COLOR
	energy = 0.0
	enabled = false
	add_to_group(GROUP)
	var world := get_tree().get_first_node_in_group("farm_world")
	if world and world.has_method("night_factor"):
		set_night(world.night_factor())


## 0 낮(꺼짐) ~ 1 밤(가장 밝음)
func set_night(factor: float) -> void:
	energy = MAX_ENERGY * clampf(factor, 0.0, 1.0)
	enabled = energy > 0.01
