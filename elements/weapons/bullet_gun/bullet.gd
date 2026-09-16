extends Area2D
class_name Bullet

const IMPACT_SCENE = preload("res://elements/weapons/bullet_gun/projectile.tscn")
const HULL_IMPACT_SCENE = preload("res://elements/weapons/bullet_gun/impact.tscn")

## Скорость полёта пули, пикселей в секунду. Должна быть заметно выше скорости корабля.
@export var speed := 800.0
## Сколько здоровья снимает одно попадание.
@export var damage := 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Обе подписки здесь, а не в сцене: имя обработчика тогда наше, а не склеенное
	# редактором из имени узла. Наследник (ракета) получает их вместе с super._ready(),
	# и узел ScreenExit обязан быть в его сцене тоже.
	$ScreenExit.screen_exited.connect(_on_screen_exited)


func _physics_process(delta: float) -> void:
	# Пуля летит туда, куда повёрнута: у пули игрока поворот 0 и она идёт вверх,
	# у вражеской корень развёрнут на 180° и она идёт вниз. Отдельный параметр
	# направления не нужен — хватает угла узла, выставленного в сцене.
	position += get_velocity() * delta


## Скорость пули в пикселях в секунду вместе с направлением. По ней враги предсказывают,
## где пройдёт пуля, чтобы увернуться заранее.
func get_velocity() -> Vector2:
	return Vector2.UP.rotated(rotation) * speed


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_spawn_impact()
	_spawn_hull_impact(body)
	queue_free()


func _spawn_impact() -> void:
	var impact := IMPACT_SCENE.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position
	# Брызги на спрайте нарисованы вверх, как и полёт пули при нулевом повороте.
	# Разворот на 180° отправляет их навстречу стрелку, а основание — на корпус цели.
	impact.global_rotation = global_rotation + PI


# Пуля попадает только в корабли (маски пуль не включают стены), а у каждого корабля
# есть компонент Tilt, по которому брызги доворачиваются вместе с корпусом.
func _spawn_hull_impact(body: Node2D) -> void:
	var impact: Impact = HULL_IMPACT_SCENE.instantiate()
	impact.attach(body, body.tilt, global_position)
	get_tree().current_scene.add_child(impact)


# Снаряд ушёл за край экрана. Без этого промахи копились бы в дереве до конца уровня:
# сами они не исчезают, а летят дальше в пустоту. Область слежения задаёт прямоугольник
# rect у ScreenExit, а не спрайт, поэтому её размер правится в сцене.
func _on_screen_exited() -> void:
	queue_free()
