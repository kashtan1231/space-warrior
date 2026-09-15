extends Node2D

## Панель приборов: подложка, бары и переключатели. При старте сцены отыгрывает запуск
## систем: щелчки переключателей, затем волну лампочек здоровья и заполнение шкалы нырка.
##
## Бары и переключатели сами ничего не запускают — они только умеют показать анимацию,
## когда их попросят. Весь порядок и паузы живут здесь, в одном месте.

@export_group("Switches")
## Через сколько секунд после старта сцены включается левый переключатель
## и загорается красная лампочка.
@export var left_on_delay := 0.6
## Через сколько секунд после того, как красная лампочка левого переключателя отмерцала
## и горит ровно, включается правый переключатель с зелёной лампочкой.
@export var right_on_delay := 0.8
## Через сколько секунд после того, как зелёная лампочка правого переключателя отмерцала
## и горит ровно, выключается левый переключатель и гаснет красная.
@export var left_off_delay := 0.8

@export_group("Systems")
## Через сколько секунд после того, как зелёная лампочка правого переключателя отмерцала,
## начинается волна лампочек здоровья. Отсчёт идёт параллельно с выключением левого.
@export var health_delay := 2.0
## Пауза между концом волны здоровья и началом заполнения шкалы нырка, секунд.
@export var dodge_delay := 0.3

@onready var left_toggle: Toggle = $LeftToggle
@onready var right_toggle: Toggle = $RightToggle
@onready var health_bar: HealthBar = $HealthBar
@onready var dodge_bar: DodgeBar = $DodgeBar


func _ready() -> void:
	# Функция с await внутри — корутина. Вызов без await не ждёт её конца: она доходит
	# до первого await и возвращает управление, а продолжается сама, когда придёт сигнал.
	_run_switches()


func _run_switches() -> void:
	await _wait(left_on_delay)
	left_toggle.set_on(true)
	await _wait_flicker(left_toggle)
	await _wait(right_on_delay)
	right_toggle.set_on(true)
	await _wait_flicker(right_toggle)
	# Запуск систем и выключение левого переключателя идут каждый по своим часам.
	_boot_systems()
	await _wait(left_off_delay)
	left_toggle.set_on(false)


# Возвращает управление, когда лампочка переключателя отмерцала.
func _wait_flicker(toggle: Toggle) -> void:
	# При Flicker Count = 0 мерцания нет, и сигнал о его конце не придёт.
	if toggle.is_flickering():
		await toggle.flicker_finished


func _boot_systems() -> void:
	await _wait(health_delay)
	health_bar.play_intro()
	# Урон до запуска уже закончил волну, и сигнала о её конце больше не будет.
	if not health_bar.intro_done:
		await health_bar.intro_finished
	await _wait(dodge_delay)
	dodge_bar.play_intro()


# Сигнал, который придёт через seconds секунд. Ожидание сделано tween'ом, а не таймером
# дерева: tween принадлежит узлу и умирает вместе с ним, поэтому корутина не проснётся
# на удалённом дашборде.
func _wait(seconds: float) -> Signal:
	return create_tween().tween_interval(seconds).finished
