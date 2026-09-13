extends Control

## Одно сердце индикатора здоровья. Само ничего не знает про корабль: ряд сердец
## (hearts.gd) говорит ему, когда появиться и полное оно или пустое.
##
## Анимаций в SpriteFrames две:
## - appear — появление, последний кадр — целое красное сердце;
## - break — разрушение, первый кадр — целое сердце, последний — тёмное пустое.
## Отдельных «стоячих» анимаций нет: полное и пустое сердце — это последние кадры этих двух.

const APPEAR := &"appear"
const BREAK := &"break"

@onready var sprite: AnimatedSprite2D = $Sprite

var _filled := true
var _appear_tween: Tween


func _ready() -> void:
	sprite.animation_finished.connect(_on_sprite_animation_finished)


## Показывает сердце через delay секунд анимацией появления. До этого момента оно скрыто,
## но место в ряду уже занимает, поэтому соседи не прыгают при появлении.
func appear(delay: float, filled: bool) -> void:
	_filled = filled
	sprite.hide()
	_appear_tween = create_tween()
	_appear_tween.tween_interval(delay)
	_appear_tween.tween_callback(_start_appear)


func set_filled(filled: bool) -> void:
	if _filled == filled:
		return
	_filled = filled
	# Урон мог прийти, пока сердце ещё ждёт своей очереди в волне появления, —
	# тогда ожидание отменяется, и сердце сразу показывает разрушение.
	if _appear_tween != null and _appear_tween.is_running():
		_appear_tween.kill()
	sprite.show()
	if filled:
		# Анимации лечения пока нет: сердце мгновенно становится целым.
		_show_last_frame(APPEAR)
	else:
		sprite.play(BREAK)


func _start_appear() -> void:
	sprite.show()
	sprite.play(APPEAR)


func _on_sprite_animation_finished() -> void:
	# Сердце, созданное сверх текущего здоровья (прокачали максимум без лечения), всё равно
	# проигрывает появление, а по его окончании сразу показывается пустым.
	if sprite.animation == APPEAR and not _filled:
		_show_last_frame(BREAK)


func _show_last_frame(animation: StringName) -> void:
	# Смена animation сбрасывает кадр на нулевой, поэтому кадр выставляется вторым.
	# play() не вызывается: нужна неподвижная картинка, а не проигрывание.
	sprite.animation = animation
	sprite.frame = sprite.sprite_frames.get_frame_count(animation) - 1
