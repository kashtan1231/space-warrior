extends CharacterBody2D

## Летит при каждом изменении здоровья. На него подписан индикатор хп, чтобы корабль
## ничего не знал про интерфейс и не лез в его узлы.
signal health_changed(health: int, max_health: int)

## Летит один раз, в момент гибели корабля, до проигрывания взрыва. Сюда подключатся
## экран поражения и счётчик жизней, когда появятся.
signal died

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

@export_group("Death")
## Через сколько секунд после начала основного взрыва стартует второй (узел Blast).
## 0 — оба одновременно. Корабль удаляется, только когда доиграют оба, поэтому
## большая задержка удлиняет гибель на столько же.
@export var blast_delay := 0.3

@onready var muzzle: Marker2D = $Muzzle
@onready var ship: Sprite2D = $Ship
@onready var engine_left: AnimatedSprite2D = $Ship/Engine/EngineLeft
@onready var engine_right: AnimatedSprite2D = $Ship/Engine/EngineRight
@onready var explosion: AnimatedSprite2D = $Explosion
@onready var blast: AnimatedSprite2D = $Explosion/Blast
@onready var hitbox: CollisionPolygon2D = $Hitbox
@onready var tilt: Tilt = $Tilt

const BULLET_SCENE = preload("res://elements/weapons/bullet_gun/bullet.tscn")
const DODGE_EFFECT_SCENE = preload("res://elements/dodge_effect.tscn")

var health := 0
var _fire_cooldown := 0.0
var _invulnerability_left := 0.0
var _dodge_left := 0.0
var _dodge_cooldown_left := 0.0
var _base_collision_layer := 0
var _base_ship_scale := Vector2.ONE
var _base_ship_position := Vector2.ZERO
var _recoil_tween: Tween
var _dying := false
var _base_ship_modulate := Color.WHITE


func _ready() -> void:
	_base_collision_layer = collision_layer
	_base_ship_scale = ship.scale
	_base_ship_position = ship.position
	_base_ship_modulate = ship.modulate
	health = max_health
	health_changed.emit(health, max_health)
	_update_ship_texture()


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
	
	var direction := Input.get_axis("move_left", "move_right")
	tilt.direction = direction
	_update_engines(direction)
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * max_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	move_and_slide()


func take_damage(amount: int) -> void:
	if _dying or _is_invulnerable():
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
	hitbox.set_deferred("disabled", true)
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
		_dodge_cooldown_left -= delta

	if _dodge_left > 0.0:
		_dodge_left -= delta
		if _dodge_left <= 0.0:
			_dodge_left = 0.0
			_dodge_cooldown_left = dodge_cooldown
			_refresh_collision_layer()
	elif _dodge_cooldown_left <= 0.0 and Input.is_action_just_pressed("dodge"):
		_start_dodge()


func _start_dodge() -> void:
	_dodge_left = dodge_duration
	_refresh_collision_layer()
	_spawn_dodge_effect()

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
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	# Пуля летит туда, куда повёрнута (см. bullet.gd), поэтому наклон корпуса
	# достаточно передать ей углом. Наклон уже ступенчатый, значит и разброс
	# направлений выстрела получается дискретным, без промежуточных значений.
	bullet.rotation = ship.rotation * bullet_tilt_influence
	_recoil()


# Разгоняется двигатель с той стороны, от которой корабль уходит: уводя машину влево,
# толкается правое сопло. Поэтому направление и сторона двигателя здесь противоположны.
func _update_engines(direction: float) -> void:
	_set_engine_animation(engine_left, &"boost" if direction > 0.0 else &"idle")
	_set_engine_animation(engine_right, &"boost" if direction < 0.0 else &"idle")


func _set_engine_animation(engine: AnimatedSprite2D, animation: StringName) -> void:
	if engine.animation != animation or not engine.is_playing():
		engine.play(animation)


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
