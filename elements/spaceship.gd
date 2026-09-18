extends CharacterBody2D
class_name Spaceship

## Летит при каждом изменении здоровья. На него подписан индикатор хп, чтобы корабль
## ничего не знал про интерфейс и не лез в его узлы.
signal health_changed(health: int, max_health: int)

## Летит один раз, в момент гибели корабля, до проигрывания взрыва. Сюда подключатся
## экран поражения и счётчик жизней, когда появятся.
signal died

## Летит при каждом изменении заряда нырка: 0 — нырок идёт или перезарядка только
## началась, 1 — нырок снова доступен. Во время перезарядки — каждый физический кадр.
## На него подписана шкала перезарядки нырка.
signal dodge_charge_changed(charge: float)

## Летит при входе в режим прицеливания и при выходе из него. На него подписана ракетная
## панель: по нему она взводит рычаг следующей ракеты и опускает его обратно.
signal aiming_changed(active: bool)

## Летит на каждое нажатие «следующая/предыдущая цель»: 1 — вперёд, -1 — назад.
signal target_cycled(step: int)

## Летит в кадр пуска ракеты. index — номер шахты в rocket_launchers.
signal rocket_launched(index: int)

## Летит при любом изменении боезапаса: пуск ракеты, прокачка вместимости. Массив идёт
## по заряженным шахтам в порядке rocket_launchers: true — ракета на месте.
signal rockets_changed(loaded: Array[bool])

## Летит при каждом изменении готовности ракетной системы: 0 — ракета только что ушла,
## 1 — можно пускать снова. Во время задержки — каждый физический кадр. На него подписана
## шкала кулдауна на ракетной панели.
signal rocket_charge_changed(charge: float)

## Сколько попаданий вражеских пуль выдерживает корабль.
@export var max_health := 5
## Предельная скорость корабля, пикселей в секунду.
@export var max_speed := 400.0
## Насколько быстро корабль набирает скорость, пикселей в секунду за секунду.
@export var acceleration := 1200.0
## Насколько быстро гаснет скорость после отпускания кнопки. Меньше значение — длиннее занос.
@export var friction := 3000.0
## Сколько выстрелов в секунду при зажатой кнопке огня.
@export var fire_rate := 2.0
## Текстуры корпуса от целой к разбитой. Шкала здоровья делится поровну между картинками:
## при четырёх текстурах каждая держится свои 25 % здоровья.
@export var damage_textures: Array[Texture2D]

@export_group("Invulnerability")
## Режим бога для тестов: пули по-прежнему попадают и взрываются на корпусе, но здоровье
## не отнимается и корабль не мигает. Перед сборкой игры выключить.
@export var god_mode := false
## Сколько секунд после попадания корабль не получает урон. Без этой паузы очередь в упор
## снимает всё здоровье за доли секунды, и игрок не успевает понять, что произошло.
@export var invulnerability_duration := 1.2
## Период мигания, секунд: первую половину корабль тусклый, вторую — обычный.
@export var invulnerability_blink_period := 0.16
## Прозрачность в тусклой фазе. 0 — корабль пропадает совсем, 1 — мигания не видно.
@export_range(0.0, 1.0) var invulnerability_blink_alpha := 0.25

@export_group("Dodge")
## Сколько секунд длится нырок. В это время урон не проходит, но и стрелять нельзя.
## Погружение и всплытие укладываются внутрь этого времени, а не добавляются к нему.
@export var dodge_duration := 1.0
## Пауза до следующего нырка, секунд. Отсчитывается с момента всплытия.
@export var dodge_cooldown := 2.0
## Сколько секунд корабль горит белым, когда перезарядка нырка закончилась.
## Больше — сигнал заметнее, но дольше закрывает сам корабль.
@export var dodge_ready_flash_duration := 0.1
## До какой доли размера сжимается корабль на дне нырка. 1 — не сжимается совсем.
@export_range(0.1, 1.0) var dodge_scale := 0.6
## Насколько корабль темнеет на дне нырка. 1 — не темнеет, 0 — чёрный силуэт.
@export_range(0.0, 1.0) var dodge_darkness := 0.45
## Сколько секунд занимает само погружение и столько же — всплытие.
@export var dodge_transition := 0.18
## На сколько ступенек разбито погружение. 2 — корабль проваливается в два рывка,
## как в пиксельной анимации; чем больше, тем ближе к плавному съезду.
@export_range(1, 6, 1) var dodge_steps := 2
## Во сколько раз каждый следующий шаг длиннее предыдущего. 1 — шаги равные,
## 0.5 — каждый вдвое короче, корабль проваливается с ускорением, 2 — с замедлением.
## Общая длительность перехода не меняется, меняется только её раскладка по шагам.
@export_range(0.25, 4.0, 0.05) var dodge_step_falloff := 1.0
## Радиус, в котором уход в нырок расталкивает уже висящий дым, пикселей. Само облако
## нырка настраивается на узле DodgeSmoke, здесь — только то, как корабль раздвигает
## дым, который был на этом месте до него.
@export var dodge_blast_radius := 70.0
## Скорость, с которой дым разлетается от нырнувшего корабля, пикселей в секунду. Это
## скорость в самом центре: к краю радиуса толчок слабеет до нуля. Заметно меньше, чем
## у гибели, — корабль проваливается, а не взрывается.
@export var dodge_blast_strength := 120.0

@export_group("Tilt")
## Сам наклон настраивается на дочернем узле Tilt, здесь — только его влияние на стрельбу.
## Насколько наклон корпуса уводит пулю в сторону. 0 — пули всегда летят строго вверх,
## 1 — точно вдоль носа, 0.5 — вполовину отложе наклона. Нужен потому, что угол, который
## хорошо смотрится на корпусе, для пули обычно уже слишком косой.
@export_range(0.0, 1.0, 0.05) var bullet_tilt_influence := 0.5

@export_group("Recoil")
## На сколько пикселей спрайта проседает корпус при выстреле. Только целые: дробное
## смещение поставило бы спрайт между пикселями и размыло бы его.
@export_range(1, 16, 1) var recoil_distance := 4
## Сколько секунд корпус стоит на нижней точке, прежде чем начать возвращаться.
@export var recoil_hold_time := 0.05
## За сколько секунд корпус возвращается на место. Время делится поровну между пикселями,
## так что при большем recoil_distance ступеньки становятся чаще, а не длиннее.
@export var recoil_return_time := 0.12

@export_group("Rockets")
## Ракетные шахты корабля — все, что есть на крыльях, независимо от прокачки. Порядок
## списка задаёт и очерёдность пуска, и порядок открытия: сначала внутренняя пара
## у корпуса, дальше по крылу наружу, внутри пары — левая, потом правая. Тогда одно
## нажатие пускает одну ракету, а крылья разряжаются поочерёдно и корабль не перекашивает.
@export var rocket_launchers: Array[RocketLauncher]
## Сколько шахт заряжено. Шаг в две ракеты — по одной на каждое крыло, чтобы ёлочка
## оставалась симметричной; лишние шахты спрятаны и не стреляют. Это же поле двигает
## прокачка в рантайме: присвоение открывает новые шахты сразу с ракетами в них.
@export_range(0, 6, 2) var rocket_capacity := 2: set = set_rocket_capacity
## Сколько секунд после пуска ракетная система не принимает следующий пуск. Нажатия
## в это время пропадают: очередь ракет задаёт корабль, а не то, как быстро игрок долбит
## кнопку. 0 — весь боезапас уходит залпом за столько нажатий, сколько успеет игрок.
@export var rocket_cooldown := 0.5

@export_group("Death")
## Через сколько секунд после начала основного взрыва стартует второй (узел Blast).
## 0 — оба одновременно. Корабль удаляется, только когда доиграют оба, поэтому
## большая задержка удлиняет гибель на столько же.
@export var blast_delay := 0.3

@export_group("Smoke")
## Радиус, в котором гибель корабля расталкивает дым, пикселей.
@export var smoke_blast_radius := 100.0
## Скорость, с которой дым разлетается от взорвавшегося корабля, пикселей в секунду. Это
## скорость в самом центре: к краю радиуса толчок слабеет до нуля.
@export var smoke_blast_strength := 400.0

@onready var muzzle: Marker2D = $Muzzle
@onready var ship: Sprite2D = $Ship
@onready var engine_left: ShipEngine = $Ship/Engine/EngineLeft
@onready var engine_right: ShipEngine = $Ship/Engine/EngineRight
@onready var explosion: AnimatedSprite2D = $Explosion
@onready var blast: AnimatedSprite2D = $Explosion/Blast
@onready var hitbox: CollisionPolygon2D = $Hitbox
@onready var tilt: Tilt = $Tilt
@onready var flammable: Flammable = $Flammable
@onready var ship_material: ShaderMaterial = ship.material
@onready var targeting: Targeting = $Targeting
@onready var wake: Wake = $Wake
@onready var dodge_smoke: SmokeTrail = $DodgeSmoke

const BULLET_SCENE = preload("res://elements/weapons/bullet_gun/bullet.tscn")
const DODGE_EFFECT_SCENE = preload("res://elements/dodge_effect.tscn")
## Имя uniform-параметра в white_flash.gdshader.
const FLASH_PARAM := &"flash"

var health := 0
var _fire_cooldown := 0.0
var _rocket_cooldown := 0.0
var _invulnerability_left := 0.0
var _dodge_left := 0.0
var _dodge_cooldown_left := 0.0
# Последний отправленный заряд нырка: по переходу через 1 ловится момент готовности.
var _dodge_charge_sent := 1.0
var _flash_tween: Tween
var _base_collision_layer := 0
var _base_ship_scale := Vector2.ONE
var _base_ship_position := Vector2.ZERO
var _recoil_tween: Tween
var _dying := false
var _base_ship_modulate := Color.WHITE
var _smoke: Smoke


func _ready() -> void:
	_base_collision_layer = collision_layer
	_base_ship_scale = ship.scale
	_base_ship_position = ship.position
	_base_ship_modulate = ship.modulate
	_smoke = get_tree().get_first_node_in_group(Smoke.GROUP) as Smoke
	health = max_health
	health_changed.emit(health, max_health)
	_update_ship_texture()
	# Режим прицеливания выключается и сам — когда врагов не осталось или кончились
	# ракеты, — поэтому о входе и выходе рассказывает он, а не тот, кто его включил.
	targeting.activated.connect(aiming_changed.emit.bind(true))
	targeting.deactivated.connect(aiming_changed.emit.bind(false))
	targeting.target_cycled.connect(target_cycled.emit)
	# Вместимость пришла из инспектора ещё до появления дочерних узлов, поэтому шахты
	# разбираются только здесь, когда до них уже можно дотянуться.
	_refresh_launchers()


func _physics_process(delta: float):
	if _dying:
		return

	if _invulnerability_left > 0.0:
		_update_invulnerability(delta)

	_update_dodge(delta)

	_fire_cooldown -= delta
	
	if Input.is_action_pressed("fire") and _fire_cooldown <= 0.0 and _dodge_left <= 0.0: 
		fire()
		_fire_cooldown = 1.0 / fire_rate

	if Input.is_action_just_pressed("enable_aiming"):
		_toggle_targeting()

	if _rocket_cooldown > 0.0:
		# Остаток не уходит в минус, чтобы последний сигнал принёс ровно 1, а не 1.02.
		_rocket_cooldown = maxf(_rocket_cooldown - delta, 0.0)
		_send_rocket_charge()

	# just_pressed, а не pressed: одно нажатие — одна ракета, зажатая кнопка не
	# высыпает весь запас подряд. Ракеты пускаются только по выбранной цели.
	if Input.is_action_just_pressed("fire_rocket") and targeting.is_active() \
			and _rocket_cooldown <= 0.0 and _dodge_left <= 0.0:
		_launch_rocket()

	var direction := Input.get_axis("move_left", "move_right")
	tilt.direction = direction
	_update_engines(direction)
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * max_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	move_and_slide()


func take_damage(amount: int) -> void:
	if _dying or _is_invulnerable() or god_mode:
		return
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0:
		die()
		return
	_update_ship_texture()
	_invulnerability_left = invulnerability_duration
	_refresh_collision_layer()


func die() -> void:
	_dying = true
	died.emit()
	targeting.deactivate()
	hitbox.set_deferred("disabled", true)
	# Взрыв один раз расталкивает дым, а обломки, висящие на месте, больше его не трогают.
	_smoke.blast(global_position, smoke_blast_radius, smoke_blast_strength)
	wake.disable()
	# Двигатели глохнут насмерть: тянуть шлейф за обломками, висящими на месте, некому.
	# Выключить их нужно здесь, а не в _physics_process: тот при _dying сразу выходит,
	# а тайминги нырка доигрывают на твинах и могли бы запустить сопла обратно.
	engine_left.disable()
	engine_right.disable()
	# Взрыв не состоит в targets у Tilt и потому висит прямо, пока корпус накренён.
	# Доворачивается он один раз, в момент гибели: управление кораблём уже отобрано,
	# и обломки замирают под тем углом, на котором их застали.
	explosion.rotation += tilt.current_angle
	# stop() перематывает на первый кадр: в сцене взрыв сохранён на последнем, и без
	# перемотки play() показал бы только его — та же причина, что у Blast ниже.
	explosion.stop()
	# Корпус пока остаётся: основной взрыв стоит в дереве после Ship и рисуется поверх
	# него, а сам корабль пропадает только вместе со стартом Blast, ниже.
	explosion.show()
	explosion.play("destroy")
	# Blast лежит внутри Explosion и становится видимым вместе с ним. stop() перематывает
	# на первый кадр: без него анимация, уже доигранная раньше, не началась бы заново.
	blast.stop()
	# Пока идёт задержка, Blast спрятан: перемотанный на первый кадр, он висел бы
	# на экране неподвижной картинкой.
	blast.hide()
	if blast_delay > 0.0:
		# Одноразовый таймер дерева сцены: await на его сигнале timeout приостанавливает
		# die(), а destroy тем временем продолжает играть сам по себе.
		await get_tree().create_timer(blast_delay).timeout
	ship.hide()
	blast.show()
	blast.play("default")
	# Взрывы разной длины, а удалять корабль можно только после обоих: queue_free
	# снёс бы и дочерние узлы, оборвав тот, что ещё играет. Проверка is_playing() нужна,
	# потому что за время задержки destroy мог уже закончиться, и его сигнал не придёт.
	if explosion.is_playing():
		await explosion.animation_finished
	if blast.is_playing():
		await blast.animation_finished
	queue_free()


## Открывает первые count шахт, остальные закрывает. Значения больше числа шахт на крыльях
## безвредны: лишние ракеты взять неоткуда, открываются все, что есть.
func set_rocket_capacity(count: int) -> void:
	rocket_capacity = count
	# Сеттер срабатывает и при загрузке сцены, когда дочерних узлов ещё нет.
	if is_node_ready():
		_refresh_launchers()


## Боезапас по заряженным шахтам в порядке rocket_launchers: true — ракета на месте.
## Закрытые прокачкой шахты в список не попадают: на панели приборов их ещё нет.
## Нужен интерфейсу, который строится позже корабля и не застаёт стартовый сигнал.
func get_rocket_states() -> Array[bool]:
	var states: Array[bool] = []
	for index in mini(rocket_capacity, rocket_launchers.size()):
		states.append(rocket_launchers[index].is_loaded())
	return states


## Идёт ли нырок прямо сейчас. Нырнувший корабль не только не получает урон: наводящиеся
## снаряды перестают его видеть и летят мимо по прямой, см. torpedo.gd.
func is_dodging() -> bool:
	return _dodge_left > 0.0


func _refresh_launchers() -> void:
	for index in rocket_launchers.size():
		rocket_launchers[index].set_open(index < rocket_capacity)
	rockets_changed.emit(get_rocket_states())


func _update_invulnerability(delta: float) -> void:
	_invulnerability_left -= delta
	if _invulnerability_left <= 0.0:
		modulate.a = 1.0
		_refresh_collision_layer()
		return
	# Мигание отсчитывается от остатка неуязвимости, поэтому последняя вспышка всегда
	# заканчивается ровно вместе с ней, а не обрывается на тусклом кадре.
	var dark := fmod(_invulnerability_left, invulnerability_blink_period) < invulnerability_blink_period * 0.5
	modulate.a = invulnerability_blink_alpha if dark else 1.0


func _update_dodge(delta: float) -> void:
	if _dodge_cooldown_left > 0.0:
		# Остаток не уходит в минус, чтобы последний сигнал принёс ровно 1, а не 1.02.
		_dodge_cooldown_left = maxf(_dodge_cooldown_left - delta, 0.0)
		_send_dodge_charge()

	if _dodge_left > 0.0:
		_dodge_left -= delta
		if _dodge_left <= 0.0:
			_dodge_left = 0.0
			_dodge_cooldown_left = dodge_cooldown
			_refresh_collision_layer()
			# Отдельный сигнал нужен на случай нулевой перезарядки: тогда ветка
			# с отсчётом выше не сработает, и без него шкала осталась бы пустой,
			# а корабль не мигнул бы.
			_send_dodge_charge()
	elif _dodge_cooldown_left <= 0.0 and Input.is_action_just_pressed("dodge"):
		_start_dodge()


func _start_dodge() -> void:
	_dodge_left = dodge_duration
	_refresh_collision_layer()
	_spawn_dodge_effect()
	_spawn_dodge_smoke()
	_send_dodge_charge()

	# Погружение и всплытие вписываются в длительность нырка, поэтому корабль всплывает
	# ровно тем же кадром, каким кончается неуязвимость, а не через мгновение после.
	var transition := minf(dodge_transition, dodge_duration * 0.5)
	var hold := dodge_duration - transition * 2.0
	var step_times := _dodge_step_times(transition)

	# Погружение и всплытие идут мгновенными состояниями, а не плавным съездом —
	# так нырок читается как нарисованная покадровая анимация, а не как трансформация.
	var tween := create_tween()
	for step in range(1, dodge_steps + 1):
		tween.tween_callback(_set_dodge_phase.bind(float(step) / dodge_steps))
		tween.tween_interval(step_times[step - 1])
	tween.tween_interval(hold)
	# Всплытие проигрывает те же длительности задом наперёд, поэтому разгон при
	# погружении превращается в торможение при выныривании, и нырок выглядит цельным.
	for step in range(dodge_steps - 1, -1, -1):
		tween.tween_callback(_set_dodge_phase.bind(float(step) / dodge_steps))
		tween.tween_interval(step_times[step])


func _spawn_dodge_effect() -> void:
	# Вспышка кладётся в корень уровня, как пуля: будь она дочерним узлом корабля,
	# она сжималась бы вместе со спрайтом на дне нырка и мигала бы при неуязвимости.
	# За позицией и наклоном корабля она следит сама, см. dodge_effect.gd.
	var effect: DodgeEffect = DODGE_EFFECT_SCENE.instantiate()
	effect.target = self
	effect.tilt_source = ship
	get_tree().current_scene.add_child(effect)


# Толчок идёт раньше облака: blast разгоняет только тот дым, что уже висел на этом месте.
# В обратном порядке он растащил бы в кольцо и клубы, выброшенные в этом же кадре, —
# они лежат ровно в его центре, где толчок сильнее всего.
func _spawn_dodge_smoke() -> void:
	_smoke.blast(global_position, dodge_blast_radius, dodge_blast_strength)
	dodge_smoke.burst()


# Раскладывает время перехода по шагам геометрической прогрессией со знаменателем
# dodge_step_falloff, а затем подгоняет сумму обратно под total — так множитель
# меняет ритм шагов, но не длительность нырка.
func _dodge_step_times(total: float) -> Array[float]:
	var weights: Array[float] = []
	var weight := 1.0
	var sum := 0.0
	for step in dodge_steps:
		weights.append(weight)
		sum += weight
		weight *= dodge_step_falloff

	var times: Array[float] = []
	for value in weights:
		times.append(total * value / sum)
	return times


# phase: 0 — корабль в обычном виде, 1 — на дне нырка, сжатый и тёмный.
func _set_dodge_phase(phase: float) -> void:
	ship.scale = _base_ship_scale.lerp(_base_ship_scale * dodge_scale, phase)
	var dark := Color(dodge_darkness, dodge_darkness, dodge_darkness)
	ship.modulate = _base_ship_modulate.lerp(dark, phase)
	# С первой ступеньки погружения корабль уже под дымом и до всплытия его не трогает.
	# Двигатели там же глохнут: под облаком им нечего толкать.
	var submerged := phase > 0.0
	wake.set_submerged(submerged)
	engine_left.set_submerged(submerged)
	engine_right.set_submerged(submerged)


func _send_rocket_charge() -> void:
	rocket_charge_changed.emit(_rocket_charge())


# Готовность ракетной системы от 0 сразу после пуска до 1, когда можно пускать снова.
# Нулевая задержка означает, что система готова всегда.
func _rocket_charge() -> float:
	if rocket_cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - _rocket_cooldown / rocket_cooldown, 0.0, 1.0)


func _send_dodge_charge() -> void:
	var charge := _dodge_charge()
	if charge >= 1.0 and _dodge_charge_sent < 1.0:
		_flash_white()
	elif charge < 1.0:
		_stop_flash()
	_dodge_charge_sent = charge
	dodge_charge_changed.emit(charge)


func _flash_white() -> void:
	_stop_flash()
	ship_material.set_shader_parameter(FLASH_PARAM, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_interval(dodge_ready_flash_duration)
	_flash_tween.tween_callback(ship_material.set_shader_parameter.bind(FLASH_PARAM, 0.0))


# Нырок мог начаться прямо во время вспышки — тогда она гаснет сразу, иначе белый силуэт
# перекрыл бы затемнение погружения.
func _stop_flash() -> void:
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	ship_material.set_shader_parameter(FLASH_PARAM, 0.0)


# Доля набранного заряда нырка: 0 — нырок идёт или перезарядка только началась, 1 — готов.
func _dodge_charge() -> float:
	if _dodge_left > 0.0:
		return 0.0
	if dodge_cooldown <= 0.0:
		return 1.0
	return 1.0 - _dodge_cooldown_left / dodge_cooldown


func _is_invulnerable() -> bool:
	return _invulnerability_left > 0.0 or _dodge_left > 0.0


func _refresh_collision_layer() -> void:
	# Отложенно, потому что метод вызывается в том числе из сигнала столкновения,
	# а посреди обработки столкновений менять физические слои нельзя.
	set_deferred("collision_layer", 0 if _is_invulnerable() else _base_collision_layer)


func _update_ship_texture() -> void:
	var lost := 1.0 - float(health) / float(max_health)
	# Доля потерянного здоровья, переведённая в номер картинки. clampi страхует края:
	# при полном здоровье выходит 0, на нуле и в минусе — последняя, самая битая.
	var index := clampi(int(lost * damage_textures.size()), 0, damage_textures.size() - 1)
	ship.texture = damage_textures[index]


func fire():
	var bullet := BULLET_SCENE.instantiate()
	# Группа выдаётся здесь, а не в сцене пули: вражеская пуля унаследована от той же
	# сцены и получила бы группу тоже. От этих пуль уворачиваются враги, см. scout.gd.
	bullet.add_to_group("player_bullets")
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	# Пуля летит туда, куда повёрнута (см. bullet.gd), поэтому наклон корпуса
	# достаточно передать ей углом. Наклон уже ступенчатый, значит и разброс
	# направлений выстрела получается дискретным, без промежуточных значений.
	bullet.rotation = ship.rotation * bullet_tilt_influence
	_recoil()


func _toggle_targeting() -> void:
	if targeting.is_active():
		targeting.deactivate()
	elif _has_rockets():
		targeting.activate(global_position.x)


func _launch_rocket() -> void:
	for index in rocket_launchers.size():
		var launcher := rocket_launchers[index]
		if launcher.is_loaded():
			launcher.launch(targeting.get_target())
			# Отсчёт взводится только на ушедшей ракете: нажатие по пустым шахтам ничего
			# не пускает, поэтому и придерживать после него нечего.
			_rocket_cooldown = rocket_cooldown
			# Шкала обнуляется в кадр пуска. Без этого при нулевой задержке ветка
			# с отсчётом не сработала бы ни разу, и шкала так и стояла бы полной.
			_send_rocket_charge()
			rocket_launched.emit(index)
			rockets_changed.emit(get_rocket_states())
			break
	# Режим прицеливания нужен только для пуска: без ракет в нём нечего делать.
	if not _has_rockets():
		targeting.deactivate()


func _has_rockets() -> bool:
	for launcher in rocket_launchers:
		if launcher.is_loaded():
			return true
	return false


# Форсаж дают двигателю с той стороны, от которой корабль уходит: уводя машину влево,
# толкается правое сопло. Поэтому направление и сторона двигателя здесь противоположны.
# Что меняется на форсаже — анимация пламени и плотность выхлопа — решает сам двигатель,
# см. ship_engine.gd.
func _update_engines(direction: float) -> void:
	engine_left.set_boosting(direction > 0.0)
	engine_right.set_boosting(direction < 0.0)


func _recoil() -> void:
	if _recoil_tween != null and _recoil_tween.is_running():
		_recoil_tween.kill()

	# Никакой интерполяции: рывок мгновенный, возврат — ступеньками по целому пикселю.
	# Плавное движение ставило бы спрайт на дробные позиции, а в пиксель-арте это
	# читается как размытие, а не как движение.
	# Дёргается только спрайт, а не сам корабль: Muzzle остаётся на месте, и пули
	# продолжают вылетать из одной точки, не разбредаясь вслед за отдачей.
	_recoil_tween = create_tween()
	_recoil_tween.tween_callback(_set_ship_recoil.bind(recoil_distance))
	_recoil_tween.tween_interval(recoil_hold_time)

	var step_time := recoil_return_time / float(recoil_distance)
	for offset in range(recoil_distance - 1, -1, -1):
		_recoil_tween.tween_callback(_set_ship_recoil.bind(offset))
		_recoil_tween.tween_interval(step_time)


func _set_ship_recoil(offset: int) -> void:
	ship.position = _base_ship_position + Vector2.DOWN * offset
