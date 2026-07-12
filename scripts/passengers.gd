extends Node3D
## Пассажиры на платформах станций: ожидают поезд, входят и выходят из вагонов.
##
## На каждой платформе каждой станции стоит группа блочных пиксель-арт фигурок.
## Когда поезд открывает двери, main.gd вызывает board_and_alight(): часть
## ожидающих идёт к ближайшей двери и «садится» (исчезает в вагоне), а часть
## пассажиров «выходит» из вагона и расходится по платформе. Ходьба — твинами.

const DOOR_X := 4.3            # |x| дверного проёма вагона у платформы
const PLAT_NEAR := 4.75        # ближний к путям край зоны ожидания
const PLAT_FAR := 6.35         # дальний край (у стены)
const FLOOR_Y := 0.55          # уровень пола платформы
const SPREAD := 21.0           # разброс ожидающих вдоль платформы, м
const WALK_SPEED := 1.4        # скорость ходьбы, м/с
const CROWD_CAP := 18          # мягкий предел людей на платформе
# z дверей вагонов относительно центра станции (8 дверей четырёхвагонного состава)
const DOOR_ZS := [-20.4, -15.6, -8.6, -3.4, 3.4, 8.6, 15.6, 20.4]

var _world: Node3D
var _rng := RandomNumberGenerator.new()
var _waiting := {}             # "idx:side" → Array[Node3D] ожидающих
var _matcache := {}            # Color → StandardMaterial3D

var _shirt := [
	Color(0.78, 0.22, 0.22), Color(0.20, 0.35, 0.62), Color(0.24, 0.52, 0.30),
	Color(0.72, 0.60, 0.18), Color(0.45, 0.28, 0.55), Color(0.28, 0.55, 0.60),
	Color(0.66, 0.66, 0.70), Color(0.80, 0.45, 0.20),
]
var _skin := [Color(0.94, 0.78, 0.62), Color(0.80, 0.60, 0.45), Color(0.62, 0.44, 0.30)]
var _pants := [Color(0.16, 0.17, 0.22), Color(0.24, 0.21, 0.18), Color(0.20, 0.24, 0.32)]

func setup(world: Node3D) -> void:
	_world = world
	_rng.randomize()
	for i in world.stations.size():
		for side in [-1, 1]:
			_spawn_waiting(i, side, _rng.randi_range(5, 10))

# --- посадка / высадка ------------------------------------------------------

## Поезд открыл двери на станции idx у пути со стороны side (=sign(track_x)).
func board_and_alight(idx: int, side: int) -> void:
	var zc: float = _world.station_z(idx)
	var key := _key(idx, side)
	var list: Array = _waiting.get(key, [])

	# выходят из вагонов на платформу (не переполняем платформу)
	var out := 0 if list.size() > CROWD_CAP else _rng.randi_range(2, 5)
	for _n in out:
		var p := _make_person()
		p.position = _door_spot(side, zc)
		add_child(p)
		_walk(p, _wait_spot(side, zc), _on_alighted.bind(key, p))

	# заходят в вагоны с платформы
	var board := mini(_rng.randi_range(2, 5), list.size())
	for _n in board:
		var p: Node3D = list.pop_back()
		_walk(p, _door_spot(side, zc), _on_boarded.bind(p))

func _on_alighted(key: String, p: Node3D) -> void:
	if is_instance_valid(p):
		_waiting[key].append(p)   # вышедший встаёт в очередь ожидающих

func _on_boarded(p: Node3D) -> void:
	if is_instance_valid(p):
		p.queue_free()            # вошедший исчезает «в вагоне»

# --- размещение -------------------------------------------------------------

func _key(idx: int, side: int) -> String:
	return "%d:%d" % [idx, side]

func _spawn_waiting(idx: int, side: int, count: int) -> void:
	var key := _key(idx, side)
	if not _waiting.has(key):
		_waiting[key] = []
	var zc: float = _world.station_z(idx)
	for _n in count:
		var p := _make_person()
		p.position = _wait_spot(side, zc)
		add_child(p)
		_waiting[key].append(p)

func _wait_spot(side: int, zc: float) -> Vector3:
	return Vector3(side * _rng.randf_range(PLAT_NEAR, PLAT_FAR),
			FLOOR_Y, zc + _rng.randf_range(-SPREAD, SPREAD))

func _door_spot(side: int, zc: float) -> Vector3:
	var dz: float = DOOR_ZS[_rng.randi() % DOOR_ZS.size()] + _rng.randf_range(-0.6, 0.6)
	return Vector3(side * DOOR_X, FLOOR_Y, zc + dz)

func _walk(p: Node3D, dest: Vector3, on_done: Callable) -> void:
	var body: Node3D = p.get_meta("body")
	var d := p.position.distance_to(dest)
	var dur := clampf(d / WALK_SPEED, 0.35, 2.2)
	var tw := create_tween()
	tw.tween_property(p, "position", dest, dur)
	# лёгкое покачивание корпуса — имитация шага
	tw.parallel().tween_method(_bob.bind(body), 0.0, PI * maxf(2.0, d * 4.0), dur)
	tw.finished.connect(_arrive.bind(body, on_done))

func _bob(ph: float, body: Node3D) -> void:
	if is_instance_valid(body):
		body.position.y = absf(sin(ph)) * 0.05

func _arrive(body: Node3D, on_done: Callable) -> void:
	if is_instance_valid(body):
		body.position.y = 0.0
	if on_done.is_valid():
		on_done.call()

# --- фигурка пассажира (блочный пиксель-арт человечек) ----------------------

func _make_person() -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	root.set_meta("body", body)
	var shirt: Color = _shirt[_rng.randi() % _shirt.size()]
	var skin: Color = _skin[_rng.randi() % _skin.size()]
	var pants: Color = _pants[_rng.randi() % _pants.size()]
	var s := _rng.randf_range(0.9, 1.08)   # рост варьируется
	# ноги
	_pbox(body, Vector3(0.15, 0.5, 0.17), Vector3(-0.1, 0.25 * s, 0), pants)
	_pbox(body, Vector3(0.15, 0.5, 0.17), Vector3(0.1, 0.25 * s, 0), pants)
	# торс
	_pbox(body, Vector3(0.44, 0.58, 0.27), Vector3(0, 0.79 * s, 0), shirt)
	# руки
	_pbox(body, Vector3(0.12, 0.54, 0.16), Vector3(-0.28, 0.78 * s, 0), shirt)
	_pbox(body, Vector3(0.12, 0.54, 0.16), Vector3(0.28, 0.78 * s, 0), shirt)
	# голова
	_pbox(body, Vector3(0.25, 0.27, 0.25), Vector3(0, 1.22 * s, 0), skin)
	return root

func _pbox(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _color_mat(color)
	mi.position = pos
	parent.add_child(mi)

func _color_mat(c: Color) -> StandardMaterial3D:
	if not _matcache.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.9
		m.metallic = 0.0
		_matcache[c] = m
	return _matcache[c]
