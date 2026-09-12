extends CharacterBody2D

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

var _fire_cooldown := 0.0


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

func fire():
	var bullet := BULLET_SCENE.instantiate()
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
