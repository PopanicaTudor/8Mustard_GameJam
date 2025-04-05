extends Area2D

@export var next_level_scene: PackedScene

func _ready():
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body):
	if body.name == "Player":
		get_tree().change_scene_to_packed(next_level_scene)
