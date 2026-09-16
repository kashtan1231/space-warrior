extends CharacterBody2D
class_name Enemy

## Общая часть всех вражеских кораблей: здоровье и гибель, вспышка попадания,
## расталкивание соседей и полёт к выбранной точке. Наследник добавляет только своё —
## чем враг занят между кадрами (_update_behaviour) и как именно он движется (_move).
##
## Сцена наследника обязана состоять в группе enemies и содержать узлы Ship,
## Explosion и Tilt: по группе врага находят прицел ракет и соседи, а узлы нужны гибели
## и наклону корпуса. Форм корпуса может быть сколько угодно и называться они могут как
## угодно — гибель гасит физику целиком, а не отдельный узел. Эффекты попадания лезут
## во врага снаружи и требуют от него полей tilt и hull_radius, см. impact.gd и fire.gd.

## Сколько попаданий выдерживает враг, прежде чем взорвётся.
@export var max_health := 5
## Текстура, на которую враг подменяется в момент попадания. Обычно кадр из листа разрушения.
@export var hit_texture: Texture2D
## Сколько секунд держится текстура попадания, прежде чем вернётся обычная.
@export var hit_duration := 0.08
## Радиус корпуса для эффектов попадания, пиксели мира. На таком расстоянии от центра врага
## садится пламя от ракеты: точку касания движок не сообщает, поэтому от попадания берётся
## только сторона, с которой оно пришло, а глубина — отсюда. Больше — очаг уезжает к кромке
## обшивки и дальше в пустоту, меньше — сползает к середине. 0 — ровно центр.
## Если рисунок корпуса сдвинут относительно начала координат узла, это смещение съедает
## часть радиуса с одной стороны и добавляет с другой — у скаута корпус сидит на 9 px ниже,
## поэтому 9 ставит огонь от попадания снизу ровно в середину корабля. Число в пикселях
## мира, так что при смене масштаба узла его придётся менять вместе с ним.
@export var hull_radius := 9.0

@export_group("Movement")
## Максимальная скорость полёта, пикселей в секунду.
@export var speed := 110.0
## Насколько резко враг разгоняется и меняет направление, пикселей в секунду за секунду.
@export var acceleration := 400.0
## Верхняя граница полосы, в которой враг летает. Меньше значение — выше граница.
@export var band_top := 60.0
## Нижняя граница полосы. Чем больше, тем ближе враги подлетают к игроку.
@export var band_bottom := 240.0
## Отступ от левого и правого краёв экрана, чтобы враг не улетал под стены.
@export var side_margin := 90.0
## Доля от speed: быстрее этого враг летит вбок — и заваливается в наклон, медленнее — выпрямляется.
## 0 — наклоняется от малейшего дрейфа, ближе к 1 — только на полной скорости вбок.
## Сам угол и ступеньки настраиваются на дочернем узле Tilt.
@export_range(0.0, 1.0, 0.05) var tilt_threshold := 0.25

@export_group("Separation")
## На каком расстоянии между центрами враги начинают расталкиваться, пикселей.
## Больше — стая держится реже и расходится раньше; меньше — подпускают соседа почти вплотную.
@export var separation_radius := 70.0
## Скорость, с которой враг уходит от соседа, стоящего с ним в одной точке, пикселей в секунду.
## На границе радиуса толчок падает до нуля. Больше — расходятся резче, но сильнее сбиваются
## с курса к цели; меньше — плавнее, но могут ненадолго наехать друг на друга.
@export var separation_strength := 120.0

## По этой группе врага находят прицел ракет, соседи и сам этот класс.
const ENEMY_GROUP := &"enemies"
# Во сколько раз скорость подлёта выше оставшегося расстояния. Тормозит врага у самой
# цели, иначе он проскакивал бы точку на полной скорости и возвращался к ней рывками.
const ARRIVE_GAIN := 3.0

@onready var sprite: Sprite2D = $Ship
@onready var explosion: AnimatedSprite2D = $Explosion
@onready var tilt: Tilt = $Tilt

var health := 0

var _player: Node2D
var _target := Vector2.ZERO
var _dying := false
var _base_texture: Texture2D
var _texture_tween: Tween


func _ready() -> void:
	health = max_health
	_base_texture = sprite.texture
	# Враг летает во все стороны, а не ходит по земле: в обычном режиме move_and_slide
	# делил бы движение на «вдоль пола» и «вдоль стены» и гасил бы часть скорости.
	motion_mode = MOTION_MODE_FLOATING
	_player = _find_player()
	# Пока поведение не выбрало точку, враг тянется к месту, где стоит, то есть никуда.
	_target = global_position


func _physics_process(delta: float) -> void:
	if _dying:
		velocity = Vector2.ZERO
		return
	_update_behaviour(delta)
	_move(delta)


func take_damage(amount: int) -> void:
	if _dying:
		return
	health -= amount
	if health <= 0:
		die()
	else:
		_show_texture(hit_texture, hit_duration)


func die() -> void:
	_dying = true
	# Взрыв доигрывает на месте ещё какое-то время. Вне группы соседи его не видят:
	# не шарахаются от обломков и не учитывают его точку при выборе своих.
	remove_from_group(ENEMY_GROUP)
	# Обломки не ловят пули и не толкают живых. Гасится не одна форма, а слой и маска
	# всего тела: корпус врага собирается из нескольких CollisionShape2D, и отключать
	# их поимённо пришлось бы в каждом наследнике.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	sprite.hide()
	explosion.show()
	explosion.play("destroy")
	await explosion.animation_finished
	queue_free()


## Точка, к которой враг сейчас летит. Нужна соседям, чтобы не выбирать место рядом.
func get_target() -> Vector2:
	return _target


# Чем враг занят в этом кадре: выбирает точку, стреляет, уворачивается. Базовый враг
# не занят ничем и просто висит на месте. Вызывается до движения, поэтому цель,
# назначенная здесь, отрабатывается тем же кадром.
func _update_behaviour(_delta: float) -> void:
	pass


# Один шаг движения. По умолчанию — тяга к текущей цели на обычных скорости и ускорении;
# наследник переопределяет метод, когда умеет двигаться как-то ещё (рывок в сторону).
func _move(delta: float) -> void:
	_apply_movement(delta, _target_pull(speed), speed, acceleration)


# Скорость, с которой враг идёт к цели: на подлёте она падает вместе с расстоянием.
func _target_pull(max_speed: float) -> Vector2:
	var to_target := _target - global_position
	var distance := to_target.length()
	if distance <= 1.0:
		return Vector2.ZERO
	return to_target / distance * minf(max_speed, distance * ARRIVE_GAIN)


# Складывает желаемую скорость с толчком от соседей и двигает врага. Резких рывков
# не будет: итог всё равно проходит через move_toward с ограниченным ускорением.
func _apply_movement(delta: float, desired: Vector2, max_speed: float,
		max_acceleration: float) -> void:
	desired = (desired + _separation()).limit_length(max_speed)
	velocity = velocity.move_toward(desired, max_acceleration * delta)
	move_and_slide()
	# У игрока направление приходит с кнопок и бывает только -1, 0 или 1, а скорость
	# врага меняется плавно. Порог отсекает медленный дрейф, иначе враг, почти висящий
	# на месте, заваливался бы от каждого сдвига на пиксель.
	tilt.direction = velocity.x if absf(velocity.x) > speed * tilt_threshold else 0.0


# Сумма толчков от всех соседей ближе separation_radius. Каждый толчок направлен
# от соседа и линейно слабеет от полной силы вплотную до нуля на границе радиуса,
# поэтому враги не отскакивают, а мягко расползаются.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var other := node as Node2D
		if other == self:
			continue
		var offset := global_position - other.global_position
		var distance := offset.length()
		if distance >= separation_radius:
			continue
		# Два врага ровно в одной точке: направления «от соседа» нет, берём случайное,
		# иначе они так и остались бы слипшимися.
		var away := offset / distance if distance > 0.001 else Vector2.RIGHT.rotated(randf() * TAU)
		push += away * (1.0 - distance / separation_radius)
	return push * separation_strength


func _find_player() -> Node2D:
	return get_tree().get_first_node_in_group("player") as Node2D


# Подменяет текстуру корпуса на время и возвращает обратно. Твин хранится в поле,
# чтобы попадание во время ещё не погасшей вспышки перебивало её, а не наслаивалось.
func _show_texture(texture: Texture2D, duration: float) -> void:
	if _texture_tween != null and _texture_tween.is_running():
		_texture_tween.kill()
	sprite.texture = texture
	_texture_tween = create_tween()
	_texture_tween.tween_callback(_restore_texture).set_delay(duration)


func _restore_texture() -> void:
	sprite.texture = _base_texture
