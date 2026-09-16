extends Node2D
class_name RocketSwitch

## Переключатель одной ракетной шахты на ракетной панели: рычаг и синяя лампочка над ним.
## Сам ничего не решает — что показывать, говорит панель.
##
## Рычаг и лампочка независимы, и в этом всё отличие от Toggle на левом дашборде, где
## лампочка ходит за рычагом. Здесь поднятый рычаг значит «эта ракета уйдёт следующей»,
## а горящая лампочка — «ракета ещё в боезапасе»; гаснут они в разные моменты.
##
## Узлы: Lever — рычаг, Lamp — лампочка, Caption — табличка с надписью. Надпись у каждой
## шахты своя, но какой он по счёту в ряду, переключатель не знает — табличку ему выдаёт
## панель при сборке.

@export_group("Lever")
## Рычаг во взведённом положении — поднят вверх. Так отмечена ракета, которая уйдёт
## следующим нажатием.
@export var lever_on: Texture2D
## Рычаг в спокойном положении — опущен вниз.
@export var lever_off: Texture2D

@export_group("Lamp")
## Горящая лампочка: ракета на месте, в боезапасе.
@export var lamp_on: Texture2D
## Погасшая лампочка: шахта пуста или панель ещё не запустилась.
@export var lamp_off: Texture2D

@export_group("Flicker")
## Сколько раз лампочка гаснет и снова вспыхивает сразу после загорания, прежде чем
## гореть ровно. 0 — загорается ровно в кадр включения.
@export_range(0, 10, 1) var flicker_count := 2
## Самая короткая фаза мерцания, секунд.
@export var flicker_min := 0.03
## Самая длинная фаза мерцания, секунд. Каждая фаза берёт случайную длительность между
## flicker_min и flicker_max — от этого мерцание неровное, как у старой лампы.
@export var flicker_max := 0.12

@onready var lever: Sprite2D = $Lever
@onready var lamp: Sprite2D = $Lamp
@onready var caption: Sprite2D = $Caption

var _flicker_tween: Tween


func _ready() -> void:
	# На старте сцены шахта не взведена, а лампочку зажжёт панель, когда запустится.
	set_on(false)
	set_lamp(false)


## Поднимает или опускает рычаг, не трогая лампочку.
func set_on(on: bool) -> void:
	lever.texture = lever_on if on else lever_off


## Ставит табличку с надписью — ту, что панель припасла для этой шахты.
func set_caption(texture: Texture2D) -> void:
	caption.texture = texture


## Зажигает или гасит лампочку, не трогая рычаг. Включение даёт мерцание, выключение
## гасит сразу и обрывает мерцание, если оно шло.
func set_lamp(on: bool) -> void:
	if _flicker_tween != null and _flicker_tween.is_running():
		_flicker_tween.kill()
	_set_lamp(on)
	if not on or flicker_count == 0:
		return
	_flicker_tween = create_tween()
	for i in flicker_count:
		_flicker_tween.tween_interval(randf_range(flicker_min, flicker_max))
		_flicker_tween.tween_callback(_set_lamp.bind(false))
		_flicker_tween.tween_interval(randf_range(flicker_min, flicker_max))
		_flicker_tween.tween_callback(_set_lamp.bind(true))


func _set_lamp(on: bool) -> void:
	lamp.texture = lamp_on if on else lamp_off
