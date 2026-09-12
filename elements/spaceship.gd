extends CharacterBody2D

## Летит при каждом изменении здоровья. На него подписан индикатор хп, чтобы корабль
## ничего не знал про интерфейс и не лез в его узлы.
signal health_changed(health: int, max_health: int)

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

@onready var muzzle: Marker2D = $Muzzle
@onready var ship: Sprite2D = $Ship

const BULLET_SCENE = preload("res://elements/bullet.tscn")

var health := 0
var _fire_cooldown := 0.0
var _invulnerability_left := 0.0
var _base_collision_layer := 0


func _ready() -> void:
	_base_collision_layer = collision_layer
	health = max_health
	health_changed.emit(health, max_health)
	_update_ship_texture()


func _physics_process(delta: float):
	if _invulnerability_left > 0.0:
		_update_invulnerability(delta)

	_fire_cooldown -= delta
	
	if Input.is_action_pressed("fire") and _fire_cooldown <= 0.0: 
		fire()
		_fire_cooldown = 1.0 / fire_rate
	
	var direction := Input.get_axis("move_left", "move_right")
	if direction != 0.0:
		velocity.x = move_toward(velocity.x, direction * max_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
	move_and_slide()


func take_damage(amount: int) -> void:
	if _invulnerability_left > 0.0:
		return
	health -= amount
	health_changed.emit(health, max_health)
	_update_ship_texture()
	_invulnerability_left = invulnerability_duration
	# Корабль уходит со своего слоя физики, и вражеские пули перестают его видеть —
	# пролетают насквозь, а не гаснут о неуязвимую цель. Отложенно, потому что метод
	# вызван из сигнала столкновения, а посреди их обработки слои менять нельзя.
	set_deferred("collision_layer", 0)


func _update_invulnerability(delta: float) -> void:
	_invulnerability_left -= delta
	if _invulnerability_left <= 0.0:
		modulate.a = 1.0
		collision_layer = _base_collision_layer
		return
	# Мигание отсчитывается от остатка неуязвимости, поэтому последняя вспышка всегда
	# заканчивается ровно вместе с ней, а не обрывается на тусклом кадре.
	var dark := fmod(_invulnerability_left, invulnerability_blink_period) < invulnerability_blink_period * 0.5
	modulate.a = invulnerability_blink_alpha if dark else 1.0


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
