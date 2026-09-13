extends CharacterBody2D
class_name Scout

## Сколько попаданий выдерживает враг, прежде чем взорвётся.
@export var max_health := 5
## Текстура, на которую враг подменяется в момент попадания. Обычно кадр из листа разрушения.
@export var hit_texture: Texture2D
## Сколько секунд держится текстура попадания, прежде чем вернётся обычная.
@export var hit_duration := 0.08

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
## Минимальное расстояние между точками, куда летят разные враги, пикселей. Не даёт двоим
## выбрать одно место и топтаться там, отпихивая друг друга. Лучше держать не меньше
## separation_radius. Если на экране тесно и места нет, берётся самая свободная точка.
@export var target_spacing := 100.0

@export_group("Dodge")
## Шанс, что враг заметит пулю, летящую в него, и увернётся. Бросается один раз на каждую
## пулю. 0 — не уворачивается никогда, 1 — от каждой пули, если не на перезарядке.
@export_range(0.0, 1.0, 0.05) var dodge_chance := 0.5
## Пауза после уворота, секунд, в течение которой враг не замечает новых пуль.
## Меньше — очередь почти не пробивает; больше — второй выстрел следом почти всегда попадает.
@export var dodge_cooldown := 1.5
## Сколько длится рывок в сторону, секунд. Вместе с dodge_speed задаёт, насколько далеко
## враг уходит с линии огня.
@export var dodge_duration := 0.3
## Скорость рывка, пикселей в секунду. Выше обычной speed, иначе враг не успевает уйти.
@export var dodge_speed := 260.0
## Ускорение во время рывка, пикселей в секунду за секунду. Больше — рывок резче и
## срабатывает даже против пули, выпущенной почти в упор.
@export var dodge_acceleration := 1800.0
## На сколько секунд вперёд враг просчитывает полёт пуль. Больше — замечает пули раньше,
## ещё у самого корабля игрока; меньше — реагирует только на подлетевшие вплотную.
@export var dodge_lookahead := 0.5
## Насколько близко к центру врага должна пройти траектория пули, чтобы он счёл её
## угрозой, пикселей. Примерно радиус корпуса с запасом: меньше — будет уворачиваться
## только от выстрелов точно в центр, больше — шарахаться и от пуль, летящих мимо.
@export var dodge_margin := 36.0

@export_group("Weapon")
## Сцена снаряда врага. Назначается в инспекторе.
@export var bullet_scene: PackedScene
## Сколько выстрелов в секунду делает враг, пока игрок на линии огня. 0 — враг не стреляет совсем.
@export var fire_rate := 0.6
## Разброс паузы между выстрелами, доля от базовой паузы. 0 — стрельба строго по таймеру,
## 0.5 — пауза гуляет в полтора раза в обе стороны, и залпы соседних врагов не сливаются.
@export_range(0.0, 1.0) var fire_jitter := 0.4
## Насколько близко игрок должен оказаться под врагом по горизонтали, пикселей.
## Больше — враг стреляет чаще, но чаще мажет; меньше — стреляет реже и точнее.
@export var aim_tolerance := 28.0

const MAX_AIMERS := 2
const AIM_CHANCE := 0.5
const WANDER_ATTEMPTS := 8

static var _aimers := 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var explosion: AnimatedSprite2D = $Explosion
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var muzzle: Marker2D = $Muzzle
@onready var weapons: AnimatedSprite2D = $Weapons
@onready var tilt: Tilt = $Tilt

var health := 0
var _base_texture: Texture2D
var _texture_tween: Tween
var _dying := false

var _player: Node2D
var _target := Vector2.ZERO
var _state_timer := 0.0
var _aiming := false
var _fire_cooldown := 0.0

var _dodge_left := 0.0
var _dodge_cooldown_left := 0.0
var _dodge_direction := Vector2.ZERO
# Решения «заметил / не заметил» по каждой пуле, ключ — instance id пули. Без памяти
# шанс перебрасывался бы каждый кадр подлёта, и уворот стал бы почти гарантированным.
var _dodge_decisions: Dictionary[int, bool] = {}


func _ready() -> void:
	health = max_health
	_base_texture = sprite.texture
	motion_mode = MOTION_MODE_FLOATING
	_player = _find_player()
	_pick_wander()
	# Первая пауза случайная, иначе вся стая делает первый залп одним кадром.
	_fire_cooldown = _next_cooldown() * randf()
	weapons.animation_finished.connect(weapons.hide)


func _physics_process(delta: float) -> void:
	if _dying:
		velocity = Vector2.ZERO
		return

	_state_timer -= delta
	if _state_timer <= 0.0:
		_choose_state()

	_fire_cooldown -= delta
	if _can_fire():
		_fire()

	_update_dodge(delta)

	if _aiming and is_instance_valid(_player):
		_target.x = _player.global_position.x

	var to_target := _target - global_position
	var distance := to_target.length()
	var desired := Vector2.ZERO
	if distance > 1.0:
		desired = to_target / distance * minf(speed, distance * 3.0)
	var max_speed := speed
	var max_acceleration := acceleration
	# Во время рывка цель забыта, враг просто уходит вбок на повышенных скорости и
	# ускорении. Состояния блуждания и прицеливания при этом не сбиваются: рывок кончится,
	# и тяга к той же цели вернёт его обратно.
	if _dodge_left > 0.0:
		desired = _dodge_direction * dodge_speed
		max_speed = dodge_speed
		max_acceleration = dodge_acceleration
	# Толчок от соседей просто складывается с тягой к цели. Резких рывков не будет:
	# итог всё равно проходит через move_toward с ограниченным ускорением.
	desired = (desired + _separation()).limit_length(max_speed)
	velocity = velocity.move_toward(desired, max_acceleration * delta)
	move_and_slide()
	# У игрока направление приходит с кнопок и бывает только -1, 0 или 1, а скорость
	# врага меняется плавно. Порог отсекает медленный дрейф, иначе враг, почти висящий
	# на месте, заваливался бы от каждого сдвига на пиксель.
	tilt.direction = velocity.x if absf(velocity.x) > speed * tilt_threshold else 0.0


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
	remove_from_group("enemies")
	_set_aiming(false)
	collision_shape.set_deferred("disabled", true)
	sprite.hide()
	weapons.hide()
	explosion.show()
	explosion.play("destroy")
	await explosion.animation_finished
	queue_free()


## Точка, к которой враг сейчас летит. Нужна соседям, чтобы не выбирать место рядом.
func get_target() -> Vector2:
	return _target


func _can_fire() -> bool:
	if fire_rate <= 0.0 or _fire_cooldown > 0.0:
		return false
	if not is_instance_valid(_player):
		return false
	return absf(_player.global_position.x - global_position.x) <= aim_tolerance


func _fire() -> void:
	_fire_cooldown = _next_cooldown()
	var bullet := bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	# stop() перед play() перематывает на первый кадр: без него повторный выстрел
	# во время ещё играющей анимации не перезапустил бы её.
	weapons.stop()
	weapons.show()
	weapons.play("fire")


func _next_cooldown() -> float:
	var base := 1.0 / fire_rate
	return base * randf_range(1.0 - fire_jitter, 1.0 + fire_jitter)


func _choose_state() -> void:
	if _aiming:
		_set_aiming(false)
		_pick_wander()
	elif _player != null and _aimers < MAX_AIMERS and randf() < AIM_CHANCE:
		_set_aiming(true)
		_target = Vector2(global_position.x, randf_range(band_top, band_bottom))
		_state_timer = randf_range(1.0, 2.0)
	else:
		_pick_wander()


# Несколько случайных попыток найти точку, далёкую от целей соседей. Первая подходящая
# берётся сразу; если все попытки легли в тесноту, остаётся самая свободная из них —
# враг не должен зависать без цели только потому, что на экране людно.
func _pick_wander() -> void:
	var width := get_viewport_rect().size.x
	var best := Vector2.ZERO
	var best_clearance := -1.0
	for attempt in WANDER_ATTEMPTS:
		var candidate := Vector2(
			randf_range(side_margin, width - side_margin),
			randf_range(band_top, band_bottom)
		)
		var clearance := _clearance_from_other_targets(candidate)
		if clearance > best_clearance:
			best = candidate
			best_clearance = clearance
		if clearance >= target_spacing:
			break
	_target = best
	_state_timer = randf_range(0.8, 2.0)


# Расстояние от точки до ближайшей цели другого врага. INF, если соседей нет.
func _clearance_from_other_targets(point: Vector2) -> float:
	var nearest := INF
	for node in get_tree().get_nodes_in_group("enemies"):
		# В группе могут оказаться враги других типов, у которых нет get_target().
		var other := node as Scout
		if other == null or other == self:
			continue
		nearest = minf(nearest, point.distance_to(other.get_target()))
	return nearest


# Сумма толчков от всех соседей ближе separation_radius. Каждый толчок направлен
# от соседа и линейно слабеет от полной силы вплотную до нуля на границе радиуса,
# поэтому враги не отскакивают, а мягко расползаются.
func _separation() -> Vector2:
	var push := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("enemies"):
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


# Перебирает пули игрока, решает, от какой уворачиваться, и запускает рывок.
# Перезарядка начинает тикать только после окончания рывка.
func _update_dodge(delta: float) -> void:
	if _dodge_left > 0.0:
		_dodge_left -= delta
	elif _dodge_cooldown_left > 0.0:
		_dodge_cooldown_left -= delta
	var ready_to_dodge := _dodge_left <= 0.0 and _dodge_cooldown_left <= 0.0

	# Словарь пересобирается каждый кадр из живых пуль, так что решения по улетевшим
	# и удалённым пулям выбрасываются сами.
	var decisions: Dictionary[int, bool] = {}
	var escape := Vector2.ZERO
	for node in get_tree().get_nodes_in_group("player_bullets"):
		var bullet := node as Bullet
		var id := bullet.get_instance_id()
		if _dodge_decisions.has(id):
			decisions[id] = _dodge_decisions[id]
		var side := _escape_direction(bullet)
		if side == Vector2.ZERO:
			continue
		# Во время рывка и перезарядки угрозы не замечаются, и кубик не бросается:
		# шанс сыграет, когда враг снова будет готов, если пуля ещё летит в него.
		if not ready_to_dodge:
			continue
		if not decisions.has(id):
			decisions[id] = randf() < dodge_chance
		if decisions[id] and escape == Vector2.ZERO:
			escape = side
	_dodge_decisions = decisions

	if escape != Vector2.ZERO:
		_start_dodge(escape)


# Пуля летит по прямой, поэтому ближайшее сближение считается проекцией. Считается
# по относительной скорости: враг сам движется, и пуля, пущенная туда, где он был,
# может пройти мимо — на такую тратить уворот незачем.
# Возвращает направление, куда уходить, или ZERO, если пуля не угрожает: уже пролетела,
# долетит нескоро или пройдёт дальше dodge_margin от центра.
func _escape_direction(bullet: Bullet) -> Vector2:
	var bullet_velocity := bullet.get_velocity()
	var relative := bullet_velocity - velocity
	var to_self := global_position - bullet.global_position
	var time := to_self.dot(relative) / relative.length_squared()
	if time < 0.0 or time > dodge_lookahead:
		return Vector2.ZERO
	var miss := to_self - relative * time
	if miss.length() > dodge_margin:
		return Vector2.ZERO
	# Уходим поперёк полёта пули, в ту сторону, где враг уже и так смещён от её линии:
	# до безопасного края там ближе. Пуля точно в центр — сторона случайная.
	var across := bullet_velocity.orthogonal().normalized()
	var side := signf(miss.dot(across))
	if side == 0.0:
		side = 1.0 if randf() < 0.5 else -1.0
	return across * side


func _start_dodge(direction: Vector2) -> void:
	# Если рывок вынес бы врага за боковой отступ, уходим в другую сторону. Это значит
	# пересечь линию огня, зато враг не прилипнет к стене, куда его легко добить.
	var width := get_viewport_rect().size.x
	var landing_x := global_position.x + direction.x * dodge_speed * dodge_duration
	if landing_x < side_margin or landing_x > width - side_margin:
		direction = -direction
	_dodge_direction = direction
	_dodge_left = dodge_duration
	_dodge_cooldown_left = dodge_cooldown


func _set_aiming(value: bool) -> void:
	if _aiming == value:
		return
	_aiming = value
	_aimers += 1 if value else -1


func _exit_tree() -> void:
	_set_aiming(false)


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
