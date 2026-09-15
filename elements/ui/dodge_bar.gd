extends Node2D
class_name DodgeBar

## Шкала перезарядки нырка с плавной заливкой. Сама ничего не отсчитывает: корабль
## сообщает долю заряда сигналом dodge_charge_changed, а шкала только показывает её.
##
## Слоёв два: Frame — пустой бар целиком, Fill — полоса заливки поверх него, только
## внутренняя часть с уже нарисованными тёмными перепонками. Код меняет ширину региона
## Fill, открывая полосу слева направо, поэтому перепонки остаются тёмными сами собой.
## Ширина полной заливки читается из региона в инспекторе.

## На сколько пикселей исходного рисунка сдвигается край заливки за раз, при заполнении
## и при стекании. Скорость шкалы от шага не меняется: чем больше шаг, тем реже и
## крупнее прыжки. 1 — самое плавное движение.
@export_range(1, 16, 1) var fill_step := 1

@export_group("Intro")
## За сколько секунд шкала заполняется целиком, когда дашборд запускает системы.
## 0 — появляется полной.
@export var intro_duration := 0.6

@export_group("Drain")
## За сколько секунд вся шкала стекает при нырке. Частично заполненная стекает
## пропорционально быстрее. 0 — пустеет мгновенно.
@export var drain_duration := 0.15

@export_group("Dodge Blink")
## Какая доля шкалы мигает, пока идёт нырок и шкала уже стекла до нуля. 0.125 — ровно
## половина первой из четырёх секций; чуть больше — край заходит за середину секции.
@export_range(0.0, 1.0, 0.005) var dodge_blink_fill := 0.15
## Сколько длится одна фаза мигания во время нырка (заливка видна или скрыта), секунд.
## Меньше — мигание чаще.
@export var dodge_blink_interval := 0.1

@onready var fill: Sprite2D = $Fill

# Полный регион заливки из инспектора; код меняет только его ширину.
var _full_region := Rect2()
# Заряд, который сейчас нарисован. Отстаёт от настоящего, пока шкала стекает
# или заполняется на старте.
var _shown := 0.0
# Настоящий заряд корабля.
var _charge := 1.0
# Идёт ли стартовое заполнение. Запускает его дашборд через play_intro().
var _intro := false
# Заполнение уже запускалось или его отменил нырок — второй раз оно не играет.
var _intro_done := false
# Сколько секунд шкала мигает во время нырка. Сбрасывается, как только шкала снова
# показывает заряд, чтобы каждое мигание начиналось с видимой заливки.
var _blink_time := 0.0


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	player.dodge_charge_changed.connect(_on_player_dodge_charge_changed)
	_full_region = fill.region_rect
	# Корабль стартует с полным зарядом, но шкала пустая, пока дашборд не запустит системы.
	_set_shown(0.0)


func _process(delta: float) -> void:
	if _intro:
		_set_shown(move_toward(_shown, 1.0, _speed(intro_duration) * delta))
		_intro = _shown < 1.0
	elif _shown > _charge:
		_set_shown(move_toward(_shown, _charge, _speed(drain_duration) * delta))
	elif _charge <= 0.0:
		# Нулевой заряд корабль шлёт только во время нырка: перезарядка начинается
		# со следующего кадра и сразу приносит заряд больше нуля, что и прерывает мигание.
		_blink_during_dodge(delta)


## Плавно заполняет пустую шкалу за intro_duration. Если нырок случился раньше,
## ничего не делает: шкала и так уже показывает настоящий заряд.
func play_intro() -> void:
	if _intro_done:
		return
	_intro_done = true
	_intro = true


func _on_player_dodge_charge_changed(charge: float) -> void:
	# Нырнуть можно и до запуска систем, и во время заполнения: заполнение лишь украшение,
	# поэтому отменяется, и дальше шкала показывает настоящий заряд.
	_intro = false
	_intro_done = true
	_charge = charge
	# Рост заряда показывается в тот же кадр, чтобы шкала заполнилась одновременно
	# со вспышкой корабля. Падение — нет: его плавно догоняет _process.
	if charge >= _shown:
		_set_shown(charge)


func _set_shown(value: float) -> void:
	_shown = value
	_blink_time = 0.0
	_set_fill_width(value, fill_step)


# Мигает заливкой на dodge_blink_fill шкалы. Начинает с видимой фазы, поэтому мигание
# стартует ровно в кадр, когда шкала стекла до нуля.
func _blink_during_dodge(delta: float) -> void:
	var visible_phase := fmod(_blink_time, dodge_blink_interval * 2.0) < dodge_blink_interval
	_blink_time += delta
	# Ширина мигания задана долей явно, поэтому шагом заливки не округляется.
	_set_fill_width(dodge_blink_fill if visible_phase else 0.0, 1)


# Открывает полосу заливки на долю fraction её полной ширины, округляя вниз до кратного
# step пикселей. Округление вниз, а не до ближайшего: последний шаг появляется ровно
# в момент полного заряда, одновременно со вспышкой корабля, а не на кадр раньше.
func _set_fill_width(fraction: float, step: int) -> void:
	var full_width := int(_full_region.size.x)
	var width := floori(full_width * fraction / step) * step
	# Полная шкала рисуется целиком, даже если её ширина не делится на шаг нацело.
	if fraction >= 1.0:
		width = full_width
	var region := _full_region
	region.size.x = width
	fill.region_rect = region
	# Регион нулевой ширины Sprite2D рисовать не должен, но надёжнее просто спрятать спрайт.
	fill.visible = region.size.x > 0.0


# Доля шкалы в секунду для анимации длиной duration секунд. Нулевая длительность —
# мгновенный переход.
func _speed(duration: float) -> float:
	return 1.0 / duration if duration > 0.0 else INF
