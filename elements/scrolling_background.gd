extends Sprite2D

## Скорость прокрутки фона, пикселей в секунду. Больше — корабль будто летит быстрее.
## Отрицательное значение пускает фон в обратную сторону, будто корабль летит назад.
@export var speed := 40.0

var _offset := 0.0


func _process(delta: float) -> void:
	# Окно региона едет вверх по текстуре, поэтому картинка на экране ползёт вниз.
	# texture_repeat заворачивает всё, что за краем текстуры, а fposmod не даёт
	# смещению расти бесконечно.
	_offset = fposmod(_offset - speed * delta, texture.get_height())
	# Целые пиксели: при дробном сдвиге пиксель-арт с фильтром Nearest дрожит.
	region_rect.position.y = roundf(_offset)
