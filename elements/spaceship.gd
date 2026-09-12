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

@onready var muzzle: Marker2D = $Muzzle

const BULLET_SCENE = preload("res://elements/bullet.tscn")

var health := 0
var _fire_cooldown := 0.0


func _ready() -> void:
	health = max_health
	health_changed.emit(health, max_health)


func _physics_process(delta: float):
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
	health -= amount
	health_changed.emit(health, max_health)


func fire():
	var bullet := BULLET_SCENE.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
