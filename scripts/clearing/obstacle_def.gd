class_name ObstacleDef
extends RefCounted
## 개간 장애물 한 종류 (잡초, 돌, 나뭇가지, 그루터기 ...). data/obstacles.json 의 "types" 한 항목.

var id := ""
var name := ""
var textures: Array[Texture2D] = []
## 치울 수 있는 도구 종류 (ItemDef.tool_type): "hoe", "axe", "pickaxe"
var tools: Array[String] = []
## 필요한 최소 도구 등급. 기본 도구는 1, 대장간 강화 도구는 2 이상
var tier := 1
## 몇 번 쳐야 부서지는지
var hits := 1
## true 면 지나갈 수 없다
var solid := true
## [{"item": id, "min": n, "max": n}]
var drops: Array = []


static func from_dict(def_id: String, d: Dictionary) -> ObstacleDef:
	var def := ObstacleDef.new()
	def.id = def_id
	def.name = d.get("name", def_id)
	for path: String in d.get("textures", []):
		def.textures.append(load(path))
	for t: String in d.get("tools", []):
		def.tools.append(t)
	def.tier = int(d.get("tier", 1))
	def.hits = maxi(1, int(d.get("hits", 1)))
	def.solid = d.get("solid", true)
	def.drops = d.get("drops", [])
	return def
