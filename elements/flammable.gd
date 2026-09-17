extends Node
class_name Flammable

## Горючий корпус. Узел-компонент: кладётся в сцену корабля, оружие сообщает ему, в какую
## форму корпуса пришло попадание, а компонент сам решает, где загорится пламя. Своего кода
## в каждом корабле для этого не нужно, и подбирать числа под каждого врага — тоже.
##
## Очаг садится на поверхность той самой формы, в которую вошёл снаряд, со стороны подлёта:
## у круглого скаута это кромка корпуса, у бомбера — бок именно того пода или балки, куда
## пришла ракета. Поэтому точность горения — это точность коллизий корабля, а не отдельная
## настройка: чем ближе хитбокс к рисунку, тем вернее садится огонь.

## Сцена пламени, которая ставится в точке попадания. Сколько очаг горит и как гаснет,
## настраивается в самой сцене огня, см. fire.gd: эти параметры общие для всех кораблей.
@export var fire_scene: PackedScene
## Узел, внутри которого живут очаги. Обычно спрайт корпуса: тогда пламя едет вместе
## с кораблём, заваливается с ним в вираже и пропадает, когда корпус прячется при взрыве.
## Не сам корабль: у CharacterBody2D огонь остался бы висеть прямо, пока корпус кренится.
@export var hull: Node2D


## Зажигает очаг на обшивке. shape — узел формы, в которую вошёл снаряд: его приносит
## сигнал столкновения, см. bullet.gd. Это либо CollisionShape2D, либо CollisionPolygon2D:
## корпуса кораблей собраны и так, и так — у врагов из форм, у игрока из полигона.
## from — глобальная точка, откуда пришло попадание; от неё берётся только сторона,
## а место на обшивке считается по самой форме.
func ignite(shape: Node2D, from: Vector2) -> void:
	var fire: Fire = fire_scene.instantiate()
	# Позиция выставляется после добавления в дерево: пока у узла нет родителя,
	# глобальные координаты не во что переводить.
	hull.add_child(fire)
	fire.global_position = _surface_point(shape, from)


# Точка на поверхности формы, ближайшая к тому месту, откуда пришёл снаряд. Считается
# в системе координат самой формы, поэтому поворот и масштаб корабля учитываются сами
# собой, а обратный перевод возвращает готовую глобальную точку.
func _surface_point(shape: Node2D, from: Vector2) -> Vector2:
	var to_world := shape.global_transform
	var local := to_world.affine_inverse() * from
	if shape is CollisionShape2D:
		return to_world * _closest_shape_point((shape as CollisionShape2D).shape, local)
	return to_world * _closest_polygon_point((shape as CollisionPolygon2D).polygon, local)


# Ближайшая к point точка на границе формы, в её собственных координатах. Снаряд приходит
# снаружи, поэтому это и есть место входа в обшивку. Форму, которой здесь нет, огонь
# примет за точку и сядет в её центр — заметно, но не ломает ничего.
func _closest_shape_point(shape: Shape2D, point: Vector2) -> Vector2:
	if shape is CircleShape2D:
		# Нулевой вектор normalized() оставляет нулём: попадание точно в центр там и горит.
		return point.normalized() * (shape as CircleShape2D).radius
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		# Капсула в Godot вытянута вдоль Y, а height считается вместе с обеими полусферами.
		# Её сердцевина — отрезок между их центрами, и поверхность отстоит от него на радиус.
		var half_core := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		var core := Vector2(0.0, clampf(point.y, -half_core, half_core))
		return core + (point - core).normalized() * capsule.radius
	if shape is RectangleShape2D:
		var half_size := (shape as RectangleShape2D).size * 0.5
		return point.clamp(-half_size, half_size)
	return Vector2.ZERO


# То же самое для корпуса, нарисованного полигоном: обшивка — это его рёбра, и ближайшая
# точка ищется перебором по ним. Рёбер у корпуса десяток, так что перебор на попадание
# дешевле, чем держать рядом с полигоном заранее разобранную форму.
func _closest_polygon_point(polygon: PackedVector2Array, point: Vector2) -> Vector2:
	var best := polygon[0]
	var best_distance := INF
	for index in polygon.size():
		var edge_point := Geometry2D.get_closest_point_to_segment(
			point, polygon[index], polygon[(index + 1) % polygon.size()])
		var distance := point.distance_squared_to(edge_point)
		if distance < best_distance:
			best = edge_point
			best_distance = distance
	return best
