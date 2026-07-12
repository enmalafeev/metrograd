extends Node3D
## Процедурно строит двухпутную линию метро со станциями и разворотными петлями.
##
## Два пути идут параллельно вдоль Z: внешний (x = -T) и внутренний (x = +T).
## Поезд едет по замкнутой кривой: прямой участок по одному пути → петля 180°
## на дальней конечной → обратно по второму пути → петля на ближней конечной.
## На каждой станции — две боковые платформы (по одной у каждого пути).

const T := 3.0               # смещение путей от оси (пути на x = ±T)
const RING := 10.0           # длина сегмента тоннеля, м
const PLATFORM_HALF := 24.0  # половина длины платформы, м
const N := 6                 # число станций
# перегоны между соседними станциями, м (5 перегонов для 6 станций, 0.5–1.0 км)
const GAPS := [700.0, 1000.0, 550.0, 900.0, 650.0]
const LEG_NEAR := 40.0       # z ближней петли (за станцией 0)

const WALL_X := 6.8          # боковые стены
const CEIL_TUN := 3.8        # высота тоннеля
const CEIL_STA := 5.6        # высота свода станции
const PLAT_INNER := 4.2      # внутренний край платформы (у пути)
const PLAT_TOP := 0.55       # высота платформы

var stations := [
	{"name": "Восточная"},   # 0 — ближняя конечная
	{"name": "Центральная"}, # 1
	{"name": "Заречная"},    # 2
	{"name": "Парковая"},    # 3
	{"name": "Северная"},    # 4
	{"name": "Западная"},    # 5 — дальняя конечная
]

var stops: Array = []        # остановки по кривой: {name, idx, terminal, offset}
var _zpos: Array = []        # z каждой станции (накопленные перегоны)
var _leg_far := 0.0          # z дальней петли (за последней станцией)
var _curve: Curve3D
var _mats := {}

func _ready() -> void:
	_compute_layout()
	_build_env()
	_build_curve()
	_build_tunnel()
	_build_loop(_leg_far, -1.0)
	_build_loop(LEG_NEAR, 1.0)
	_compute_stops()

func _compute_layout() -> void:
	# станция 0 в z=0, дальше накапливаем перегоны в -Z
	_zpos = [0.0]
	for g in GAPS:
		_zpos.append(_zpos[-1] - float(g))
	_leg_far = _zpos[-1] - 60.0   # дальняя петля за последней станцией

func station_z(i: int) -> float:
	return _zpos[i]

func get_curve() -> Curve3D:
	return _curve

func total_length() -> float:
	return _curve.get_baked_length()

func start_offset() -> float:
	# станция 0, внешний путь — начало маршрута
	return _curve.get_closest_offset(Vector3(-T, 0, station_z(0)))

# --- кривая маршрута (замкнутая петля) --------------------------------------

func _build_curve() -> void:
	_curve = Curve3D.new()
	_curve.bake_interval = 0.4
	# внешний путь (x=-T): от ближней петли к дальней
	_curve.add_point(Vector3(-T, 0, LEG_NEAR))
	_curve.add_point(Vector3(-T, 0, _leg_far))
	# дальняя петля: -X → +X, выпуклостью в -Z
	_add_arc(_leg_far, -1.0)
	# внутренний путь (x=+T): от дальней петли к ближней
	_curve.add_point(Vector3(T, 0, _leg_far))
	_curve.add_point(Vector3(T, 0, LEG_NEAR))
	# ближняя петля: +X → -X, выпуклостью в +Z (замыкает маршрут)
	_add_arc(LEG_NEAR, 1.0)

func _add_arc(cz: float, s: float) -> void:
	# полукруг радиуса T; s=-1 — дальняя петля, s=+1 — ближняя
	var steps := 16
	for k in range(1, steps):
		var phi := PI * float(k) / float(steps)
		_curve.add_point(Vector3(s * T * cos(phi), 0, cz + s * T * sin(phi)))

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

func _concrete() -> StandardMaterial3D: return _mat("res://assets/textures/tunnel_wall.png", 4.0, 1.2)
func _tile() -> StandardMaterial3D: return _mat("res://assets/textures/station_tile.png", 3.0, 3.0)
func _rail() -> StandardMaterial3D: return _mat("res://assets/textures/rail_bed.png", 1.0, 3.0)
func _platmat() -> StandardMaterial3D: return _mat("res://assets/textures/platform_floor.png", 2.0, 3.0)
func _edge() -> StandardMaterial3D: return _mat("res://assets/textures/platform_edge.png", 1.0, 3.0)

# --- окружение --------------------------------------------------------------

func _build_env() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.62)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.04, 0.06)
	env.fog_density = 0.016
	we.environment = env
	add_child(we)

# --- геометрия --------------------------------------------------------------

func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

func _at_station(zc: float) -> int:
	for i in stations.size():
		if absf(zc - station_z(i)) <= PLATFORM_HALF:
			return i
	return -1

func _build_tunnel() -> void:
	var z := LEG_NEAR
	var idx := 0
	while z >= _leg_far:
		_ring(z, _at_station(z), idx)
		z -= RING
		idx += 1
	# названия станций — надписи на самих стенах станции, лицом к путям
	for i in stations.size():
		var name := str(stations[i]["name"])
		_sign(name, Vector3(-WALL_X + 0.12, 3.9, station_z(i)), PI * 0.5)   # левая стена → лицом +X
		_sign(name, Vector3(WALL_X - 0.12, 3.9, station_z(i)), -PI * 0.5)   # правая стена → лицом -X

func _ring(zc: float, st: int, idx: int) -> void:
	var station := st != -1
	var ch := CEIL_STA if station else CEIL_TUN
	var wallmat := _tile() if station else _concrete()
	# пол во всю ширину + две рельсовые полосы
	_box(Vector3(WALL_X * 2.0, 0.2, RING), Vector3(0, -0.1, zc), _concrete())
	_box(Vector3(1.9, 0.06, RING), Vector3(-T, 0.03, zc), _rail())
	_box(Vector3(1.9, 0.06, RING), Vector3(T, 0.03, zc), _rail())
	# потолок и боковые стены
	_box(Vector3(WALL_X * 2.0 + 0.4, 0.2, RING), Vector3(0, ch, zc), _concrete())
	_box(Vector3(0.2, ch, RING), Vector3(-WALL_X, ch * 0.5, zc), wallmat)
	_box(Vector3(0.2, ch, RING), Vector3(WALL_X, ch * 0.5, zc), wallmat)
	# центральные колонны между путями
	if idx % 2 == 0:
		_box(Vector3(0.5, ch, 0.5), Vector3(0, ch * 0.5, zc), wallmat)
	if station:
		var pw := WALL_X - PLAT_INNER
		var pcx := (WALL_X + PLAT_INNER) * 0.5
		# две боковые платформы
		_box(Vector3(pw, PLAT_TOP, RING), Vector3(-pcx, PLAT_TOP * 0.5, zc), _platmat())
		_box(Vector3(pw, PLAT_TOP, RING), Vector3(pcx, PLAT_TOP * 0.5, zc), _platmat())
		# жёлтые линии у краёв
		_box(Vector3(0.22, 0.06, RING), Vector3(-PLAT_INNER - 0.11, PLAT_TOP + 0.02, zc), _edge())
		_box(Vector3(0.22, 0.06, RING), Vector3(PLAT_INNER + 0.11, PLAT_TOP + 0.02, zc), _edge())
		_light(Vector3(0, ch - 0.3, zc), 2.2, Color(0.92, 0.95, 1.0))
	elif idx % 3 == 0:
		_light(Vector3(0, ch - 0.3, zc), 1.4, Color(1.0, 0.86, 0.62))

func _build_loop(cz: float, s: float) -> void:
	# разворотная камера вокруг полукруга (s=-1 дальняя, s=+1 ближняя)
	var mid := cz + s * (T * 0.5 + 1.0)
	var depth := T + 3.0
	_box(Vector3(WALL_X * 2.0, 0.2, depth), Vector3(0, -0.1, mid), _concrete())
	_box(Vector3(WALL_X * 2.0, 0.2, depth), Vector3(0, CEIL_TUN, mid), _concrete())
	_box(Vector3(0.2, CEIL_TUN, depth), Vector3(-WALL_X, CEIL_TUN * 0.5, mid), _concrete())
	_box(Vector3(0.2, CEIL_TUN, depth), Vector3(WALL_X, CEIL_TUN * 0.5, mid), _concrete())
	# торцевая стена
	_box(Vector3(WALL_X * 2.0, CEIL_TUN, 0.3), Vector3(0, CEIL_TUN * 0.5, cz + s * (T + 1.6)), _tile())
	# рельсовая дуга (короткие плитки вдоль полукруга)
	var steps := 40
	for k in range(steps + 1):
		var phi := PI * float(k) / float(steps)
		_box(Vector3(1.0, 0.06, 1.0), Vector3(s * T * cos(phi), 0.03, cz + s * T * sin(phi)), _rail())
	_light(Vector3(0, CEIL_TUN - 0.3, mid), 1.6, Color(1.0, 0.8, 0.55))

func _light(pos: Vector3, energy: float, color: Color) -> void:
	var o := OmniLight3D.new()
	o.position = pos
	o.omni_range = 16.0
	o.light_energy = energy
	o.light_color = color
	o.shadow_enabled = false
	add_child(o)

func _sign(text: String, pos: Vector3, ry: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.0065
	# без billboard — надпись лежит в плоскости стены и повёрнута к путям
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.modulate = Color(1, 1, 1)
	l.outline_size = 18
	l.outline_modulate = Color(0.05, 0.1, 0.25)
	# смещаем чуть вперёд от плоскости стены, чтобы не было z-fighting
	l.render_priority = 1
	l.position = pos
	l.rotation.y = ry
	add_child(l)

# --- остановки по кривой ----------------------------------------------------

func _compute_stops() -> void:
	_curve.get_baked_length()  # форсируем бейк
	stops.clear()
	for i in stations.size():
		var terminal := i == 0 or i == stations.size() - 1
		# внешний путь (x=-T) и внутренний (x=+T)
		stops.append({
			"name": str(stations[i]["name"]), "idx": i, "terminal": terminal,
			"x": -T,  # внешний путь → внешняя платформа (side = -1)
			"offset": _curve.get_closest_offset(Vector3(-T, 0, station_z(i))),
		})
		stops.append({
			"name": str(stations[i]["name"]), "idx": i, "terminal": terminal,
			"x": T,   # внутренний путь → внутренняя платформа (side = +1)
			"offset": _curve.get_closest_offset(Vector3(T, 0, station_z(i))),
		})
	stops.sort_custom(func(a, b): return a["offset"] < b["offset"])
