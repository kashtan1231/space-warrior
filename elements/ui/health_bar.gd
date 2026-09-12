extends ProgressBar

var _player: Node


func _ready() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_player.health_changed.connect(_on_player_health_changed)
	# Подписка могла опоздать: корабль стоит в дереве выше и успевает отправить
	# стартовый сигнал до того, как полоска доберётся до своего _ready. Поэтому
	# текущее состояние ещё и забирается напрямую.
	_on_player_health_changed(_player.health, _player.max_health)


func _on_player_health_changed(health: int, max_health: int) -> void:
	max_value = max_health
	value = health
