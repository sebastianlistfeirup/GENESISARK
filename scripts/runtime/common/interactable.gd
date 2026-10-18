class_name Interactable
extends Area3D
## Anything the captain can use. Shows object, action and consequence BEFORE
## activation (bible p.6). Emits `used`; the scene controller issues the command.

signal used(interactable: Interactable)

@export var interact_id: String = ""
@export var title: String = ""
@export var verb: String = "Brug"
@export var consequence: String = ""
@export var locked: bool = false
@export var locked_reason: String = ""
## Seconds the interact key must be held (e.g. 8 s sampling). 0 = instant.
@export var hold_time: float = 0.0
@export var radius: float = 1.8


func _ready() -> void:
	collision_layer = 4  # "interactable"
	collision_mask = 0
	monitorable = true
	monitoring = false
	if get_child_count() == 0 or not _has_shape():
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = radius
		cs.shape = sp
		cs.position.y = 1.0
		add_child(cs)


func _has_shape() -> bool:
	for c: Node in get_children():
		if c is CollisionShape3D:
			return true
	return false


func prompt_text() -> String:
	if locked:
		return "%s — %s" % [title, locked_reason if not locked_reason.is_empty() else Loc.t("locked")]
	return "[%s] %s %s" % [SettingsService.binding_text("interact"), verb, title]


func use() -> void:
	if locked:
		AudioService.ui("ui_error")
		return
	AudioService.play("sfx_interact")
	used.emit(self)
