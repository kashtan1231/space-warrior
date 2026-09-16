extends Node2D
class_name RocketPanel

## Ракетная панель: подложка, ряд переключателей по числу заряженных шахт, крутилка
## выбора цели и кнопка пуска. Сама ничего не решает и время боя не отсчитывает —
## только показывает то, о чём корабль сообщает сигналами.
##
## Один переключатель — одна шахта. Синяя лампочка горит, пока ракета в боезапасе;
## рычаг поднят у той ракеты, которая уйдёт следующим нажатием.
##
## Переключатели строит код: их столько, сколько у корабля заряжено шахт, и прокачка
## вместимости добавляет новые прямо в бою. Узел Switch в сцене — образец и место
## первого переключателя: сам он спрятан, а в ряд идут его копии, как куски бара
## здоровья в health_bar.gd.

@export_group("Switches")
## Шаг ряда: расстояние между левыми краями соседних переключателей, в пикселях
## исходного рисунка. Включает и сам переключатель, и просвет за ним. Ряд начинается
## от узла Switch и растёт вправо, поэтому две ракеты стоят слева, а прокачка
## достраивает недостающие в свободную часть панели.
@export var switch_step := 16
## Таблички под переключателями слева направо, по одной на шахту. Порядок совпадает
## с порядком шахт в rocket_launchers корабля, поэтому надписи не разъезжаются при
## прокачке: уже стоящие переключатели остаются при своих, а новые получают следующие.
## Надписей должно быть столько же, сколько шахт на крыльях, — иначе последние
## переключатели останутся без таблички, и движок скажет об этом ошибкой.
@export var captions: Array[Texture2D]

@export_group("Launch")
## Кнопка пуска в обычном положении.
@export var button_released: Texture2D
## Утопленная кнопка пуска: показывается в кадр пуска ракеты.
@export var button_pressed: Texture2D
## Сколько секунд кнопка держится утопленной. Больше — нажатие заметнее, но панель
## дольше отстаёт от того, что уже происходит на экране.
@export var button_hold_time := 0.18
## Пауза между подъёмом рычага следующей ракеты и опусканием рычага отстрелянной,
## секунд. Сначала система показывает, что готова, и только потом списывает ушедшую;
## 0 — оба рычага щёлкают одновременно.
@export var lever_drop_delay := 0.12

@export_group("Knob")
## Кадры крутилки по кругу. Каждое переключение цели проворачивает её на один кадр:
## «следующая» — вперёд по списку, «предыдущая» — назад, с конца на начало.
@export var knob_frames: Array[Texture2D]

@export_group("Intro")
## Через сколько секунд после старта сцены панель оживает и начинает зажигать лампочки.
## Подбирается на глаз под запуск систем левого дашборда: панели друг о друге не знают.
@export var intro_delay := 2.0
## Пауза между загоранием соседних лампочек при старте, секунд. Больше — волна медленнее.
@export var intro_interval := 0.12

@onready var switch_template: RocketSwitch = $Switch
@onready var knob: Sprite2D = $Knob
@onready var button: Sprite2D = $Button

var _player: Node
# Переключатели слева направо, по одному на заряженную шахту.
var _switches: Array[RocketSwitch] = []
# Боезапас по шахтам: true — ракета на месте.
var _states: Array[bool] = []
# Горит ли лампочка по смыслу. Пока идёт стартовая волна, картинка отстаёт от боезапаса,
# поэтому нарисованное состояние хранится отдельно.
var _lit: Array[bool] = []
var _aiming := false
# Номер поднятого рычага: эта ракета уйдёт следующей. -1 — все рычаги опущены.
var _armed := -1
var _knob_frame := 0
# Волна уже игралась или её отменил пуск — второй раз она не запускается.
var _intro_done := false
var _intro_tween: Tween


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_player.rockets_changed.connect(_on_player_rockets_changed)
	_player.rocket_launched.connect(_on_player_rocket_launched)
	_player.aiming_changed.connect(_on_player_aiming_changed)
	_player.target_cycled.connect(_on_player_target_cycled)
	# Корабль стоит в дереве выше и свой стартовый сигнал шлёт ещё до _ready панели,
	# поэтому начальный боезапас забирается напрямую.
	switch_template.hide()
	_states = _player.get_rocket_states()
	_build(_states.size())
	knob.texture = knob_frames[_knob_frame]
	button.texture = button_released
	# Пока панель не запустилась, лампочки тёмные: их зажжёт волна.
	_run_intro()


func _on_player_rockets_changed(loaded: Array[bool]) -> void:
	# Волна — только украшение. Пуск или прокачка до её конца отменяет её, и панель
	# сразу показывает настоящий боезапас.
	if _intro_tween != null and _intro_tween.is_running():
		_intro_tween.kill()
	_intro_done = true
	_states = loaded
	if _states.size() != _switches.size():
		_build(_states.size())
	_apply_states()


# Пуск: кнопка утапливается, лампочка отстрелянной ракеты гаснет сама по rockets_changed
# в этот же кадр. Рычаг пока остаётся поднятым — им займётся отжатие кнопки.
#
# Номер шахты уезжает в отложенный вызов вместе с ним: при частой стрельбе следующий пуск
# успевает случиться раньше, чем отожмётся кнопка от предыдущего, и к тому моменту _armed
# указывает уже на другую шахту.
func _on_player_rocket_launched(index: int) -> void:
	button.texture = button_pressed
	var tween := create_tween()
	tween.tween_interval(button_hold_time)
	tween.tween_callback(_release_button.bind(index))


func _on_player_aiming_changed(active: bool) -> void:
	_aiming = active
	if active:
		_arm_next()
	else:
		_disarm()


func _on_player_target_cycled(step: int) -> void:
	_knob_frame = posmod(_knob_frame + step, knob_frames.size())
	knob.texture = knob_frames[_knob_frame]


# Кнопка отжимается, следом поднимается рычаг следующей ракеты, и только потом опускается
# рычаг отстрелянной. fired — шахта того пуска, который эту кнопку и утопил.
func _release_button(fired: int) -> void:
	button.texture = button_released
	# Взведённой отстрелянная шахта остаётся только у самого свежего пуска. У предыдущих
	# рычаг уже перевели на следующую ракету — её трогать нельзя, иначе она останется
	# с опущенным рычагом, хотя уйдёт следующей.
	if _armed == fired:
		_armed = -1
		if _aiming:
			_arm_next()
	# Пока кнопка была утоплена, режим прицеливания мог выключиться — тогда рычаг уже
	# опущен, и опускать нечего. Лишний set_on(false) безвреден, но тайминг заводится зря.
	var switch := _switches[fired]
	var tween := create_tween()
	tween.tween_interval(lever_drop_delay)
	tween.tween_callback(switch.set_on.bind(false))


# Поднимает рычаг первой неотстрелянной шахты. Если ракет не осталось, поднимать нечего:
# корабль в этот момент и сам выходит из режима прицеливания.
func _arm_next() -> void:
	for index in _switches.size():
		if _states[index]:
			_set_armed(index)
			return
	_set_armed(-1)


func _set_armed(index: int) -> void:
	if _armed == index:
		return
	if _armed >= 0:
		_switches[_armed].set_on(false)
	_armed = index
	if _armed >= 0:
		_switches[_armed].set_on(true)


func _disarm() -> void:
	_set_armed(-1)


# Зажигает лампочки волной слева направо. Отстрелянные пропускает: волна показывает
# боезапас, а не пересчитывает шахты.
func _run_intro() -> void:
	# Функция с await внутри — корутина: вызов не ждёт её конца, она сама продолжится,
	# когда придёт сигнал.
	await create_tween().tween_interval(intro_delay).finished
	if _intro_done:
		return
	_intro_done = true
	_intro_tween = create_tween()
	for index in _switches.size():
		if not _states[index]:
			continue
		_intro_tween.tween_callback(_set_lamp.bind(index, true))
		_intro_tween.tween_interval(intro_interval)


func _apply_states() -> void:
	for index in _switches.size():
		_set_lamp(index, _states[index])


# Лампочка трогается только на изменении: иначе каждый пуск заново запускал бы мерцание
# у всех оставшихся ракет.
func _set_lamp(index: int, on: bool) -> void:
	if _lit[index] == on:
		return
	_lit[index] = on
	_switches[index].set_lamp(on)


# Выстраивает ряд из count переключателей слева направо от позиции образца. Лишние
# удаляются, недостающие добавляются его копиями — вместе с лампочкой, рычагом
# и табличкой внутри.
func _build(count: int) -> void:
	while _switches.size() < count:
		var switch: RocketSwitch = switch_template.duplicate()
		add_child(switch)
		switch.show()
		# Новый переключатель приходит с тёмной лампочкой: если шахту открыла прокачка,
		# лампочка загорится следом, в _apply_states, и мигнёт при загорании.
		switch.set_lamp(false)
		_switches.append(switch)
	while _switches.size() > count:
		_switches.pop_back().queue_free()
	_lit.resize(count)

	# Позиция образца — место первого переключателя, дальше ряд идёт вправо с шагом.
	for index in count:
		_switches[index].position = switch_template.position + Vector2(index * switch_step, 0.0)
		_switches[index].set_caption(captions[index])
