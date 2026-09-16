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

var _state_timer := 0.0
# Сдвиг цели от игрока по горизонтали: 0 — корабль ведёт себя ровно над ним.
var _drift_offset := 0.0
var _drifting := false


func _ready() -> void:
	super()
	_start_track()
	# Первый отрезок укорочен на случайную долю: иначе бомбардировщики, поставленные
	# в сцену вместе, переключали бы состояния одним кадром и ходили бы синхронно.
	_state_timer *= randf()


func _update_behaviour(delta: float) -> void:
	_state_timer -= delta
	if _state_timer <= 0.0:
		_switch_state()
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
