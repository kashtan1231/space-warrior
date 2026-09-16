extends Bullet
class_name Rocket

@export_group("Launch")
## Сколько секунд ракета «падает» с крыла: уменьшается и темнеет, медленно двигаясь вперёд.
@export var drop_time := 0.15
## Сколько секунд ракета возвращается к полному размеру. За это же время скорость растёт
## от drop_speed до speed, так что ракета набирает ход по мере того, как «всплывает».
@export var ignite_time := 0.3
## Скорость во время падения, пикселей в секунду. 0 — ракета зависает на месте,
## пока падает; ближе к speed — разгона почти не видно.
@export var drop_speed := 60.0
## До какой доли размера ракета сжимается в нижней точке. 1 — не сжимается совсем.
@export_range(0.1, 1.0) var drop_scale := 0.6
## Насколько ракета темнеет в нижней точке. 1 — не темнеет, 0 — чёрный силуэт.
@export_range(0.0, 1.0) var drop_darkness := 0.5
## На сколько ступенек разбито падение и столько же — возврат. 1 — ракета проваливается
## и возвращается одним рывком; чем больше, тем ближе к плавному переходу.
@export_range(1, 6, 1) var drop_steps := 2

@export_group("Homing")
## Предельная скорость поворота ракеты, градусов в секунду. Больше — крутые виражи и почти
## без промахов; меньше — широкие дуги, и цель, резко ушедшая вбок вблизи, успевает уйти.
@export var turn_rate := 180.0
## Насколько ракета учитывает движение цели. 0 — летит туда, где цель сейчас, и отстаёт
## от движущейся; 1 — в расчётную точку встречи.
@export_range(0.0, 1.0, 0.05) var lead := 0.8
## Радиус случайной ошибки прицела, пикселей. Каждая ракета при пуске выбирает свою точку
## в этом круге вокруг цели. Меньше радиуса корпуса врага — промахи только на виражах;
## больше — часть ракет проходит мимо даже по неподвижной цели.
@export var aim_error := 12.0
## Через сколько секунд после вылета ракета начинает наводиться. Отсчёт идёт от появления
## ракеты, а не от конца разгона: меньше — ракета цепляет цель ещё у крыла и заворачивает
## круто, больше — сначала уходит вверх по прямой и доворачивает уже вдали от корабля.
@export var homing_delay := 0.15
## За сколько секунд поворотливость нарастает от нуля до turn_rate. Нужно, чтобы наведение
## включалось не рывком: 0 — ракета получает полный поворот сразу и заметно дёргается
## в сторону цели, больше — вписывается в курс плавной дугой.
@export var homing_ramp := 0.25
## На сколько градусов цель должна уйти в сторону от курса ракеты, чтобы считаться
## упущенной. 90 — ракета бросает цель, едва та оказалась позади её носа; меньше —
## сдаётся раньше, ещё на подлёте сбоку; 180 — не бросает никогда и разворачивается
## на второй заход.
@export_range(30.0, 180.0, 5.0) var lose_angle := 90.0

@export_group("Fire")
## Сцена пламени, которое остаётся гореть на обшивке в точке попадания. Сколько оно горит
## и как гаснет, настраивается в самой сцене огня, см. fire.gd.
@export var fire_scene: PackedScene

const ENEMY_GROUP := &"enemies"
# По этой группе враги находят летящие ракеты, чтобы уворачиваться от них.
const ROCKET_GROUP := &"player_rockets"

@onready var sprite: AnimatedSprite2D = $Body

## Враг, на которого наводится ракета. Выставляется до добавления в дерево;
## null — ракета летит прямо.
var target: Node2D

var _base_sprite_scale := Vector2.ONE
var _base_sprite_modulate := Color.WHITE
var _cruise_speed := 0.0
# Доля от turn_rate, доступная ракете прямо сейчас: 0 — наведение ещё не включилось.
var _turn_scale := 0.0
var _aim_offset := Vector2.ZERO


func _ready() -> void:
	# У унаследованного _ready нет автоматического вызова родительского, как у конструктора:
	# без super() ракета останется без обеих подписок Bullet — пролетит врагов насквозь
	# и не удалится, уйдя за край экрана.
	super()
	# Группа выдаётся здесь, а не в сцене: сцена ракеты одна на всех, отдельной вражеской
	# версии у неё нет, и так в группу попадает ракета, выпущенная любым способом.
	add_to_group(ROCKET_GROUP)
	_base_sprite_scale = sprite.scale
	_base_sprite_modulate = sprite.modulate
	# sqrt растягивает распределение к краю круга: без него точки кучковались бы
	# в центре, и ошибка на деле была бы меньше заявленной.
	_aim_offset = Vector2.from_angle(randf() * TAU) * aim_error * sqrt(randf())
	_start_drop()


func _physics_process(delta: float) -> void:
	if _turn_scale > 0.0 and target != null:
		if _is_target_alive() and not _is_target_behind():
			_steer(delta)
		else:
			# Цель потеряна насовсем: ракета держит текущий курс и не ищет новую.
			target = null
	super(delta)


# Пламя ставит только ракета, поэтому пуск огня живёт здесь, а не в bullet.gd: пуль в бою
# на порядок больше, и огонь от каждой превратил бы попадания в сплошной костёр.
# Родительский _on_body_entered в конце вызывает queue_free, так что поджигать нужно до него.
func _on_body_entered(body: Node2D) -> void:
	_spawn_fire(body)
	super(body)


# Огонь цепляется к обшивке так же, как брызги попадания, см. impact.gd: у каждого корабля
# есть компонент Tilt, по которому точка горения доворачивается вместе с корпусом.
func _spawn_fire(body: Node2D) -> void:
	var fire: Fire = fire_scene.instantiate()
	fire.attach(body, body.tilt, global_position)
	get_tree().current_scene.add_child(fire)


func _start_drop() -> void:
	# Масштабируется только спрайт, а не весь узел: хитбокс остаётся прежним, а корень
	# сохраняет масштаб из сцены, под который подогнан размер ракеты в шахте.
	var look := create_tween()
	for step in range(1, drop_steps + 1):
		look.tween_callback(_set_drop_phase.bind(float(step) / drop_steps))
		look.tween_interval(drop_time / drop_steps)
	# На возврате пауза идёт перед шагом, а не после: так последний шаг к полному размеру
	# приходится ровно на конец ignite_time — тот же кадр, где скорость становится полной.
	for step in range(drop_steps - 1, -1, -1):
		look.tween_interval(ignite_time / drop_steps)
		look.tween_callback(_set_drop_phase.bind(float(step) / drop_steps))

	# Скорость меняется плавно, в отличие от картинки: движение не размывает пиксели,
	# а рывки скорости выглядели бы как подёргивание. EASE_IN — медленный старт
	# с нарастающим ускорением, как у разгорающегося двигателя.
	_cruise_speed = speed
	speed = drop_speed
	var thrust := create_tween()
	thrust.tween_interval(drop_time)
	thrust.tween_property(self, "speed", _cruise_speed, ignite_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Наведение живёт своим таймингом, а не концом разгона: так момент, когда ракета
	# начинает доворачивать, правится отдельно от того, как выглядит пуск.
	var homing := create_tween()
	homing.tween_interval(homing_delay)
	homing.tween_property(self, "_turn_scale", 1.0, homing_ramp)


func _steer(delta: float) -> void:
	var target_velocity := Vector2.ZERO
	if target is CharacterBody2D:
		target_velocity = (target as CharacterBody2D).velocity
	# Время до встречи прикидывается по прямой на крейсерской скорости. Это неточно:
	# ракета летит дугой, а цель меняет курс, — но пересчёт каждый кадр сам поправляет ошибку.
	var time := global_position.distance_to(target.global_position) / _cruise_speed
	var aim_point := target.global_position + target_velocity * time * lead + _aim_offset
	# Ракета летит вдоль своего «верха» (см. bullet.gd), поэтому нужный поворот —
	# угол между UP и направлением на точку прицеливания.
	var desired := Vector2.UP.angle_to(aim_point - global_position)
	rotation = rotate_toward(rotation, desired, deg_to_rad(turn_rate * _turn_scale) * delta)


# Цель считается пройденной, когда направление на неё ушло от курса ракеты дальше
# lose_angle. Проверять расстояние здесь нельзя: у идущей навстречу цели оно растёт
# и до пролёта, а у догоняемой убывает даже когда ракета мажет.
func _is_target_behind() -> bool:
	var heading := Vector2.UP.rotated(rotation)
	var to_target := target.global_position - global_position
	return absf(heading.angle_to(to_target)) > deg_to_rad(lose_angle)


func _is_target_alive() -> bool:
	return is_instance_valid(target) and target.is_in_group(ENEMY_GROUP)


# phase: 0 — ракета в обычном виде, 1 — в нижней точке, сжатая и тёмная.
func _set_drop_phase(phase: float) -> void:
	sprite.scale = _base_sprite_scale.lerp(_base_sprite_scale * drop_scale, phase)
	var dark := Color(drop_darkness, drop_darkness, drop_darkness)
	sprite.modulate = _base_sprite_modulate.lerp(dark, phase)
