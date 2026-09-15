extends Node2D
class_name Toggle

## Переключатель с сигнальной лампочкой и надписью. Сам ничего не решает и время не
## отсчитывает: когда щёлкнуть, говорит дашборд через set_on().
##
## Узлы: Lever — рычаг, Lamp — лампочка, Caption — надпись. Все картинки задаются
## текстурами ниже, поэтому одна сцена служит любым переключателем: цвет лампочки
## и надпись выбираются на инстансе, без правки детей внутри него.

## Лампочка отмерцала и горит ровно. Шлётся и при выключении посреди мерцания:
## мерцание в любом случае закончилось.
signal flicker_finished

## Табличка с надписью под переключателем.
@export var caption: Texture2D

@export_group("Lever")
## Рычаг во включённом положении — поднят вверх.
@export var lever_on: Texture2D
## Рычаг в выключенном положении — опущен вниз.
@export var lever_off: Texture2D

@export_group("Lamp")
## Горящая лампочка над переключателем.
@export var lamp_on: Texture2D
## Погасшая лампочка над переключателем.
@export var lamp_off: Texture2D

@export_group("Flicker")
## Сколько раз лампочка гаснет и снова вспыхивает сразу после включения, прежде чем
## гореть ровно. 0 — загорается ровно в кадр щелчка.
@export_range(0, 10, 1) var flicker_count := 2
## Самая короткая фаза мерцания, секунд.
@export var flicker_min := 0.03
## Самая длинная фаза мерцания, секунд. Каждая фаза берёт случайную длительность между
## flicker_min и flicker_max — от этого мерцание неровное, как у старой лампы. Чем шире
## разброс, тем «больнее» лампа.
@export var flicker_max := 0.12

@onready var lever: Sprite2D = $Lever
@onready var lamp: Sprite2D = $Lamp
@onready var caption_sprite: Sprite2D = $Caption

var _flicker_tween: Tween


func _ready() -> void:
	caption_sprite.texture = caption
	# На старте сцены переключатель выключен.
	set_on(false)


## Щёлкает рычагом. Включение зажигает лампочку в тот же кадр и затем даёт ей
## померцать; выключение гасит её сразу.
func set_on(on: bool) -> void:
	if is_flickering():
		_flicker_tween.kill()
		flicker_finished.emit()
	lever.texture = lever_on if on else lever_off
	_set_lamp(on)
	if not on or flicker_count == 0:
		return
	_flicker_tween = create_tween()
	for i in flicker_count:
		_flicker_tween.tween_interval(randf_range(flicker_min, flicker_max))
		_flicker_tween.tween_callback(_set_lamp.bind(false))
		_flicker_tween.tween_interval(randf_range(flicker_min, flicker_max))
		_flicker_tween.tween_callback(_set_lamp.bind(true))
	_flicker_tween.tween_callback(flicker_finished.emit)


## Мерцает ли лампочка прямо сейчас. Без мерцания flicker_finished уже не придёт,
## поэтому ждать его стоит, только если здесь true.
func is_flickering() -> bool:
	return _flicker_tween != null and _flicker_tween.is_running()


func _set_lamp(on: bool) -> void:
	lamp.texture = lamp_on if on else lamp_off
