extends Node2D
class_name HealthBar

## Бар здоровья из лампочек: одна лампочка — одна единица здоровья. Первая слева
## красная, остальные зелёные. Здоровье уходит справа налево, так что красная гаснет
## последней, а пока она осталась одна, тревожно мигает.
##
## Бар собирается как шкала нырка: кусок Start, копии куска Middle и кусок End встык.
## Внутри каждого куска лежит дочерний спрайт Lamp — его позиция в сцене задаёт место
## лампочки в куске, а картинку код подставляет сам из четырёх текстур ниже. Middle
## копируется вместе со своей лампочкой. Лампочек ровно max_health корабля: по одной
## в Start и End и max_health − 2 в серединах.

## Стартовая волна закончилась: все лампочки загорелись или волну отменил урон.
signal intro_finished

@export_group("Lamps")
## Горящая красная лампочка. Красная всегда первая слева — последняя единица здоровья.
@export var red_on: Texture2D
## Погасшая красная лампочка: здоровья не осталось совсем.
@export var red_off: Texture2D
## Горящая зелёная лампочка — целая единица здоровья.
@export var green_on: Texture2D
## Погасшая зелёная лампочка — потерянная единица здоровья.
@export var green_off: Texture2D

@export_group("Intro")
## Пауза между загоранием соседних лампочек при старте, секунд. Больше — волна медленнее.
@export var intro_interval := 0.08

@export_group("Damage")
## Сколько раз лампочка мигает при уроне, прежде чем погаснуть окончательно.
@export_range(1, 10, 1) var damage_blinks := 3
## Сколько длится одна фаза мигания при уроне (лампочка погашена или горит), секунд.
## Меньше — мигание чаще и заканчивается быстрее.
@export var damage_blink_interval := 0.06

@export_group("Low Health")
## При каком здоровье и ниже красная лампочка мигает без остановки. 1 — только когда
## осталась она одна.
@export var low_health := 1
## Сколько длится одна фаза тревожного мигания, секунд. Больше — мигание медленнее
## и спокойнее, меньше — нервнее.
@export var low_health_blink_interval := 0.25

@onready var start_piece: Sprite2D = $Start
@onready var middle_piece: Sprite2D = $Middle
@onready var end_piece: Sprite2D = $End

## Закончена ли стартовая волна. Урон до волны или посреди неё тоже её заканчивает:
## бар сразу показывает настоящее здоровье, и волна больше не запускается.
var intro_done := false

var _player: Node
# Лампочки слева направо; нулевая — красная.
var _lamps: Array[Sprite2D] = []
# Горит ли лампочка по смыслу. Картинка может временно расходиться с этим, пока лампочка
# мигает, поэтому смысл хранится отдельно.
var _lit: Array[bool] = []
# Текущее мигание каждой лампочки: при уроне или тревожное у красной.
var _blink_tweens: Array[Tween] = []
var _health := 0
var _alarm := false
var _intro_tween: Tween


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_player.health_changed.connect(_on_player_health_changed)
	# Корабль стоит в дереве выше и отправляет стартовый сигнал ещё до _ready бара,
	# поэтому начальное здоровье забирается напрямую.
	_build(_player.max_health)
	_health = _player.health
	# Пока дашборд не запустил системы, все лампочки тёмные.
	for i in _lamps.size():
		_set_lamp(i, false)


func _on_player_health_changed(health: int, _max_health: int) -> void:
	# Стартовая волна — только украшение. Урон до неё или посреди неё отменяет волну, и бар
	# сразу показывает настоящее здоровье: ещё не загоревшиеся лампочки загораются мгновенно.
	if _intro_tween != null and _intro_tween.is_running():
		_intro_tween.kill()
	_health = health
	_apply_health()
	# Завершение идёт после _apply_health, чтобы тревога красной включалась по уже
	# горящей лампочке.
	_finish_intro()


## Зажигает лампочки волной слева направо и по окончании шлёт intro_finished.
## Если волну уже отменил урон, ничего не делает.
func play_intro() -> void:
	if intro_done:
		return
	_intro_tween = create_tween()
	for i in _health:
		_intro_tween.tween_callback(_light_up.bind(i))
		if i < _health - 1:
			_intro_tween.tween_interval(intro_interval)
	_intro_tween.tween_callback(_finish_intro)


func _finish_intro() -> void:
	if intro_done:
		return
	intro_done = true
	_update_alarm()
	intro_finished.emit()


func _apply_health() -> void:
	for i in _lamps.size():
		var lit := i < _health
		if lit == _lit[i]:
			continue
		_lit[i] = lit
		_stop_blink(i)
		if lit:
			# Анимации лечения нет: лампочка просто загорается.
			_set_lamp(i, true)
		else:
			_blink_out(i)
	_update_alarm()


func _light_up(index: int) -> void:
	_lit[index] = true
	_set_lamp(index, true)


# Лампочка мигает damage_blinks раз и гаснет. Начинает с погасшей картинки, чтобы
# урон был виден в тот же кадр.
func _blink_out(index: int) -> void:
	var tween := _lamps[index].create_tween()
	for n in damage_blinks:
		tween.tween_callback(_set_lamp.bind(index, false))
		tween.tween_interval(damage_blink_interval)
		tween.tween_callback(_set_lamp.bind(index, true))
		tween.tween_interval(damage_blink_interval)
	tween.tween_callback(_set_lamp.bind(index, false))
	_blink_tweens[index] = tween


# Включает или выключает тревожное мигание красной лампочки по текущему здоровью.
func _update_alarm() -> void:
	var alarm := _health > 0 and _health <= low_health
	if alarm == _alarm:
		return
	_alarm = alarm
	if alarm:
		_stop_blink(0)
		# set_loops() без аргумента повторяет tween бесконечно, пока его не убьют.
		var tween := _lamps[0].create_tween().set_loops()
		tween.tween_callback(_set_lamp.bind(0, false))
		tween.tween_interval(low_health_blink_interval)
		tween.tween_callback(_set_lamp.bind(0, true))
		tween.tween_interval(low_health_blink_interval)
		_blink_tweens[0] = tween
	elif _lit[0]:
		# Здоровье поднялось выше порога. Если же красная погасла, её тревогу уже сменило
		# мигание при уроне в _apply_health, и трогать его нельзя.
		_stop_blink(0)
		_set_lamp(0, true)


func _stop_blink(index: int) -> void:
	var tween := _blink_tweens[index]
	if tween != null and tween.is_running():
		tween.kill()


func _set_lamp(index: int, on: bool) -> void:
	if index == 0:
		_lamps[index].texture = red_on if on else red_off
	else:
		_lamps[index].texture = green_on if on else green_off


# Расставляет куски встык слева направо и собирает лампочки по порядку. Первая середина —
# сам узел Middle из сцены, остальные — его копии вместе с лампочкой внутри.
func _build(lamp_count: int) -> void:
	start_piece.position = Vector2.ZERO
	_lamps.append(start_piece.get_node(^"Lamp"))
	var x := start_piece.region_rect.size.x

	var middle_count := maxi(lamp_count - 2, 0)
	for i in middle_count:
		var piece := middle_piece
		if i > 0:
			piece = middle_piece.duplicate()
			add_child(piece)
		piece.position = Vector2(x, 0.0)
		x += middle_piece.region_rect.size.x
		_lamps.append(piece.get_node(^"Lamp"))
	middle_piece.visible = middle_count > 0

	# При одной единице здоровья весь бар — это кусок Start с красной лампочкой.
	end_piece.position = Vector2(x, 0.0)
	end_piece.visible = lamp_count > 1
	if lamp_count > 1:
		_lamps.append(end_piece.get_node(^"Lamp"))

	_lit.resize(_lamps.size())
	_blink_tweens.resize(_lamps.size())
