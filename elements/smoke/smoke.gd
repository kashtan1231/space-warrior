extends CanvasGroup
class_name Smoke

## Весь дым уровня. Клубы от всех ракет и торпед живут здесь, в одном узле, а не внутри
## снарядов: шлейф не пропадает вместе с ракетой, когда та взорвалась или ушла за экран,
## а доживает и рассеивается сам.
##
## Каждый клуб — частица в потоке воздуха. Воздух идёт навстречу кораблям со скоростью
## прокрутки фона, помноженной на wind_scale, и закручивается вихрями; клуб тормозит о воздух и постепенно начинает
## плыть вместе с ним. Со временем клуб расплывается и бледнеет, как пятно при диффузии.
## Корабли и снаряды с компонентом Wake раздвигают дым на своём пути и тащат его за собой
## (см. wake.gd), взрывы расталкивают его вокруг себя (см. blast). Друг на друга клубы
## не влияют: дым, который разогнал корабль, не увлекает за собой соседний.
##
## Клуб живёт до конца своего времени или до того, как поток унесёт его за край экрана, —
## смотря что случится раньше. Поэтому долгий дым стоит ровно столько, сколько его видно.
##
## Рисуется дым в два прохода. Узел — это CanvasGroup: сначала дочерний Puffs складывает
## все клубы в отдельный буфер как плотность (см. smoke_puff.gdshader), затем материал
## самого узла переводит сумму в цвета палитры крупными пикселями (см. smoke.gdshader).
##
## Сцена дыма должна состоять в группе smoke: по ней дым находят сопла, корабли и ракеты.

## Цвет пламени, которым светится горячий дым у сопла. Сами цвета задаются в материале
## узла Smoke, здесь — только выбор между ними.
enum Flame { ROCKET, TORPEDO }

@export_group("Air")
## Фон уровня. Воздух идёт навстречу кораблям с той же скоростью, с какой прокручивается
## фон: корабли будто летят вперёд, а брошенный дым остаётся позади и уплывает вниз.
@export var background: ScrollingBackground
## Во сколько раз воздух движется медленнее или быстрее фона. 1 — честно: дым висит
## в том же воздухе, сквозь который летят корабли, и уходит за нижний край экрана
## примерно за семь секунд. Меньше — дым частично летит вместе с кораблями, дольше
## остаётся в кадре и успевает расползтись, но связь с фоном теряется. 0 — воздух
## неподвижен относительно экрана, и дым не сносит вовсе: тогда он держится до конца
## lifetime, и клубов на экране становится заметно больше.
@export_range(0.0, 2.0, 0.05, "or_greater") var wind_scale := 1.0
## Как быстро клуб теряет собственную скорость и подхватывается воздухом, в долях за секунду.
## Больше — выхлоп и толчки гаснут почти сразу, дым послушно плывёт с потоком; меньше —
## клубы долго летят по инерции, и взрыв разбрасывает их дальше.
@export var drag := 3.0

@export_group("Turbulence")
## Скорость завихрений воздуха, пикселей в секунду. 0 — шлейф ровный, как по линейке;
## больше — извивается, а на краях рвётся на отдельные клубы.
@export var turbulence := 35.0
## Размер одного завихрения, пикселей. Меньше — дым мелко рябит; больше — шлейф плавно
## изгибается широкими волнами.
@export var eddy_size := 120.0
## Насколько быстро завихрения меняют форму сами по себе, радиан фазы в секунду.
## 0 — рисунок вихрей застыл и только плывёт вместе с воздухом; 1 — заметно меняется
## примерно за шесть секунд; больше — дым беспокойно переливается на месте.
@export var eddy_change := 0.6

@export_group("Limits")
## Сколько клубов может быть на уровне одновременно. При переполнении новый клуб занимает
## место самого старого, и шлейфы начинают укорачиваться. Читается один раз при запуске.
@export var max_puffs := 1024

## Группа, в которой состоит узел дыма.
const GROUP := &"smoke"
# Имя uniform-параметра в smoke.gdshader.
const CANVAS_SIZE_PARAM := &"canvas_size"
# С какой доли жизни клуб начинает дотаивать до нуля. Без этого самый бледный слой
# пропадал бы целым куском в кадр, когда клуб удаляется.
const FADE_START := 0.7
# Волны, из которых складываются завихрения: направление в градусах, длина волны в долях
# eddy_size и скорость смены рисунка в долях eddy_change. Направления взяты вразнобой,
# а длины не кратны друг другу, чтобы сумма не складывалась в заметную на глаз сетку.
const EDDY_WAVES: Array[Vector3] = [
	Vector3(0.0, 1.0, 1.0),
	Vector3(67.0, 0.73, 1.3),
	Vector3(131.0, 1.37, 0.8),
	Vector3(211.0, 0.53, 1.6),
]
# Доля turbulence на одну волну. Четыре волны почти никогда не совпадают по фазе, и
# типичная скорость вихря получается порядка turbulence, а не вчетверо больше.
const EDDY_WAVE_SHARE := 0.5

@onready var puffs: Node2D = $Puffs
@onready var smoke_material: ShaderMaterial = material

# Клубы хранятся не объектами, а набором параллельных массивов: клуб номер i — это i-е
# значение в каждом из них. Тысяча узлов с _physics_process стоила бы в разы дороже.
var _count := 0
var _capacity := 0
var _positions := PackedVector2Array()
var _velocities := PackedVector2Array()
var _ages := PackedFloat32Array()
var _lifetimes := PackedFloat32Array()
# При диффузии со временем линейно растёт не размер пятна, а его квадрат. Поэтому хранится
# квадрат размера при вылете и скорость его роста, а сам размер считается при отрисовке.
var _start_sizes_sq := PackedFloat32Array()
var _size_growths := PackedFloat32Array()
var _densities := PackedFloat32Array()
var _hot_times := PackedFloat32Array()
var _flames := PackedFloat32Array()
# Экземпляр снаряда, выпустившего клуб: его собственный след этот клуб не трогает.
var _sources := PackedInt64Array()

var _time := 0.0
# Самое большое число клубов с начала уровня. Только для отладочного счётчика.
var _peak_count := 0
# Номер физического кадра, в котором дым последний раз сделал шаг, см. add_puff.
var _last_step_frame := -1
# Волны завихрений на текущий кадр: волновой вектор, направление скорости и фаза.
var _eddy_vectors := PackedVector2Array()
var _eddy_sides := PackedVector2Array()
var _eddy_phases := PackedFloat32Array()


func _ready() -> void:
	_capacity = max_puffs
	_positions.resize(_capacity)
	_velocities.resize(_capacity)
	_ages.resize(_capacity)
	_lifetimes.resize(_capacity)
	_start_sizes_sq.resize(_capacity)
	_size_growths.resize(_capacity)
	_densities.resize(_capacity)
	_hot_times.resize(_capacity)
	_flames.resize(_capacity)
	_sources.resize(_capacity)
	_eddy_vectors.resize(EDDY_WAVES.size())
	_eddy_sides.resize(EDDY_WAVES.size())
	_eddy_phases.resize(EDDY_WAVES.size())
	# Рисует клубы не сам узел, а дочерний Puffs со своим материалом: у самой группы
	# материал уже занят раскраской. Обработчик сигнала draw вправе рисовать на узле,
	# который этот сигнал послал, — так весь код дыма остаётся в одном скрипте.
	puffs.draw.connect(_draw_puffs)
	get_viewport().size_changed.connect(_update_canvas_size)
	_update_canvas_size()


func _physics_process(delta: float) -> void:
	_time += delta
	_last_step_frame = Engine.get_physics_frames()
	var wind := _wind()
	_update_eddies()
	# Следы толкают дым до шага: скорости, которые они выдали, сразу же и сдвинут клубы.
	for node in get_tree().get_nodes_in_group(Wake.GROUP):
		var wake := node as Wake
		if wake.is_pushing():
			_apply_wake(wake, wind, delta)
	_step_puffs(wind, delta)
	puffs.queue_redraw()


## Выпускает клуб дыма. Вызывает сопло, см. smoke_trail.gd. age — сколько секунд клуб
## уже прожил к этому моменту: сопло выпускает клубы между кадрами, и клуб, вылетевший
## в начале кадра, успел отлететь от сопла. Позицию сопло передаёт уже с учётом этого.
func add_puff(position: Vector2, velocity: Vector2, age: float, trail: SmokeTrail) -> void:
	var index := _count
	if _count < _capacity:
		_count += 1
		# Пик считается здесь, а не в шаге дыма: число клубов растёт только тут, а сопла
		# успевают выпустить дым уже после того, как дым сделал свой шаг в этом кадре.
		_peak_count = maxi(_peak_count, _count)
	else:
		index = _oldest_puff()
	# Дым в этом кадре ещё не шагал — значит, шаг впереди, и он сдвинет и состарит клуб
	# на целый кадр. Клуб откатывается на кадр назад, чтобы после шага оказаться ровно там,
	# где его выпустили. Так порядок узлов в дереве не влияет на то, где рождается дым.
	if _last_step_frame != Engine.get_physics_frames():
		var delta := get_physics_process_delta_time()
		position -= velocity * delta
		age -= delta
	_positions[index] = position
	_velocities[index] = velocity
	_ages[index] = age
	_lifetimes[index] = trail.lifetime
	_start_sizes_sq[index] = trail.start_size * trail.start_size
	_size_growths[index] = (trail.end_size * trail.end_size - trail.start_size * trail.start_size) \
			/ trail.lifetime
	_densities[index] = trail.density
	_hot_times[index] = trail.hot_time
	_flames[index] = float(trail.flame)
	_sources[index] = trail.get_source_id()


## Сколько клубов дыма живёт прямо сейчас.
func get_puff_count() -> int:
	return _count


## Самое большое число клубов с начала уровня. По нему видно, насколько близко дым подходил
## к max_puffs: текущее число к моменту, когда на него смотришь, уже успевает упасть.
func get_peak_puff_count() -> int:
	return _peak_count


## Расталкивает дым вокруг точки взрыва. strength — скорость, с которой разлетается дым
## в самом центре, пикселей в секунду; к краю radius толчок линейно слабеет до нуля.
func blast(center: Vector2, radius: float, strength: float) -> void:
	for index in _count:
		var offset := _positions[index] - center
		var distance := offset.length()
		if distance >= radius:
			continue
		# Клуб ровно в центре взрыва: направления «от центра» нет, берём случайное.
		var away := offset / distance if distance > 0.001 else Vector2.from_angle(randf() * TAU)
		_velocities[index] += away * strength * (1.0 - distance / radius)


func _step_puffs(wind: Vector2, delta: float) -> void:
	var bounds := _screen_bounds()
	# Доля разницы скоростей клуба и воздуха, которая гаснет за кадр. Экспонента, а не
	# drag * delta: результат не зависит от частоты кадров, и клуб никогда не проскакивает
	# скорость воздуха, даже при большом drag.
	var catch_up := 1.0 - exp(-drag * delta)
	# Обход с конца: удалённый клуб заменяется последним, а последний уже обработан.
	for index in range(_count - 1, -1, -1):
		_ages[index] += delta
		if _ages[index] >= _lifetimes[index]:
			_remove_puff(index)
			continue
		var position := _positions[index]
		var velocity := _velocities[index]
		var air := wind + _eddy_velocity(position, wind)
		velocity += (air - velocity) * catch_up
		position += velocity * delta
		_velocities[index] = velocity
		_positions[index] = position
		# Клуб целиком ушёл за край экрана и удаляется от него: вернуть его в кадр потоку
		# уже нечем, а считался бы он наравне со всеми. Проверка скорости обязательна:
		# дым над верхним краем встречный поток как раз несёт обратно в кадр.
		var away := _offscreen_offset(position, bounds)
		if away.dot(velocity) > 0.0 \
				and away.length_squared() > _start_sizes_sq[index] + _size_growths[index] * _ages[index]:
			_remove_puff(index)


# Корабль или снаряд раздвигает дым с пути и увлекает его за собой. Путь за кадр —
# отрезок, а не точка: пуля пролетает за кадр больше собственного размера и без этого
# проскакивала бы клубы насквозь.
func _apply_wake(wake: Wake, wind: Vector2, delta: float) -> void:
	var start := wake.get_segment_start()
	var end := wake.get_segment_end()
	var radius := wake.radius
	var reach := Vector2(radius, radius)
	var box_min := Vector2(minf(start.x, end.x), minf(start.y, end.y)) - reach
	var box_max := Vector2(maxf(start.x, end.x), maxf(start.y, end.y)) + reach
	var wake_velocity := wake.get_velocity()
	# Толчок зависит от скорости сквозь воздух, а не по экрану: неподвижный на экране
	# корабль всё равно летит навстречу потоку и раздвигает дым, который на него наплывает.
	var push_speed := (wake_velocity - wind).length() * wake.push
	var source := wake.get_source_id()
	# Клуб точно на оси пути: направления «от оси» нет, он уходит вбок от курса.
	var side := (end - start).orthogonal().normalized()
	if side == Vector2.ZERO:
		side = Vector2.RIGHT

	for index in _count:
		var position := _positions[index]
		# Дешёвая отсечка по прямоугольнику: большинство клубов далеко от любого следа.
		if position.x < box_min.x or position.x > box_max.x \
				or position.y < box_min.y or position.y > box_max.y:
			continue
		if _sources[index] == source:
			continue
		var offset := position - Geometry2D.get_closest_point_to_segment(position, start, end)
		var distance_sq := offset.length_squared()
		if distance_sq >= radius * radius:
			continue
		var distance := sqrt(distance_sq)
		var falloff := 1.0 - distance / radius
		var velocity := _velocities[index]
		# Увлечение: дым у самого корпуса подтягивается к скорости корабля.
		velocity += (wake_velocity - velocity) * (1.0 - exp(-wake.drag * falloff * delta))
		# Вытеснение: скорость ухода с пути (относительно воздуха) не меньше положенной.
		# Именно «не меньше», а не «прибавить»: корабль, который висит в облаке несколько
		# кадров подряд, держит коридор открытым, но не разгоняет дым с каждым кадром сильнее.
		var away := offset / distance if distance > 0.001 else side
		var outward := (velocity - wind).dot(away)
		var needed := push_speed * falloff
		if outward < needed:
			velocity += away * (needed - outward)
		_velocities[index] = velocity


# Скорость завихрений в точке. Поле строится как ротор суммы плоских волн: у такого поля
# нет ни источников, ни стоков, поэтому дым в нём закручивается, но не собирается в точки
# и не разбегается из них — как в настоящем несжимаемом воздухе.
func _eddy_velocity(position: Vector2, wind: Vector2) -> Vector2:
	# Вихри переносятся тем же воздухом, что и дым: их рисунок едет вниз вместе с потоком.
	# Иначе шлейф гнулся бы на одних и тех же неподвижных местах экрана.
	var drifted := position - wind * _time
	var velocity := Vector2.ZERO
	for wave in _eddy_vectors.size():
		velocity += _eddy_sides[wave] * cos(_eddy_vectors[wave].dot(drifted) + _eddy_phases[wave])
	return velocity * turbulence * EDDY_WAVE_SHARE


func _update_eddies() -> void:
	for wave in EDDY_WAVES.size():
		var settings := EDDY_WAVES[wave]
		var direction := Vector2.from_angle(deg_to_rad(settings.x))
		_eddy_vectors[wave] = direction * TAU / (eddy_size * settings.y)
		# Скорость направлена поперёк волны: вдоль неё воздух бы сжимался и расширялся.
		_eddy_sides[wave] = direction.orthogonal()
		# Постоянный сдвиг по номеру волны не даёт всем волнам стартовать в одной фазе.
		_eddy_phases[wave] = _time * eddy_change * settings.z + wave * 2.1


# Насколько клуб вышел за края экрана: нулевой вектор — центр клуба ещё в кадре, иначе
# вектор от ближайшего края до центра. Его длина — это и есть, на сколько клуб вынесло.
func _offscreen_offset(position: Vector2, bounds: Rect2) -> Vector2:
	var end := bounds.end
	var offset := Vector2.ZERO
	if position.x < bounds.position.x:
		offset.x = position.x - bounds.position.x
	elif position.x > end.x:
		offset.x = position.x - end.x
	if position.y < bounds.position.y:
		offset.y = position.y - bounds.position.y
	elif position.y > end.y:
		offset.y = position.y - end.y
	return offset


# Видимая область уровня в глобальных координатах. Канвас-трансформация учтена на будущее:
# появится камера — границы поедут вместе с ней, а не останутся в углу мира.
func _screen_bounds() -> Rect2:
	var viewport := get_viewport()
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()


func _wind() -> Vector2:
	# Фон сдвигает окно по своей текстуре, поэтому его скорость — в пикселях текстуры.
	# На экране она больше во столько раз, во сколько растянут спрайт.
	return Vector2.DOWN * background.speed * background.global_scale.y * wind_scale


func _remove_puff(index: int) -> void:
	_count -= 1
	if index == _count:
		return
	_positions[index] = _positions[_count]
	_velocities[index] = _velocities[_count]
	_ages[index] = _ages[_count]
	_lifetimes[index] = _lifetimes[_count]
	_start_sizes_sq[index] = _start_sizes_sq[_count]
	_size_growths[index] = _size_growths[_count]
	_densities[index] = _densities[_count]
	_hot_times[index] = _hot_times[_count]
	_flames[index] = _flames[_count]
	_sources[index] = _sources[_count]


# Самый старый клуб — по доле прожитой жизни, а не по секундам: долгоживущий клуб
# в середине пути ценнее короткоживущего, который вот-вот погаснет сам.
func _oldest_puff() -> int:
	var oldest := 0
	var oldest_share := -1.0
	for index in _count:
		var share := _ages[index] / _lifetimes[index]
		if share > oldest_share:
			oldest = index
			oldest_share = share
	return oldest


func _draw_puffs() -> void:
	# Клубы хранятся в глобальных координатах, поэтому рисуются в обход трансформации узла:
	# куда бы ни поставили Smoke в сцене, дым останется там, где его выпустили.
	puffs.draw_set_transform_matrix(puffs.get_global_transform().affine_inverse())
	for index in _count:
		# Клуб, откатанный назад в add_puff, до первого шага может иметь отрицательный возраст.
		var age := maxf(_ages[index], 0.0)
		var size_sq := _start_sizes_sq[index] + _size_growths[index] * age
		var size := sqrt(size_sq)
		# Масса клуба не меняется, пока он расплывается: клуб вдвое больше по размеру
		# занимает вчетверо большую площадь и во столько же раз бледнее.
		var amount := _densities[index] * _start_sizes_sq[index] / size_sq
		amount *= 1.0 - smoothstep(FADE_START, 1.0, age / _lifetimes[index])
		var hot := amount if age < _hot_times[index] else 0.0
		# Цвет здесь — не цвет, а данные для smoke_puff.gdshader: плотность, горячая
		# плотность и плотность дыма торпеды.
		var data := Color(amount, hot, amount * _flames[index], 1.0)
		var half := Vector2(size, size)
		puffs.draw_rect(Rect2(_positions[index] - half, half * 2.0), data)


func _update_canvas_size() -> void:
	smoke_material.set_shader_parameter(CANVAS_SIZE_PARAM, get_viewport().get_visible_rect().size)
