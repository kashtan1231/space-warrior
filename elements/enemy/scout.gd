extends CharacterBody2D

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

	if _aiming and is_instance_valid(_player):
		_target.x = _player.global_position.x

	var to_target := _target - global_position
	var distance := to_target.length()
	var desired := Vector2.ZERO
	if distance > 1.0:
		desired = to_target / distance * minf(speed, distance * 3.0)
	velocity = velocity.move_toward(desired, acceleration * delta)
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
	_set_aiming(false)
	collision_shape.set_deferred("disabled", true)
	sprite.hide()
	weapons.hide()
	explosion.show()
	explosion.play("destroy")
	await explosion.animation_finished
	queue_free()


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


func _pick_wander() -> void:
	var width := get_viewport_rect().size.x
	_target = Vector2(
		randf_range(side_margin, width - side_margin),
		randf_range(band_top, band_bottom)
	)
	_state_timer = randf_range(0.8, 2.0)


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
