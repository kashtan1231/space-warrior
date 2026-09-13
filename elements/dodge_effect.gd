extends AnimatedSprite2D
class_name DodgeEffect

## Вспышка нырка. Лежит в корне уровня, а не в детях корабля, но каждый кадр
## переставляет себя в его позицию и доворачивает на его наклон. Будь она дочерним
## узлом, она унаследовала бы масштаб корабля, мигание неуязвимости и затемнение нырка.
## Проигрывается один раз и удаляет себя сама.

## Узел, за чьей позицией едет вспышка. Назначается кораблём до добавления в дерево.
var target: Node2D
## Узел, чей поворот прибавляется к вспышке, — наклоняемый спрайт корпуса. Отдельно
## от target, потому что наклоняется спрайт, а не сам корабль.
var tilt_source: Node2D

var _base_rotation := 0.0


func _ready() -> void:
	# Поворот, выставленный в сцене, — это ориентация спрайта. Наклон корабля
	# прибавляется к нему, а не заменяет его.
	_base_rotation = rotation
	# Анимация должна быть без Loop: у зацикленной сигнал окончания не приходит никогда,
	# и вспышка висела бы на экране вечно.
	animation_finished.connect(queue_free)
	_follow_target()


# Корабль двигается в _physics_process, а _process кадра идёт после него, поэтому
# вспышка берёт уже обновлённую позицию и не отстаёт на кадр.
func _process(_delta: float) -> void:
	_follow_target()


func _follow_target() -> void:
	# Корабль мог погибнуть и удалиться, пока вспышка ещё доигрывает: тогда она
	# остаётся там, где видела его в последний раз.
	if not is_instance_valid(target) or not is_instance_valid(tilt_source):
		return
	global_position = target.global_position
	rotation = _base_rotation + tilt_source.rotation
