extends Sprite2D

## Сколько секунд вспышка гаснет, после чего удаляет себя.
@export var duration := 0.15


func _ready() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_callback(queue_free)
