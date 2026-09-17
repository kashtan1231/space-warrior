extends Area2D
class_name Bullet

## Скорость полёта пули, пикселей в секунду. Должна быть заметно выше скорости корабля.
@export var speed := 800.0
## Сколько здоровья снимает одно попадание.
@export var damage := 1

@export_group("Impact")
## Вспышка в точке попадания. Остаётся там, где снаряд коснулся цели, и доигрывает на месте,
## даже если корабль уже улетел. Рисунок в сцене должен смотреть вверх: при спавне он
## разворачивается навстречу стрелку, а поворот корня сцены при этом перезаписывается.
@export var impact_scene: PackedScene
## Брызги на обшивке: прилипают к кораблю, едут и заваливаются вместе с ним, см. impact.gd.
## У пули и у ракеты это разные сцены с одним скриптом, поэтому размер, кадры и направление
## рисунка правятся в самой сцене эффекта.
@export var hull_impact_scene: PackedScene

# Хитбокс корабля собран из нескольких форм, и снаряд входит сразу в две, когда они
# перекрываются: сигнал приходит по каждой, а queue_free снимает узел только в конце кадра.
# Без флага одно попадание засчиталось бы дважды.
var _spent := false


func _ready() -> void:
	# body_shape_entered, а не body_entered: сигнал приносит ещё и номер формы, в которую
	# вошёл снаряд, — по нему ракета находит место для пламени, см. flammable.gd.
	body_shape_entered.connect(_on_body_shape_entered)
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


# Физика сообщает номер формы внутри тела, а не сам узел. Разворачиваем его здесь, чтобы
# наследникам попадание досталось в готовом виде. Тип узла зависит от корабля: у врагов
# корпус собран из CollisionShape2D, у игрока — из CollisionPolygon2D, и огонь умеет
# сесть на оба, см. flammable.gd.
func _on_body_shape_entered(_body_rid: RID, body: Node2D, body_shape_index: int,
		_local_shape_index: int) -> void:
	if _spent:
		return
	_spent = true
	var target := body as CollisionObject2D
	var owner_id := target.shape_find_owner(body_shape_index)
	_on_hit(body, target.shape_owner_get_owner(owner_id) as Node2D)


# Что снаряд делает с тем, во что попал. Наследник добавляет своё до super(), потому что
# в конце снаряд удаляет себя.
func _on_hit(body: Node2D, _shape: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_spawn_impact()
	_spawn_hull_impact(body)
	queue_free()


func _spawn_impact() -> void:
	var impact: Node2D = impact_scene.instantiate()
	get_tree().current_scene.add_child(impact)
	impact.global_position = global_position
	# Брызги на спрайте нарисованы вверх, как и полёт пули при нулевом повороте.
	# Разворот на 180° отправляет их навстречу стрелку, а основание — на корпус цели.
	impact.global_rotation = global_rotation + PI


# Пуля попадает только в корабли (маски пуль не включают стены), а у каждого корабля
# есть компонент Tilt, по которому брызги доворачиваются вместе с корпусом.
func _spawn_hull_impact(body: Node2D) -> void:
	var impact: Impact = hull_impact_scene.instantiate()
	impact.attach(body, body.tilt, global_position, global_rotation)
	get_tree().current_scene.add_child(impact)


# Снаряд ушёл за край экрана. Без этого промахи копились бы в дереве до конца уровня:
# сами они не исчезают, а летят дальше в пустоту. Область слежения задаёт прямоугольник
# rect у ScreenExit, а не спрайт, поэтому её размер правится в сцене.
func _on_screen_exited() -> void:
	queue_free()
