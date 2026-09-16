extends AnimatedSprite2D
class_name RocketLauncher

## Сцена ракеты, которая вылетает из шахты.
@export var rocket_scene: PackedScene
## Номер кадра анимации launch, на котором ракета покидает шахту и появляется снаряд.
## Должен совпадать с первым кадром, где ракеты в шахте уже не нарисовано: раньше — на
## экране окажутся две ракеты сразу, позже — ракета на мгновение пропадёт.
@export var launch_frame := 2

const LAUNCH_ANIMATION := &"launch"

@onready var muzzle: Marker2D = $Muzzle

var _loaded := true
var _target: Node2D


func _ready() -> void:
	frame_changed.connect(_on_frame_changed)
	# После пуска шахта пуста: последний кадр с рассеявшимся дымом сменяется пустотой.
	animation_finished.connect(hide)


## Есть ли в шахте ракета. Пусковая установка одноразовая: после пуска остаётся пустой.
func is_loaded() -> bool:
	return _loaded


## Запускает ракету по цели. Сама ракета вылетит позже, на кадре launch_frame.
func launch(target: Node2D) -> void:
	_loaded = false
	_target = target
	play(LAUNCH_ANIMATION)


# frame_changed приходит и при ручной смене кадра, не только во время проигрывания,
# поэтому ракета спавнится лишь в идущей анимации.
func _on_frame_changed() -> void:
	if is_playing() and frame == launch_frame:
		_spawn_rocket()


func _spawn_rocket() -> void:
	# Ракета кладётся в корень уровня, как пуля: дочерний узел корабля ездил бы
	# за ним вбок и наклонялся вместе с корпусом уже после вылета.
	var rocket: Rocket = rocket_scene.instantiate()
	# Между нажатием и вылетом проходит анимация, и цель могла за это время удалиться.
	# Удалённый узел нельзя присвоить типизированной переменной — движок выдаст ошибку.
	rocket.target = _target if is_instance_valid(_target) else null
	get_tree().current_scene.add_child(rocket)
	rocket.global_position = muzzle.global_position
