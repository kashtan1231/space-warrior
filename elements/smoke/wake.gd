extends Node2D
class_name Wake

## След в дыме. Узел-компонент: кладётся в сцену корабля или снаряда в центр корпуса, и тот
## раздвигает дым на своём пути и немного тащит его за собой. Коду владельца для этого
## ничего не нужно — дым сам обходит все следы на уровне, см. smoke.gd.
##
## Скорость компонент считает сам, по сдвигу между физическими кадрами, поэтому работает
## с любым владельцем: кораблём, пулей, ракетой. Дым, выпущенный соплом той же сцены
## (см. smoke_trail.gd), след не трогает: иначе ракета раздувала бы собственный выхлоп
## прямо у сопла.
##
## Владелец — корень сцены, в которой лежит компонент. Его же след уводит под дым, см.
## set_submerged, поэтому корень сцены и узел дыма должны быть соседями в дереве уровня:
## корабли, снаряды и Smoke лежат прямо в корне уровня.

## Полуширина коридора, который объект пробивает в дыме, пикселей экрана: масштаб сцены
## на неё не влияет. Обычно чуть больше половины ширины корпуса. Больше — объект расчищает
## широкую полосу; меньше — дым обтекает его почти вплотную.
@export var radius := 24.0
## Насколько резко дым уходит с пути, в долях скорости объекта сквозь воздух. 0 — дым
## не раздвигается; 0.5 — клуб прямо на пути отлетает в сторону с половиной этой скорости;
## 1 и больше — коридор пробивается резко и широко расходится.
@export_range(0.0, 2.0, 0.05) var push := 0.5
## Как сильно объект тащит дым за собой, в долях разницы скоростей за секунду. 0 — дым
## только раздвигается; больше — за объектом тянется хвост увлечённого дыма.
@export var drag := 4.0

## Группа, по которой дым находит все следы на уровне.
const GROUP := &"smoke_wakes"

var _segment_start := Vector2.ZERO
var _segment_end := Vector2.ZERO
var _velocity := Vector2.ZERO
var _tracking := false
var _submerged := false
var _disabled := false
var _base_z_index := 0


func _ready() -> void:
	# Группа выдаётся здесь, а не в сцене: компонент лежит в полудюжине сцен, и группа,
	# забытая в одной из них, молча оставила бы объект без следа.
	add_to_group(GROUP)
	_base_z_index = (owner as CanvasItem).z_index


func _physics_process(delta: float) -> void:
	var position_now := global_position
	# Первый кадр только запоминает позицию. Пулю и ракету ставят на место уже после
	# добавления в дерево, и сдвиг от нуля до дула читался бы как пролёт через весь экран.
	_segment_start = _segment_end if _tracking else position_now
	_segment_end = position_now
	_velocity = (_segment_end - _segment_start) / delta
	_tracking = true


## Толкает ли след дым прямо сейчас.
func is_pushing() -> bool:
	return _tracking and not _submerged and not _disabled


## Откуда объект начал последний физический кадр, в глобальных координатах.
func get_segment_start() -> Vector2:
	return _segment_start


## Где объект закончил последний физический кадр, в глобальных координатах.
func get_segment_end() -> Vector2:
	return _segment_end


## Скорость объекта за последний физический кадр, пикселей в секунду.
func get_velocity() -> Vector2:
	return _velocity


## Экземпляр, которому принадлежит след. По нему дым узнаёт выхлоп этого же снаряда.
func get_source_id() -> int:
	return owner.get_instance_id()


## Уводит объект под дым или возвращает обратно. Под дымом он не раздвигает облако
## и рисуется под ним: так выглядят нырок корабля и падение ракеты с крыла, когда объект
## по задумке уходит с плоскости боя.
func set_submerged(submerged: bool) -> void:
	if submerged == _submerged:
		return
	_submerged = submerged
	var body := owner as CanvasItem
	if submerged:
		var smoke := get_tree().get_first_node_in_group(Smoke.GROUP) as Smoke
		body.z_index = smoke.z_index - 1
	else:
		body.z_index = _base_z_index


## Выключает след насовсем: обломки, доигрывающие взрыв на месте, дым уже не трогают.
func disable() -> void:
	_disabled = true
