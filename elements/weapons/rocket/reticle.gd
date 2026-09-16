extends Node2D
class_name Reticle

const LOCK_ANIMATION := &"lock"
const ENEMY_GROUP := &"enemies"

@onready var mark: AnimatedSprite2D = $Mark
@onready var lock: AnimatedSprite2D = $Lock

## Враг, над которым висит прицел. Выставляется до добавления прицела в дерево.
var target: Node2D

var _revealed := false
var _selected := false


func _ready() -> void:
	# До своей очереди в волне появления прицел не виден, но уже стоит на враге.
	mark.hide()
	lock.hide()
	# Пульсация собрана из незацикленной анимации: доиграв в одну сторону, она запускается
	# в другую. Loop в SpriteFrames так не умеет — он всегда начинает с первого кадра.
	mark.animation_finished.connect(_bounce.bind(mark))
	lock.animation_finished.connect(_bounce.bind(lock))
	_follow()


func _process(_delta: float) -> void:
	_follow()


## Жив ли враг под прицелом. Взрывающийся враг выходит из группы, но узел ещё существует,
## пока доигрывает взрыв, — такой считается потерянным.
func has_target() -> bool:
	return is_instance_valid(target) and target.is_in_group(ENEMY_GROUP)


func is_revealed() -> bool:
	return _revealed


## Показывает прицел: уголки сходятся на враге и дальше пульсируют.
func reveal() -> void:
	_revealed = true
	_show_current()


func set_selected(value: bool) -> void:
	_selected = value
	if _revealed:
		_show_current()


func _show_current() -> void:
	var shown := lock if _selected else mark
	var hidden := mark if _selected else lock
	# Спрятанный спрайт тоже останавливается, иначе продолжал бы пульсировать невидимым.
	hidden.stop()
	hidden.hide()
	shown.show()
	# stop() сбрасывает на кадр 0, и play_backwards начинает с последнего кадра:
	# в листе уголки расходятся от кадра к кадру, так что задом наперёд они сходятся.
	shown.stop()
	shown.play_backwards(LOCK_ANIMATION)


# Кадр, на котором анимация закончилась, говорит, в какую сторону она шла:
# на нулевом уголки сошлись — пора расходиться, на последнем — наоборот.
func _bounce(sprite: AnimatedSprite2D) -> void:
	if sprite.frame == 0:
		sprite.play(LOCK_ANIMATION)
	else:
		sprite.play_backwards(LOCK_ANIMATION)


func _follow() -> void:
	# Прицел — не дочерний узел врага, поэтому догоняет его сам. Проверка нужна: враг
	# мог удалиться в этом кадре раньше, чем режим прицеливания убрал прицел.
	if is_instance_valid(target):
		global_position = target.global_position
