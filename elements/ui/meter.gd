extends Node2D

## Стрелочный прибор для атмосферы: стрелка хаотично ходит возле центра шкалы.
##
## Стрелка не картинка, её пиксели ставит код. Спрайт с поворотом при увеличенном UI
## вылез бы за пиксельную сетку, а линия, построенная по целым пикселям, всегда
## совпадает с сеткой циферблата под любым углом.
##
## Движение устроено как у настоящего прибора: стрелка висит на пружине и время
## от времени получает новую случайную цель, к которой прыгает с перелётом.
## Сверху на это накладывается мелкая дрожь от шума.
##
## Рисует не сам корень, а дочерний узел Needle: его позиция в сцене и есть ось
## стрелки. Корень рисовал бы под детьми, то есть под циферблатом.

## Длина стрелки от оси до кончика, в пикселях исходного рисунка (до увеличения сцены).
@export var length := 16
## Цвет стрелки. Бери тёмный цвет из палитры циферблата.
@export var color := Color("3d3d2c")

@export_group("Shadow")
## Цвет тени под стрелкой. Бери средний тон между стрелкой и фоном экрана, чтобы тень
## читалась, но не спорила со стрелкой. Прозрачность 0 выключает тень.
@export var shadow_color := Color("8a8561")
## Сдвиг тени относительно стрелки, в пикселях исходного рисунка. (1, 0) — на пиксель
## вправо. Задаётся для стрелки, стоящей по центру или наклонённой вправо; при наклоне
## влево тень зеркалится по X и уходит на ту же величину влево.
## Сдвиг вниз уводит тень от оси на рамку экрана, поэтому по Y лучше оставлять 0.
@export var shadow_offset := Vector2i(1, 0)
## На сколько пикселей тень короче стрелки со стороны кончика. 0 — тень во всю длину,
## больше — кончик стрелки торчит над тенью сильнее.
@export_range(0, 8, 1) var shadow_tip_trim := 1

@export_group("Wander")
## Насколько далеко от центра стрелка может выбрать новую цель, в градусах
## в каждую сторону. Больше — прибор «нервничает» сильнее.
@export_range(0.0, 90.0, 0.5) var max_angle := 20.0
## Самая короткая пауза перед выбором новой цели, секунд.
@export var min_interval := 0.3
## Самая длинная пауза перед выбором новой цели, секунд. Пауза каждый раз
## выбирается случайно между min_interval и max_interval.
@export var max_interval := 1.5

@export_group("Spring")
## Жёсткость пружины. Больше — стрелка быстрее и резче рвётся к цели.
@export var stiffness := 120.0
## Затухание качаний. Меньше — стрелка сильнее проскакивает цель и дольше
## качается; больше — подходит к цели плавно, без перелёта.
@export var damping := 8.0

@export_group("Jitter")
## Размах мелкой дрожи поверх основного движения, в градусах. 0 — без дрожи.
@export var jitter_angle := 1.5
## Как быстро меняется дрожь. Больше — трясётся чаще.
@export var jitter_speed := 12.0

# Самый длинный шаг интегрирования пружины, секунд. При просадке кадра большой
# delta разогнал бы пружину до бесконечности, поэтому шаг обрезается.
const MAX_STEP := 1.0 / 30.0

@onready var needle: Node2D = $Needle

# Угол стрелки в радианах: 0 — строго вверх, плюс — вправо.
var _angle := 0.0
# Угловая скорость, радиан в секунду.
var _velocity := 0.0
var _target := 0.0
var _time_to_next_target := 0.0
var _time := 0.0
var _noise := FastNoiseLite.new()
# Кончик, нарисованный в прошлый раз. Перерисовка нужна, только когда он сдвинулся
# хотя бы на пиксель.
var _tip := Vector2i.ZERO


func _ready() -> void:
	_noise.seed = randi()
	# Стрелка рисуется через сигнал draw узла Needle: Godot вызывает его, когда узел
	# просит перерисовку, и рисовать в этот момент можно методами самого Needle.
	needle.draw.connect(_on_needle_draw)
	_tip = _tip_for(_angle)
	needle.queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	_time_to_next_target -= delta
	if _time_to_next_target <= 0.0:
		_target = deg_to_rad(randf_range(-max_angle, max_angle))
		_time_to_next_target = randf_range(min_interval, max_interval)

	var step := minf(delta, MAX_STEP)
	var acceleration := stiffness * (_target - _angle) - damping * _velocity
	_velocity += acceleration * step
	_angle += _velocity * step

	var jitter := deg_to_rad(jitter_angle) * _noise.get_noise_1d(_time * jitter_speed)
	var tip := _tip_for(_angle + jitter)
	# То, что нарисовано в _draw, Godot запоминает и показывает каждый кадр сам.
	# Перерисовывать стоит только при изменении, иначе это пустая работа.
	if tip != _tip:
		_tip = tip
		needle.queue_redraw()


## Толкает стрелку, как будто прибор получил удар. Сила — угловая скорость
## в градусах в секунду; знак задаёт сторону. Пригодится, чтобы связать стрелку
## с событиями игры.
func kick(strength: float) -> void:
	_velocity += deg_to_rad(strength)


func _on_needle_draw() -> void:
	var pixels := _line_pixels(Vector2i.ZERO, _tip)
	# Сторона тени берётся по нарисованному кончику, а не по углу: иначе при угле чуть
	# левее нуля стрелка ещё стоит ровно, а тень уже перескочила бы влево.
	var offset := shadow_offset
	if _tip.x < 0:
		offset.x = -offset.x
	# Всё, что нарисовано раньше, лежит ниже. Тень идёт первой, и там, где она заходит
	# под стрелку, её перекрывает сама стрелка.
	# Пиксели линии идут от оси к кончику, поэтому укорачивание тени — это отрезанный хвост.
	for pixel in pixels.slice(0, maxi(pixels.size() - shadow_tip_trim, 0)):
		needle.draw_rect(Rect2(pixel + offset, Vector2.ONE), shadow_color)
	for pixel in pixels:
		needle.draw_rect(Rect2(pixel, Vector2.ONE), color)


func _tip_for(angle: float) -> Vector2i:
	var direction := Vector2(sin(angle), -cos(angle))
	return Vector2i((direction * length).round())


# Пиксели отрезка от from до to по алгоритму Брезенхэма: ровно по одному пикселю
# на шаг вдоль длинной оси, без дыр и без утолщений.
func _line_pixels(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var pixels: Array[Vector2i] = []
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var error := dx + dy
	var current := from
	while true:
		pixels.append(current)
		if current == to:
			break
		var doubled := error * 2
		if doubled >= dy:
			error += dy
			current.x += sx
		if doubled <= dx:
			error += dx
			current.y += sy
	return pixels
