extends Node3D
## Процедурно строит прямой тоннель метро со станциями.
## Движение поезда — вдоль -Z (естественное "вперёд" для камеры Godot).
## Станция i расположена в точке z = -s.

const RING := 6.0            # длина одного модульного сегмента, м
const PLATFORM_HALF := 12.0  # половина длины платформы, м
const START_Z := 12.0        # немного пути позади старта
const END_Z := -252.0

var stations := [
	{"name": "Восточная", "s": 0.0},
	{"name": "Центральная", "s": 120.0},
	{"name": "Западная", "s": 240.0},
]

var _mats := {}

func _ready() -> void:
	_build_env()
	_build_world()

func station_z(i: int) -> float:
	return -float(stations[i]["s"])

# --- материалы --------------------------------------------------------------

func _mat(path: String, sx: float, sy: float) -> StandardMaterial3D:
	var key := path + ":" + str(sx) + "x" + str(sy)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_scale = Vector3(sx, sy, 1.0)
	m.roughness = 0.95
	m.metallic = 0.0
	_mats[key] = m
	return m

# --- окружение --------------------------------------------------------------

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.62)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.04, 0.06)
	env.fog_density = 0.018
	we.environment = env
	add_child(we)

# --- сборка мира ------------------------------------------------------------

func _build_world() -> void:
	var z := START_Z
	var ring_index := 0
	while z >= END_Z:
		var st := _station_at(z)
		if st == -1:
			_tunnel_ring(z)
			if ring_index % 3 == 0:
				_light(z, 1.4, Color(1.0, 0.85, 0.6))
		else:
			_station_ring(z)
			_light(z, 1.6, Color(0.85, 0.9, 1.0))
		z -= RING
		ring_index += 1
	for i in stations.size():
		_sign(i)

func _station_at(zc: float) -> int:
	for i in stations.size():
		if absf(zc - station_z(i)) <= PLATFORM_HALF:
			return i
	return -1

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _floor_and_track(zc: float) -> void:
	_box(Vector3(3.4, 0.2, RING), Vector3(0, -0.1, zc), _mat("res://assets/textures/tunnel_wall.png", 1.7, 3.0))
	_box(Vector3(1.9, 0.06, RING), Vector3(0, 0.03, zc), _mat("res://assets/textures/rail_bed.png", 1.0, 3.0))

func _tunnel_ring(zc: float) -> void:
	var wall := _mat("res://assets/textures/tunnel_wall.png", 3.0, 1.6)
	_floor_and_track(zc)
	_box(Vector3(0.2, 3.2, RING), Vector3(-1.7, 1.6, zc), wall)  # левая стена
	_box(Vector3(0.2, 3.2, RING), Vector3(1.7, 1.6, zc), wall)   # правая стена
	_box(Vector3(3.6, 0.2, RING), Vector3(0, 3.2, zc), wall)     # потолок

func _station_ring(zc: float) -> void:
	var tile := _mat("res://assets/textures/station_tile.png", 3.0, 2.2)
	var wall := _mat("res://assets/textures/tunnel_wall.png", 3.4, 1.0)
	_floor_and_track(zc)
	# облицованная стена со стороны без платформы
	_box(Vector3(0.2, 4.4, RING), Vector3(-1.7, 2.2, zc), tile)
	# платформа (поднятый пол) со стороны +X
	_box(Vector3(3.2, 0.55, RING), Vector3(3.3, 0.275, zc), _mat("res://assets/textures/platform_floor.png", 1.6, 3.0))
	# жёлтая линия у края платформы
	_box(Vector3(0.25, 0.06, RING), Vector3(1.85, 0.58, zc), _mat("res://assets/textures/platform_edge.png", 1.0, 3.0))
	# задняя стена платформы, облицованная плиткой
	_box(Vector3(0.2, 4.4, RING), Vector3(4.9, 2.2, zc), tile)
	# высокий потолок станции
	_box(Vector3(6.9, 0.2, RING), Vector3(1.6, 4.0, zc), wall)

func _light(zc: float, energy: float, color: Color) -> void:
	var o := OmniLight3D.new()
	o.position = Vector3(0, 3.0, zc)
	o.omni_range = 14.0
	o.light_energy = energy
	o.light_color = color
	o.shadow_enabled = false
	add_child(o)

func _sign(i: int) -> void:
	var l := Label3D.new()
	l.text = str(stations[i]["name"])
	l.font_size = 96
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(1, 1, 1)
	l.outline_size = 18
	l.outline_modulate = Color(0.05, 0.1, 0.25)
	l.position = Vector3(3.3, 2.9, station_z(i))
	add_child(l)
