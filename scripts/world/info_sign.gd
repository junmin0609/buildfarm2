class_name InfoSign
extends Prop
## [E] 로 읽을 수 있는 팻말 (스토리: MQ01 농장 안내판). 읽으면 글을 띄우고 Events.sign_read 를 보낸다.
## 그림·충돌은 Prop 그대로.

const REACH := 18.0

## 퀘스트가 알아보는 이름
@export var sign_id := ""
## 읽었을 때 보여 줄 글
@export_multiline var message := ""

var prompt := "[E] 안내판 읽기"


func _ready() -> void:
	super._ready()
	add_to_group("interactables")


func interact_point() -> Vector2:
	return global_position + Vector2(0, 6)


func can_interact(from: Vector2) -> bool:
	return from.distance_to(interact_point()) <= REACH


func interact(_player: Node) -> void:
	if message != "":
		Events.toast.emit(message)
	Events.sign_read.emit(sign_id)
