extends Enemy
class_name TorpedoBomber

## Тяжёлый носитель торпед. Держится в своей полосе выше остальных врагов и медленно
## подводит себя по горизонтали к игроку, время от времени отходя в сторону, чтобы
## не висеть над ним неподвижной мишенью. От пуль и ракет не уворачивается совсем:
## по нему легко попасть, но и ковырять его дольше, чем скаута, — в этом весь контраст.
##
## Высота выбирается заново на каждой смене состояния, в пределах band_top и band_bottom
## из базового класса. Держать полосу стоит выше скаутской, иначе корабли перемешаются.

@export_group("Hover")
## Сколько секунд корабль висит над игроком, прежде чем отойти в сторону. Больше —
## дольше стоит под прицелом и дольше держит игрока под собой.
@export var track_time := 3.0
## Сколько секунд длится отход в сторону. Больше — корабль надолго уступает игроку
## место под собой; меньше — почти всё время висит над ним.
@export var drift_time := 1.5
## На сколько пикселей от игрока корабль отходит в сторону. Сторона выбирается случайно,
## а расстояние — от половины этого значения до него целиком. Меньше ширины экрана,
## иначе отход всегда упирается в край и превращается в полёт к стене.
@export var drift_distance := 260.0
## Разброс длительностей обоих состояний, доля от заданной. 0 — корабль переключается
## строго по таймеру, и пара бомбардировщиков ходит строем; 0.5 — время гуляет
## в полтора раза в обе стороны.
@export_range(0.0, 1.0, 0.05) var time_jitter := 0.3

@export_group("Torpedoes")
## Отсеки с торпедами в порядке пуска: первый заряженный из списка уходит следующим.
## Чередование бортов разряжает корабль симметрично, поэтому порядок лучше задавать
## накрест — левый, правый, левый, — а не подряд вдоль одного крыла.
@export var torpedo_bays: Array[TorpedoBay]
## Сколько отсеков заряжено на старте. Меньше, чем отсеков, — лишние горят красным
## с самого начала. Перезарядки нет: отстрелянные торпеды не возвращаются, и полный
## боезапас — это всё, что корабль принесёт в бой.
@export_range(0, 6, 1) var torpedo_count := 6
## Нижняя граница случайной паузы между пусками, секунд.
@export var launch_cooldown_min := 1.0
## Верхняя граница случайной паузы между пусками, секунд. Пауза бросается заново после
## каждого пуска, поэтому торпеды не идут ровной очередью.
@export var launch_cooldown_max := 5.0
## Ширина полосы вдоль линии пуска, в которую не должен попадать союзник, пикселей.
## Торпеда бьёт своих так же, как игрока, поэтому занятая полоса откладывает пуск.
## Больше — корабль осторожничает и стреляет реже, меньше — чаще накрывает своих.
@export var clear_lane_width := 70.0

var _state_timer := 0.0
# Сдвиг цели от игрока по горизонтали: 0 — корабль ведёт себя ровно над ним.
var _drift_offset := 0.0
var _drifting := false
var _launch_cooldown := 0.0


func _ready() -> void:
	super()
	_start_track()
	# Первый отрезок укорочен на случайную долю: иначе бомбардировщики, поставленные
	# в сцену вместе, переключали бы состояния одним кадром и ходили бы синхронно.
	_state_timer *= randf()
	for index in torpedo_bays.size():
		torpedo_bays[index].set_loaded(index < torpedo_count)
	_launch_cooldown = randf_range(launch_cooldown_min, launch_cooldown_max)


func die() -> void:
	# Отсеки не входят в спрайт корпуса и сами бы не пропали: без этого торпеды
	# и лампочки остались бы висеть поверх взрыва.
	for bay in torpedo_bays:
		bay.hide()
	super()


func _update_behaviour(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_switch_state()

	_launch_cooldown -= delta
	if _can_launch():
		_launch_torpedo()

	# Игрок мог погибнуть — тогда корабль дотягивает до последней цели и висит там.
	if is_instance_valid(_player):
		_target.x = _aim_x()


func _switch_state() -> void:
	if _drifting:
		_start_track()
	else:
		_start_drift()


func _start_track() -> void:
	_drifting = false
	_drift_offset = 0.0
	_state_timer = _jittered(track_time)
	_pick_height()


func _start_drift() -> void:
	_drifting = true
	# Расстояние берётся не короче половины заданного: отход на десяток пикселей
	# читался бы не как манёвр, а как дрожание корабля на месте.
	var side := 1.0 if randf() < 0.5 else -1.0
	_drift_offset = side * drift_distance * randf_range(0.5, 1.0)
	_state_timer = _jittered(drift_time)
	_pick_height()


func _pick_height() -> void:
	_target.y = randf_range(band_top, band_bottom)


# Горизонтальная цель: над игроком или в стороне от него на отходе. Отступ от краёв
# режет её, чтобы корабль, ведущий игрока к стене, не заезжал под неё сам.
func _aim_x() -> float:
	var width := get_viewport_rect().size.x
	return clampf(_player.global_position.x + _drift_offset, side_margin, width - side_margin)


func _jittered(seconds: float) -> float:
	return seconds * randf_range(1.0 - time_jitter, 1.0 + time_jitter)


# Пуск идёт, когда пауза истекла, заряженный отсек ещё есть и путь к игроку свободен
# от союзников. Ждать корабль готов сколько угодно: занятая полоса просто откладывает
# пуск до ближайшего кадра, в котором она очистится, и отсчёт паузы заново не заводит.
func _can_launch() -> bool:
	if _launch_cooldown > 0.0 or not is_instance_valid(_player):
		return false
	return _next_bay() != null and _is_lane_clear()


func _launch_torpedo() -> void:
	_next_bay().launch(_player)
	_launch_cooldown = randf_range(launch_cooldown_min, launch_cooldown_max)


# Отсек, из которого уйдёт следующая торпеда, или null, если боезапас кончился.
func _next_bay() -> TorpedoBay:
	for bay in torpedo_bays:
		if bay.is_loaded():
			return bay
	return null


# Свободна ли полоса до игрока. Торпеда наводится и идёт к нему примерно по прямой,
# поэтому союзник считается помехой, когда он ближе половины ширины полосы к отрезку
# от корабля до игрока. Соседи выше и позади в отрезок не попадают и пуску не мешают.
func _is_lane_clear() -> bool:
	for node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var other := node as Node2D
		if other == self:
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(
			other.global_position, global_position, _player.global_position)
		if other.global_position.distance_to(nearest) <= clear_lane_width * 0.5:
			return false
	return true
