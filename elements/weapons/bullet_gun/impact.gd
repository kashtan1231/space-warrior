extends AnimatedSprite2D
class_name Impact

## Брызги попадания, прилипшие к корпусу. Лежат в корне уровня, как DodgeEffect, но каждый
## кадр переставляют себя в точку попадания на корабле и поворачиваются вдоль оси корпуса.
## Будь импакт дочерним узлом корабля, он унаследовал бы его масштаб и мигание неуязвимости,
## которое включается как раз в момент попадания.
## Куда смотрит рисунок на спрайте, знает только сцена: поворот, выставленный узлу
## в редакторе, скрипт запоминает и прибавляет к своему. Так спрайт, нарисованный вбок,
## доворачивается одним полем в инспекторе, а не правкой кода. Основание брызг ставится
## в точку узла через Offset.
## Проигрывается один раз и удаляет себя сама.

var _target: Node2D
var _tilt: Tilt
var _local_offset := Vector2.ZERO
var _outward := 0.0
var _base_rotation := 0.0


func _ready() -> void:
	# Анимация должна быть без Loop: у зацикленной сигнал окончания не приходит никогда.
	animation_finished.connect(queue_free)
	# Поворот из сцены снимается до первого доворота: дальше _follow_target каждый кадр
	# пишет в global_rotation, и авторский угол иначе пропал бы в первом же кадре.
	_base_rotation = rotation
	_follow_target()


# Корабль двигается в _physics_process, а _process кадра идёт после него, поэтому
# импакт берёт уже обновлённую позицию и наклон и не отстаёт на кадр.
func _process(_delta: float) -> void:
	_follow_target()


## Привязывает импакт к кораблю. Вызывается до добавления в дерево.
## hit_position — глобальная точка, где пуля коснулась корпуса.
func attach(target: Node2D, tilt: Tilt, hit_position: Vector2) -> void:
	_target = target
	_tilt = tilt
	# Смещение хранится в системе ненаклонённого корпуса: тогда при любом наклоне
	# достаточно повернуть его на текущий угол, и точка останется на том же месте обшивки.
	_local_offset = (hit_position - target.global_position).rotated(-tilt.current_angle)
	# Брызги торчат из носа наружу, к стрелку: у игрока нос вверху, у кораблей с
	# nose_down — внизу, значит спрайт разворачивается на 180°.
	_outward = PI if tilt.nose_down else 0.0


func _follow_target() -> void:
	# Корабль мог погибнуть и удалиться, пока брызги доигрывают: тогда они остаются
	# там, где видели его в последний раз.
	if not is_instance_valid(_target):
		return
	var angle := _tilt.current_angle
	global_position = _target.global_position + _local_offset.rotated(angle)
	global_rotation = _base_rotation + _outward + angle
