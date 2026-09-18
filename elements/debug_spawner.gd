extends Node
class_name DebugSpawner

## Отладочный спавнер врагов: клавиши 1, 2, 3… ставят по одному врагу того типа, что лежит
## в соответствующей ячейке enemy_scenes. Узел-компонент: кладётся в сцену уровня, список
## типов заполняется в инспекторе, и порядок в списке и есть раскладка клавиш.
##
## Клавиши читаются сырыми кодами, а не действиями Input Map, намеренно: это отладочный
## инструмент, и новый тип врага должен добавляться одной ячейкой массива, а не ещё одной
## записью в настройках проекта. Цена — переназначить клавиши без правки кода нельзя.
##
## Перед сборкой игры узел выключается флагом enabled или удаляется из сцены целиком.

## Сцены врагов по клавишам: первая ячейка — клавиша 1, вторая — 2, и так до 9. Клавиши
## за пределами списка ничего не делают.
@export var enemy_scenes: Array[PackedScene]
## Выключатель на время обычной игры: с false клавиши не спавнят ничего.
@export var enabled := true
## На сколько пикселей выше верхнего края экрана появляется враг. Больше — дольше влетает
## в кадр, зато точно не возникает у игрока на виду.
@export var spawn_height := 60.0
## Отступ от левого и правого краёв экрана, в котором враг не появляется, пикселей.
## Не даёт ему выйти из-за верхнего края вплотную к стене.
@export var side_margin := 90.0

# Цифровой ряд: номер типа — это смещение кода клавиши от KEY_1. KEY_0 лежит перед KEY_1,
# поэтому даёт -1 и отсекается вместе с остальным, что не попало в диапазон.
const FIRST_KEY := KEY_1
const LAST_KEY := KEY_9


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var key := event as InputEventKey
	# echo — автоповтор зажатой клавиши: одно нажатие должно давать ровно одного врага.
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode < FIRST_KEY or key.keycode > LAST_KEY:
		return
	var index := key.keycode - FIRST_KEY
	if index >= enemy_scenes.size():
		return
	_spawn(enemy_scenes[index])


func _spawn(scene: PackedScene) -> void:
	var enemy: Enemy = scene.instantiate()
	var width := get_viewport().get_visible_rect().size.x
	# Позиция назначается до добавления в дерево: _ready врага запоминает точку, где тот
	# стоит, как свою первую цель, и после add_child он бы одним кадром числился стоящим
	# в начале координат — туда же смотрели бы соседи, разбирающие чужие цели.
	enemy.position = Vector2(randf_range(side_margin, width - side_margin), -spawn_height)
	get_tree().current_scene.add_child(enemy)
