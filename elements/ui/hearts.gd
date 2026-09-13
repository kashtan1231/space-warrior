extends HBoxContainer

## Ряд сердец: одно сердце — одна единица здоровья. Число сердец следует за max_health
## корабля, заполненность — за health.

const HEART_SCENE = preload("res://elements/ui/heart.tscn")

## Задержка между появлением соседних сердец, секунд. Сердца вылетают волной слева направо;
## 0 — все появляются одновременно, больше — волна идёт медленнее.
@export var appear_interval := 0.08

var _player: Node
var _hearts: Array[Control] = []


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_player.health_changed.connect(_on_player_health_changed)
	# Подписка могла опоздать: корабль стоит в дереве выше и успевает отправить
	# стартовый сигнал до того, как ряд сердец доберётся до своего _ready. Поэтому
	# текущее состояние ещё и забирается напрямую. Повторный вызов с теми же числами
	# ничего не ломает: лишних сердец не создаётся, заполненность не меняется.
	_on_player_health_changed(_player.health, _player.max_health)


func _on_player_health_changed(health: int, max_health: int) -> void:
	_sync_count(health, max_health)
	for i in _hearts.size():
		_hearts[i].set_filled(i < health)


func _sync_count(health: int, max_health: int) -> void:
	# Волна отсчитывается от первого нового сердца, а не от начала ряда: при прокачке
	# добавленное сердце появляется сразу, не дожидаясь «очереди» старых.
	var wave_index := 0
	while _hearts.size() < max_health:
		var heart: Control = HEART_SCENE.instantiate()
		add_child(heart)
		heart.appear(wave_index * appear_interval, _hearts.size() < health)
		_hearts.append(heart)
		wave_index += 1

	while _hearts.size() > max_health:
		_hearts.pop_back().queue_free()
