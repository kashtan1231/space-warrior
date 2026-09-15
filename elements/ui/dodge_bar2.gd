extends Node2D

## Шкала перезарядки нырка: рамка из таблеток, внутри неё заливка. Сама ничего
## не отсчитывает: корабль сообщает долю заряда сигналом dodge_charge_changed, а шкала
## только решает, сколько таблеток залить.
##
## Шкала собирается из трёх слоёв, лежащих друг на друге: Frame — рамка, Fill — заливка,
## Flash — белый силуэт для вспышки. Каждый слой — это куски Start, Middle и End.
## Края берутся из листа как есть, а таблетку Middle код размножает middle_pills раз
## и ставит все куски встык. Ширины кусков читаются из их регионов, поэтому бар
## с другими краями подставляется правкой регионов, без изменений в коде.

## Сколько таблеток между началом и концом шкалы. 0 — только края. Длина шкалы
## собирается один раз при запуске, поэтому менять значение нужно до старта игры.
@export_range(0, 32, 1) var middle_pills := 3
## Сколько таблеток нарисовано в каждом крае. Каждая таблетка — своя ступенька
## заполнения, и край делится на них поровну по ширине. Для края без таблеток,
## например округлого, ставь 1: тогда он заливается целиком за одну ступеньку.
@export_range(1, 8, 1) var cap_pills := 2

@export_group("Intro")
## Через сколько секунд после старта уровня начинает заполняться шкала. 0 — сразу,
## одновременно с волной сердец.
@export var intro_delay := 0.0
## Пауза между загоранием соседних таблеток при стартовом заполнении, секунд.
## Больше — заполнение медленнее. У сердец тот же смысл несёт appear_interval.
@export var intro_interval := 0.08

@export_group("Drain")
## За сколько секунд вся шкала гаснет при нырке, справа налево. Не зависит от числа
## таблеток: длинная шкала гаснет так же быстро, как короткая, просто шаги чаще.
@export var drain_duration := 0.15

@onready var frame_layer: Node2D = $Frame
@onready var fill_layer: Node2D = $Fill
@onready var flash_layer: Node2D = $Flash
@onready var fill_start: Sprite2D = $Fill/Start
@onready var fill_end: Sprite2D = $Fill/End

var _player: Node
var _fill_middle: Array[Sprite2D] = []
var _fill_start_region := Rect2()
var _fill_end_region := Rect2()
var _charge := 1.0
var _flash_tween: Tween
var _intro_tween: Tween
var _drain_tween: Tween
# Сколько таблеток заливки сейчас на экране. Может отставать от заряда, пока идёт
# анимация, поэтому хранится отдельно.
var _shown_pills := 0


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_player.dodge_charge_changed.connect(_on_player_dodge_charge_changed)

	_build_layer(frame_layer)
	_fill_middle = _build_layer(fill_layer)
	_build_layer(flash_layer)
	# Регионы краёв из инспектора — это полностью залитые края. Дальше код меняет
	# только их ширину.
	_fill_start_region = fill_start.region_rect
	_fill_end_region = fill_end.region_rect

	flash_layer.hide()
	# Корабль стартует с полным зарядом и до первого нырка сигнал не шлёт. Но вместо
	# полной шкалы сразу показывается пустая рамка, и заряд набирается анимацией.
	_set_pills(0)
	_play_intro()


func _on_player_dodge_charge_changed(charge: float) -> void:
	# Нырнуть можно и во время стартового заполнения: оно лишь украшение, поэтому
	# обрывается, и дальше шкала показывает настоящий заряд корабля.
	if _intro_tween != null and _intro_tween.is_running():
		_intro_tween.kill()

	var was_full := _charge >= 1.0
	_charge = charge
	# Таблетка загорается, только когда набралась целиком: последняя появляется ровно
	# в момент готовности нырка, одновременно со вспышкой.
	var pills := floori(charge * _total_pills())
	if pills < _shown_pills:
		_drain(pills)
	else:
		# Заряд пошёл вверх раньше, чем шкала догасла (очень короткий нырок), —
		# настоящее состояние важнее анимации.
		if _drain_tween != null and _drain_tween.is_running():
			_drain_tween.kill()
		_set_pills(pills)

	if charge >= 1.0:
		if not was_full:
			_flash()
		return
	# Новый нырок мог начаться, пока ещё горит вспышка, — тогда она гаснет сразу.
	if _flash_tween != null and _flash_tween.is_running():
		_flash_tween.kill()
	flash_layer.hide()


# Таблетки загораются по одной слева направо, как волна сердец. Со вспышкой на последней
# стартовое заполнение выглядит точно так же, как конец перезарядки.
func _play_intro() -> void:
	var total := _total_pills()
	_intro_tween = create_tween()
	_intro_tween.tween_interval(intro_delay)
	for count in range(1, total + 1):
		_intro_tween.tween_callback(_set_pills.bind(count))
		if count < total:
			_intro_tween.tween_interval(intro_interval)
	_intro_tween.tween_callback(_flash)


# Гасит таблетки по одной справа налево до target за drain_duration. Первая гаснет
# в тот же кадр, что и нажатие, чтобы шкала отзывалась на нырок без задержки.
func _drain(target: int) -> void:
	# Во время нырка и в начале перезарядки заряд приходит каждый кадр и всё время
	# меньше видимого. Уже идущее угасание не перезапускается, иначе оно не кончилось бы.
	if _drain_tween != null and _drain_tween.is_running():
		return
	var steps := _shown_pills - target
	var step_time := drain_duration / steps
	_drain_tween = create_tween()
	for count in range(_shown_pills - 1, target - 1, -1):
		_drain_tween.tween_callback(_set_pills.bind(count))
		if count > target:
			_drain_tween.tween_interval(step_time)


func _total_pills() -> int:
	return cap_pills * 2 + middle_pills


# Расставляет Start, таблетки середины и End встык слева направо. Первая таблетка
# середины — сам узел Middle из сцены, остальные — его копии. Возвращает все таблетки
# середины по порядку.
func _build_layer(layer: Node2D) -> Array[Sprite2D]:
	var start: Sprite2D = layer.get_node(^"Start")
	var middle: Sprite2D = layer.get_node(^"Middle")
	var end: Sprite2D = layer.get_node(^"End")

	start.position = Vector2.ZERO
	var x := start.region_rect.size.x
	var pills: Array[Sprite2D] = []
	for i in middle_pills:
		var pill := middle
		if i > 0:
			pill = middle.duplicate()
			layer.add_child(pill)
		pill.position = Vector2(x, 0.0)
		x += middle.region_rect.size.x
		pills.append(pill)
	middle.visible = middle_pills > 0
	end.position = Vector2(x, 0.0)
	return pills


func _set_pills(count: int) -> void:
	_shown_pills = count
	_set_cap_fill(fill_start, _fill_start_region, count)
	for i in _fill_middle.size():
		_fill_middle[i].visible = count > cap_pills + i
	_set_cap_fill(fill_end, _fill_end_region, count - cap_pills - middle_pills)


# Обрезает край справа так, чтобы в нём было видно filled таблеток из cap_pills.
func _set_cap_fill(cap: Sprite2D, full_region: Rect2, filled: int) -> void:
	filled = clampi(filled, 0, cap_pills)
	# Регион нулевой ширины Sprite2D рисовать не должен, но надёжнее просто спрятать спрайт.
	cap.visible = filled > 0
	if filled == 0:
		return
	var region := full_region
	region.size.x = roundi(full_region.size.x * filled / float(cap_pills))
	cap.region_rect = region


func _flash() -> void:
	flash_layer.show()
	_flash_tween = create_tween()
	# Длительность берётся у корабля, чтобы шкала и корпус гасли одним кадром.
	_flash_tween.tween_interval(_player.dodge_ready_flash_duration)
	_flash_tween.tween_callback(flash_layer.hide)
