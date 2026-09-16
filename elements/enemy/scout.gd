extends Enemy
class_name Scout

## Лёгкий вражеский истребитель: блуждает по своей полосе, иногда выходит на линию огня
## и стреляет по игроку, уворачивается от пуль и ракет. Здоровье, гибель, расталкивание
## соседей и сам полёт к выбранной точке живут в базовом классе, см. enemy.gd.

@export_group("Wander")
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
## Шанс, что враг заметит идущую в него ракету и увернётся. Бросается один раз на каждую
## ракету. Даже удачный рывок спасает не всегда: ракета наводится и доворачивает следом.
@export_range(0.0, 1.0, 0.05) var rocket_dodge_chance := 0.5
## За сколько секунд до попадания враг дёргается от ракеты. Слишком поздний рывок не
## успевает ничего изменить: на 0.35 с враг сдвигается на десяток пикселей и получает
## попадание при любой поворотливости ракеты. Слишком раннее окно ракета отрабатывает
## доворотом и всё равно догоняет. Уворот спасает только от ракеты с невысоким turn_rate,
## и настраивать баланс лучше им, а не этим окном.
@export var rocket_dodge_lookahead := 0.6

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

@onready var muzzle: Marker2D = $Muzzle
@onready var weapons: AnimatedSprite2D = $Weapons

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
	super()
	_pick_wander()
	# Первая пауза случайная, иначе вся стая делает первый залп одним кадром.
	_fire_cooldown = _next_cooldown() * randf()
	weapons.animation_finished.connect(weapons.hide)


func die() -> void:
	_set_aiming(false)
	weapons.hide()
	super()


func _update_behaviour(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_choose_state()

	_fire_cooldown -= delta
	if _can_fire():
		_fire()

	_update_dodge(delta)

	if _aiming and is_instance_valid(_player):
		_target.x = _player.global_position.x


# Во время рывка цель забыта, враг просто уходит вбок на повышенных скорости и ускорении.
# Состояния блуждания и прицеливания при этом не сбиваются: рывок кончится, и тяга
# к той же цели вернёт его обратно.
func _move(delta: float) -> void:
	if _dodge_left <= 0.0:
		super(delta)
		return
	_apply_movement(delta, _dodge_direction * dodge_speed, dodge_speed, dodge_acceleration)


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
	for node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var other := node as Enemy
		if other == self:
			continue
		nearest = minf(nearest, point.distance_to(other.get_target()))
	return nearest


# Перебирает пули и ракеты игрока, решает, от чего уворачиваться, и запускает рывок.
# Перезарядка начинает тикать только после окончания рывка.
func _update_dodge(delta: float) -> void:
	if _dodge_left > 0.0:
		_dodge_left -= delta
	elif _dodge_cooldown_left > 0.0:
		_dodge_cooldown_left -= delta
	var ready_to_dodge := _dodge_left <= 0.0 and _dodge_cooldown_left <= 0.0

	# Словарь пересобирается каждый кадр из живых снарядов, так что решения по улетевшим
	# и удалённым выбрасываются сами.
	var decisions: Dictionary[int, bool] = {}
	var escape := _consider_threats(
		&"player_bullets", dodge_lookahead, dodge_chance, decisions, ready_to_dodge)
	# Ракеты перебираются, даже когда уход от пули уже выбран: их решения тоже должны
	# попасть в словарь, иначе кубик по той же ракете бросался бы заново каждый кадр.
	var from_rocket := _consider_threats(
		&"player_rockets", rocket_dodge_lookahead, rocket_dodge_chance, decisions, ready_to_dodge)
	if escape == Vector2.ZERO:
		escape = from_rocket
	_dodge_decisions = decisions

	if escape != Vector2.ZERO:
		_start_dodge(escape)


# Перебор угроз одной группы: переносит решения по уже замеченным снарядам, бросает кубик
# по новым и возвращает сторону ухода от первого, от которого враг решил уворачиваться.
# Ракета наводится, а не летит по прямой, но у самого попадания её курс уже почти прямой,
# и на коротком окне прогноз сходится.
func _consider_threats(group: StringName, lookahead: float, chance: float,
		decisions: Dictionary[int, bool], ready_to_dodge: bool) -> Vector2:
	var escape := Vector2.ZERO
	for node in get_tree().get_nodes_in_group(group):
		var bullet := node as Bullet
		var id := bullet.get_instance_id()
		if _dodge_decisions.has(id):
			decisions[id] = _dodge_decisions[id]
		var side := _escape_direction(bullet, lookahead)
		if side == Vector2.ZERO:
			continue
		# Во время рывка и перезарядки угрозы не замечаются, и кубик не бросается:
		# шанс сыграет, когда враг снова будет готов, если снаряд ещё летит в него.
		if not ready_to_dodge:
			continue
		if not decisions.has(id):
			decisions[id] = randf() < chance
		if decisions[id] and escape == Vector2.ZERO:
			escape = side
	return escape


# Снаряд считается летящим по прямой, поэтому ближайшее сближение находится проекцией.
# Счёт идёт по относительной скорости: враг сам движется, и пуля, пущенная туда, где он
# был, может пройти мимо — на такую тратить уворот незачем.
# Возвращает направление, куда уходить, или ZERO, если снаряд не угрожает: уже пролетел,
# долетит нескоро или пройдёт дальше dodge_margin от центра.
func _escape_direction(bullet: Bullet, lookahead: float) -> Vector2:
	var bullet_velocity := bullet.get_velocity()
	var relative := bullet_velocity - velocity
	# Ракета на разгоне ползёт медленно и какое-то время идёт с врагом почти вровень.
	# Без этой отсечки деление на нулевую относительную скорость дало бы nan: сравнения
	# с ним всегда ложны, проверки ниже пропустили бы его дальше, и врага унесло бы
	# в никуда с нечисловой скоростью.
	if relative.length_squared() < 1.0:
		return Vector2.ZERO
	var to_self := global_position - bullet.global_position
	var time := to_self.dot(relative) / relative.length_squared()
	if time < 0.0 or time > lookahead:
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
