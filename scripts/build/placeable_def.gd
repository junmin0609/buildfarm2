class_name PlaceableDef
extends RefCounted
## 설치할 수 있는 시설 한 종류의 정의. data/placeables.json 한 항목이 하나가 된다.
##
## 새 시설 추가: JSON 에 항목을 넣으면 건설 창·미리보기·설치·이동·철거가 그대로 동작한다.
## 특별한 동작(자동 물주기 등)이 필요하면 Placeable 을 상속한 스크립트를 만들어 "script" 에 적는다.

var id := ""
var name := ""
var category := ""
var description := ""
## 바닥에서 차지하는 칸 수 (가로, 세로)
var size := Vector2i.ONE
var texture: Texture2D
var price := 0
## true 면 플레이어가 지나갈 수 없다 (장식 깔개 같은 건 false)
var solid := true
## 비어 있으면 기본 Placeable, 아니면 그 스크립트 (Placeable 상속)
var script_path := ""


static func from_dict(def_id: String, d: Dictionary) -> PlaceableDef:
	var def := PlaceableDef.new()
	def.id = def_id
	def.name = d.get("name", def_id)
	def.category = d.get("category", "")
	def.description = d.get("description", "")
	var s: Array = d.get("size", [1, 1])
	def.size = Vector2i(int(s[0]), int(s[1]))
	def.texture = load(d.get("texture", "")) if d.has("texture") else null
	def.price = int(d.get("price", 0))
	def.solid = d.get("solid", true)
	def.script_path = d.get("script", "")
	return def
