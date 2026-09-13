extends AnimatedSprite2D


func _ready() -> void:
	# Вспышка живёт ровно одну анимацию: длительность задаётся FPS в SpriteFrames.
	# animation_finished приходит только у незацикленной анимации, поэтому Loop выключен.
	animation_finished.connect(queue_free)
