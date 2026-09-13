extends AnimatedSprite2D

## Самая короткая пауза перед сменой кадра, секунд. Меньше — звёзды иногда мигают почти мгновенно.
@export var min_frame_time := 0.1
## Самая длинная пауза перед сменой кадра, секунд. Больше — звёзды иногда надолго замирают.
## Каждая пауза выбирается случайно между этими двумя значениями.
@export var max_frame_time := 0.6


func _ready() -> void:
	frame_changed.connect(_randomize_frame_time)
	_randomize_frame_time()


# Движок сам не умеет случайную длительность кадра, зато честно учитывает speed_scale.
# Сразу после смены кадра подбираем множитель скорости так, чтобы именно этот кадр
# провисел выбранное случайное время. Учитывается и FPS анимации, и Duration кадра
# из SpriteFrames, поэтому любые их значения в редакторе не ломают расчёт.
func _randomize_frame_time() -> void:
	var fps := sprite_frames.get_animation_speed(animation)
	var base_time := sprite_frames.get_frame_duration(animation, frame) / fps
	speed_scale = base_time / randf_range(min_frame_time, max_frame_time)
