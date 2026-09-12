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

const MAX_AIMERS := 2
const AIM_CHANCE := 0.5

static var _aimers := 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var explosion: AnimatedSprite2D = $Explosion
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var health := 0
var _base_texture: Texture2D
var _flash_tween: Tween
var _dying := false

var _player: Node2D
var _target := Vector2.ZERO
var _state_timer := 0.0
var _aiming := false


func _ready() -> void:
	health = max_health
	_base_texture = sprite.texture
	motion_mode = MOTION_MODE_FLOATING
	_player = _find_player()
	_pick_wander()


func _physics_process(delta: float) -> void:
	if _dying:
		velocity = Vector2.ZERO
		return

	_state_timer -= delta
	if _state_timer <= 0.0:
		_choose_state()

	if _aiming and is_instance_valid(_player):
		_target.x = _player.global_position.x

	var to_target := _target - global_position
	var distance := to_target.length()
	var desired := Vector2.ZERO
	if distance > 1.0:
		desired = to_target / distance * minf(speed, distance * 3.0)
	velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()


func take_damage(amount: int) -> void:
	if _dying:
		return
	health -= amount
	if health <= 0:
		die()
	else:
		_flash()


func die() -> void:
	_dying = true
	_set_aiming(false)
	collision_shape.set_deferred("disabled", true)
	sprite.hide()
	explosion.show()
	explosion.play("destroy")
	await explosion.animation_finished
	queue_free()


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
	var found := get_tree().get_first_node_in_group("player")
	if found == null and get_parent() != null:
		found = get_parent().get_node_or_null("Spaceship")
	return found as Node2D


func _flash() -> void:
	if hit_texture == null:
		return
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	sprite.texture = hit_texture
	_flash_tween = create_tween()
	_flash_tween.tween_callback(_restore_texture).set_delay(hit_duration)


func _restore_texture() -> void:
	sprite.texture = _base_texture
