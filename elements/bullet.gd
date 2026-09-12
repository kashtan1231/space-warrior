extends Area2D

const IMPACT_SCENE = preload("res://elements/impact.tscn")

## Скорость полёта пули, пикселей в секунду. Должна быть заметно выше скорости корабля.
@export var speed := 800.0
## Сколько здоровья снимает одно попадание.
@export var damage := 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# Пуля летит туда, куда повёрнута: у пули игрока поворот 0 и она идёт вверх,
	# у вражеской корень развёрнут на 180° и она идёт вниз. Отдельный параметр
	# направления не нужен — хватает угла узла, выставленного в сцене.
	position += Vector2.UP.rotated(rotation) * speed * delta


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_spawn_impact()
	queue_free()


func _spawn_impact() -> void:
	var impact := IMPACT_SCENE.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position


func _on_visible_on_screen_enabler_2d_screen_exited() -> void:
	queue_free()
