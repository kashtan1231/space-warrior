extends AnimatedSprite2D
class_name Fire

## Пламя, разгорающееся в точке попадания ракеты. Лежит в корне уровня и каждый кадр
## переставляет себя в свою точку на обшивке — тем же приёмом, что брызги попадания,
## см. impact.gd. Дочерним узлом врага огонь наследовал бы его масштаб и мигание урона.
##
## Сам спрайт всегда стоит вертикально: пламя тянется вверх, а не вдоль накренившегося
## корпуса, поэтому наклон врага двигает только точку горения, но не сам огонь.
## Анимация в сцене должна быть с включённым Loop: огонь горит дольше одного прохода.

## Сколько секунд горит пламя. 0 — горит бесконечно, пока враг жив: так удобно смотреть
## анимацию в редакторе и так делается неугасающий пожар. Время отсчитывается от
## попадания, а не от конца разгорания.
@export var burn_time := 2.0
## За сколько секунд пламя уходит в прозрачность в конце горения. Это время входит
## в burn_time, а не добавляется к нему, поэтому огонь пропадает ровно через burn_time.
## 0 — гаснет разом, целым кадром.
@export var fade_time := 0.5

var _target: Node2D
var _tilt: Tilt
var _local_offset := Vector2.ZERO


func _ready() -> void:
	_follow_target()
	if burn_time > 0.0:
		_start_burn()


# Враг двигается в _physics_process, а _process кадра идёт после него, поэтому огонь
# берёт уже обновлённые позицию и наклон и не отстаёт на кадр.
func _process(_delta: float) -> void:
	# Враг взорвался и ушёл из дерева — гореть больше не на чем.
	if not is_instance_valid(_target):
		queue_free()
		return
	_follow_target()


## Привязывает пламя к кораблю. Вызывается до добавления в дерево.
## hit_position — глобальная точка, где ракета коснулась обшивки.
func attach(target: Node2D, tilt: Tilt, hit_position: Vector2) -> void:
	_target = target
	_tilt = tilt
	# Смещение хранится в системе ненаклонённого корпуса: тогда при любом наклоне
	# достаточно повернуть его на текущий угол, и огонь останется на том же месте обшивки.
	_local_offset = (hit_position - target.global_position).rotated(-tilt.current_angle)
	# От попадания остаётся только направление: длина вектора зависит от размеров обоих
	# хитбоксов и от того, каким боком вошла ракета, поэтому очаг оказывался то у обшивки,
	# то в стороне от неё. Глубину посадки знает сама цель: сцена огня одна на всех, а корпус
	# у каждого корабля свой. У нулевого вектора normalized() даёт ноль — попадание точно
	# в центр там и останется, это не ошибка.
	_local_offset = _local_offset.normalized() * target.hull_radius


func _start_burn() -> void:
	# Угасание не может быть длиннее самого горения: иначе огонь начинал бы гаснуть
	# раньше, чем появился.
	var fade := minf(fade_time, burn_time)
	var tween := create_tween()
	tween.tween_interval(burn_time - fade)
	tween.tween_property(self, "modulate:a", 0.0, fade)
	tween.tween_callback(queue_free)


func _follow_target() -> void:
	global_position = _target.global_position + _local_offset.rotated(_tilt.current_angle)
