class_name SoilTile
extends RefCounted
## 갈아 놓은 밭 한 칸의 상태.

var watered := false
var seed_id := ""      # 심은 씨앗 아이템 id ("" 이면 빈 밭)
var days_grown := 0
## 한 번 거둔 뒤 다시 열리는 중인가 (딸기처럼 regrow_days 가 있는 작물)
var regrowing := false


func has_crop() -> bool:
	return seed_id != ""


func seed_item() -> ItemDef:
	return ItemDB.get_item(seed_id) if has_crop() else null


## 지금 다 자라는 데 필요한 날 수 (처음엔 grow_days, 다시 열리는 중엔 regrow_days)
func days_needed() -> int:
	var seed_def := seed_item()
	if seed_def == null:
		return 0
	return seed_def.regrow_days if regrowing else seed_def.grow_days


## 0.0(막 심음) ~ 1.0(수확 가능)
func growth() -> float:
	var need := days_needed()
	if need <= 0:
		return 0.0
	return clampf(float(days_grown) / need, 0.0, 1.0)


func is_mature() -> bool:
	return has_crop() and growth() >= 1.0


## 하루가 지날 때. 물을 준 작물만 자란다.
func advance_day() -> void:
	if has_crop() and watered and not is_mature():
		days_grown += 1
	watered = false


## 거둔 뒤: 다시 열리는 작물은 남아서 처음부터 다시 자라고, 아니면 빈 밭이 된다.
func after_harvest() -> void:
	var seed_def := seed_item()
	days_grown = 0
	if seed_def != null and seed_def.regrows():
		regrowing = true
	else:
		seed_id = ""
		regrowing = false


func to_dict() -> Dictionary:
	return {"watered": watered, "seed_id": seed_id, "days_grown": days_grown, "regrowing": regrowing}


static func from_dict(d: Dictionary) -> SoilTile:
	var tile := SoilTile.new()
	tile.watered = d.get("watered", false)
	tile.seed_id = d.get("seed_id", "")
	tile.days_grown = int(d.get("days_grown", 0))
	tile.regrowing = d.get("regrowing", false)
	return tile
