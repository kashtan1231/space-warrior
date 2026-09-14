extends Sprite2D

## Шкала перезарядки нырка из делений. Сама ничего не отсчитывает: корабль сообщает долю
## заряда сигналом dodge_charge_changed, а шкала только выбирает под неё кадр.
##
## Текстура — горизонтальная полоска кадров (hframes), от полной шкалы к пустой:
## нулевой кадр — все деления горят, последний — ни одного. Число делений берётся из
## числа кадров, так что код не зависит от конкретного листа.


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	player.dodge_charge_changed.connect(_on_player_dodge_charge_changed)
	# Корабль стартует с полным зарядом и до первого нырка сигнал не шлёт,
	# поэтому начальное состояние выставляется здесь.
	_on_player_dodge_charge_changed(1.0)


func _on_player_dodge_charge_changed(charge: float) -> void:
	var segments := hframes - 1
	# Деление загорается, только когда набралось целиком: последнее вспыхивает ровно
	# в момент готовности нырка, и полная шкала всегда значит «можно нырять».
	var filled := floori(charge * segments)
	frame = segments - filled
