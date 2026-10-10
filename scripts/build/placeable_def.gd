class_name PlaceableDef
extends RefCounted
## 설치할 수 있는 시설 한 종류의 정의. data/placeables.json 한 항목이 하나가 된다.
##
## 새 시설 추가: JSON 에 항목을 넣으면 건설 창·미리보기·설치·이동·철거가 그대로 동작한다.
## 특별한 동작(자동 물주기 등)이 필요하면 Placeable 을 상속한 스크립트를 만들어 "script" 에 적는다.
##
## 회전 (§54) 관련 항목
##   "directional": true          방향이 있는 시설 (컨베이어·입출력 포트가 있는 기계 등). 미리보기에 방향 화살표.
##   "rotatable": true/false      R 로 돌릴 수 있는지. 없으면: 방향이 있거나 직사각형이면 true, 정사각형이면 false
##   "rotated_textures": [...]    방향(0 아래, 1 왼쪽, 2 위, 3 오른쪽)별 그림. 2개면 가로/세로로 번갈아 쓴다.
##                                없으면 모든 방향에서 "texture" 를 쓴다.
##   "materials": {"wood": 100}   돈("price") 말고 함께 드는 재료. 철거하면 돈과 함께 돌려받는다.
## 시설 전용 값(온실의 "door_width" 등)은 data 에서 그대로 꺼내 쓴다.

var id := ""
var name := ""
var category := ""
var description := ""
## 바닥에서 차지하는 칸 수 (가로, 세로). 회전 0 기준
var size := Vector2i.ONE
var texture: Texture2D
var rotated_textures: Array[Texture2D] = []
var price := 0
## 재료 아이템 id -> 개수
var materials := {}
## true 면 플레이어가 지나갈 수 없다 (장식 깔개 같은 건 false)
var solid := true
var directional := false
var rotatable := false
## 비어 있으면 기본 Placeable, 아니면 그 스크립트 (Placeable 상속)
var script_path := ""
## JSON 항목 그대로 (시설 스크립트가 자기 전용 값을 읽는다)
var data := {}


static func from_dict(def_id: String, d: Dictionary) -> PlaceableDef:
	var def := PlaceableDef.new()
	def.id = def_id
	def.name = d.get("name", def_id)
	def.category = d.get("category", "")
	def.description = d.get("description", "")
	var s: Array = d.get("size", [1, 1])
	def.size = Vector2i(int(s[0]), int(s[1]))
	def.texture = load(d.get("texture", "")) if d.has("texture") else null
	for path: String in d.get("rotated_textures", []):
		def.rotated_textures.append(load(path))
	def.price = int(d.get("price", 0))
	def.solid = d.get("solid", true)
	def.directional = d.get("directional", false)
	def.rotatable = d.get("rotatable", def.directional or def.size.x != def.size.y)
	def.script_path = d.get("script", "")
	var mats: Variant = d.get("materials", {})
	if mats is Dictionary:
		for mat_id: String in mats:
			def.materials[mat_id] = int(mats[mat_id])
	def.data = d
	return def


## turns 번 돌렸을 때 차지하는 칸 수
func size_for(turns: int) -> Vector2i:
	return Vector2i(size.y, size.x) if posmod(turns, 2) == 1 else size


func texture_for(turns: int) -> Texture2D:
	if rotated_textures.is_empty():
		return texture
	return rotated_textures[posmod(turns, 4) % rotated_textures.size()]


## "3000 G + 나무 100 + 돌 100"
func cost_text() -> String:
	return cost_text_of(price, materials)


## 돈 없이 재료만 드는 시설(컨베이어: "컨베이어 1")은 "0 G" 를 빼고 보여 준다
static func cost_text_of(money: int, mats: Dictionary) -> String:
	var parts := ["%d G" % money] if money > 0 or mats.is_empty() else []
	for mat_id: String in mats:
		var mat := ItemDB.get_item(mat_id)
		parts.append("%s %d" % [mat.name if mat else mat_id, mats[mat_id]])
	return " + ".join(parts)


## 기계상점에서 사서 놓는 시설이면 그 아이템 (사용자 결정: 기계는 아이템으로 사서 설치). 아니면 null
## (돈 없이 재료 하나만 드는데 그 재료가 기계·컨베이어 아이템인 경우)
func machine_item() -> ItemDef:
	if price > 0 or materials.size() != 1:
		return null
	var item := ItemDB.get_item(str(materials.keys()[0]))
	return item if item and item.shop in ["machine", "smith"] else null  # 용광로는 대장간에서 (스토리 결정 6)


## 설치할 돈·재료가 있는지. 모자라면 이유, 충분하면 ""
func afford_problem(inv: Inventory) -> String:
	var machine := machine_item()
	if machine and inv.count_of(machine.id) < 1:
		return "가방에 %s이(가) 없어요. 기계상점에서 사 오세요." % machine.name
	if GameState.money < price:
		return "돈이 부족해요. (%d G 필요)" % price
	for mat_id: String in materials:
		if inv.count_of(mat_id) < int(materials[mat_id]):
			var mat := ItemDB.get_item(mat_id)
			return "%s이(가) 부족해요. (%d개 필요)" % [mat.name if mat else mat_id, materials[mat_id]]
	return ""
