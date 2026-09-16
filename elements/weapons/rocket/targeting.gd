extends Node
class_name Targeting

## Летит, когда режим прицеливания включился и цель выбрана. Если врагов не нашлось,
## режим не включается и сигнала нет.
signal activated

## Летит, когда режим выключился: по кнопке, из-за кончившихся ракет или потому, что
## сбивать больше некого.
signal deactivated

## Летит на каждое нажатие «следующая/предыдущая цель»: 1 — вперёд по очереди, -1 — назад.
## Шлётся и когда цель одна и выбор фактически не изменился: нажатие всё равно было.
signal target_cycled(step: int)

## Сцена прицела, который вешается на каждого врага.
@export var reticle_scene: PackedScene
## Пауза между появлением соседних прицелов при входе в режим, секунд. Прицелы идут
## слева направо: больше — волна заметнее, но дольше ждать последнего.
@export var reveal_interval := 0.08

const ENEMY_GROUP := &"enemies"

var _active := false
# Прицелы в порядке появления: при входе в режим — слева направо.
var _reticles: Array[Reticle] = []
var _selected: Reticle
var _reveal_cooldown := 0.0


func _process(delta: float) -> void:
	if not _active:
		return
	_drop_lost_targets()
	_add_new_targets()
	if _reticles.is_empty():
		deactivate()
		return
	_update_reveal(delta)
	if Input.is_action_just_pressed("next_target"):
		_cycle(1)
	elif Input.is_action_just_pressed("prev_target"):
		_cycle(-1)


func is_active() -> bool:
	return _active


## Включает режим: вешает прицелы на всех врагов и выбирает ближайшего к origin_x
## по горизонтали. Если врагов нет, режим не включается.
func activate(origin_x: float) -> void:
	_reveal_cooldown = 0.0
	_add_new_targets()
	# Флаг поднимается только после удачного поиска: иначе неудачный вход в режим
	# отбивал бы deactivated, которому не предшествовал activated.
	if _reticles.is_empty():
		return
	_active = true
	_select(_nearest_by_x(origin_x))
	activated.emit()


func deactivate() -> void:
	if not _active:
		return
	_active = false
	for reticle in _reticles:
		reticle.queue_free()
	_reticles.clear()
	_selected = null
	deactivated.emit()


## Выбранный враг. Вызывать только при включённом режиме: тогда цель есть всегда.
func get_target() -> Node2D:
	return _selected.target


func _add_new_targets() -> void:
	var fresh: Array[Node2D] = []
	for node in get_tree().get_nodes_in_group(ENEMY_GROUP):
		var enemy := node as Node2D
		if not _is_tracked(enemy):
			fresh.append(enemy)
	# Порядок добавления — это и порядок волны появления, поэтому слева направо.
	fresh.sort_custom(_is_left_of)
	for enemy in fresh:
		var reticle: Reticle = reticle_scene.instantiate()
		reticle.target = enemy
		# Режим прицеливания — обычный Node, а не Node2D, и на нём цепочка трансформов
		# обрывается: прицел не наследует ни позицию, ни масштаб, ни мигание корабля.
		add_child(reticle)
		_reticles.append(reticle)


func _drop_lost_targets() -> void:
	var lost_x := 0.0
	for reticle in _reticles.duplicate():
		if reticle.has_target():
			continue
		_reticles.erase(reticle)
		if reticle == _selected:
			_selected = null
			lost_x = reticle.global_position.x
		reticle.queue_free()
	# Выбор переходит на соседа, ближайшего к погибшей цели, а не прыгает к краю.
	if _selected == null and not _reticles.is_empty():
		_select(_nearest_by_x(lost_x))


func _update_reveal(delta: float) -> void:
	_reveal_cooldown -= delta
	if _reveal_cooldown > 0.0:
		return
	for reticle in _reticles:
		if not reticle.is_revealed():
			reticle.reveal()
			_reveal_cooldown = reveal_interval
			return


# Очередь берётся из порядка прицелов и не пересчитывается по ходу боя. Если сортировать
# по X при каждом нажатии, у летающих врагов очередь меняется под руками: одна и та же
# кнопка ведёт то к одному соседу, то к другому.
func _cycle(step: int) -> void:
	var index := _reticles.find(_selected)
	_select(_reticles[posmod(index + step, _reticles.size())])
	target_cycled.emit(step)


func _select(reticle: Reticle) -> void:
	if reticle == _selected:
		return
	if _selected != null:
		_selected.set_selected(false)
	_selected = reticle
	_selected.set_selected(true)


func _nearest_by_x(x: float) -> Reticle:
	var nearest: Reticle = _reticles[0]
	for reticle in _reticles:
		if absf(reticle.target.global_position.x - x) < absf(nearest.target.global_position.x - x):
			nearest = reticle
	return nearest


func _is_tracked(enemy: Node2D) -> bool:
	for reticle in _reticles:
		if reticle.target == enemy:
			return true
	return false


func _is_left_of(a: Node2D, b: Node2D) -> bool:
	return a.global_position.x < b.global_position.x
