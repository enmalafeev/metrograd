extends Node3D
## Поезд метро из 4 вагонов с салоном: кинематика движения + кабина, фары, камера.
##
## Движется по замкнутой кривой маршрута (world.get_curve()) по дистанции progress,
## где progress — центр состава. Каждый вагон ставится на кривую отдельно (по своему
## смещению вдоль неё) и ориентируется по касательной, поэтому состав правильно
## изгибается на разворотных петлях. Головной вагон (0) несёт кабину, фары и камеру.

const MAX_SPEED := 22.22  # м/с (~80 км/ч)
const REVERSE_MAX := 3.0
const ACCEL := 2.8        # м/с² при полной тяге
const BRAKE := 5.5        # м/с² при полном торможении
const ROLL := 0.5         # сопротивление на выбеге

const CARS := 4           # число вагонов
const CAR_LEN := 11.0     # длина вагона, м
const CAR_GAP := 1.0      # зазор между вагонами (сцепка), м
const HALF := CAR_LEN * 0.5
const HW := 1.25          # половина ширины кузова, м
const ROOF := 2.72        # верх кузова, м
const FLOOR := 0.5        # уровень пола салона, м
const WIN_BOT := 1.15     # низ оконной ленты
const WIN_TOP := 2.05     # верх оконной ленты
const CAB_Z := -HALF + 1.6  # позиция машиниста в головном вагоне (локальная z)
const DOOR_W := 1.3         # ширина дверного проёма, м
const DOOR_SLIDE := 0.6     # ход одной створки при открытии, м

var speed := 0.0
var throttle := 0.0       # -1..1: + тяга, - тормоз
var doors_open := false: set = _set_doors_open
var progress := 0.0       # дистанция центра состава вдоль кривой, м

enum View { CAB, SALON, EXTERIOR, FRONT, FACE }  # порядок = индексы кнопок в main.gd

var _curve: Curve3D
var _len := 0.0
var _cars: Array[Node3D] = []
var _cams: Array[Camera3D] = [null, null, null, null, null]  # камеры видов, индекс = View
var _doors: Array = []    # створки платформенной стороны: {node, closed, open, tween}

# --- материалы --------------------------------------------------------------
var _ext: StandardMaterial3D      # кузов (светло-серо-голубой)
var _skirt: StandardMaterial3D    # тёмно-синяя юбка/низ борта
var _trim: StandardMaterial3D     # синяя поясная полоса
var _red: StandardMaterial3D      # красная маска передка головного вагона
var _glass: StandardMaterial3D    # окна
var _door: StandardMaterial3D     # двери
var _floor: StandardMaterial3D    # пол салона
var _seat: StandardMaterial3D     # сиденья
var _pole: StandardMaterial3D     # поручни
var _glow: StandardMaterial3D     # плафоны освещения
var _dark: StandardMaterial3D     # кабина / тёмные детали
var _skinm: StandardMaterial3D    # кожа сидящих пассажиров
var _people: Array[StandardMaterial3D] = []  # цвета одежды пассажиров

func _ready() -> void:
	_init_materials()
	for i in range(CARS):
		var car := Node3D.new()
		car.name = "Car%d" % i
		add_child(car)
		_cars.append(car)
		_build_car(car, i == 0)

func setup(curve: Curve3D, start_offset: float) -> void:
	_curve = curve
	_len = curve.get_baked_length()
	progress = start_offset
	_place()

func _physics_process(delta: float) -> void:
	var a := 0.0
	if doors_open:
		# с открытыми дверями поезд удерживается на месте
		a = -signf(speed) * BRAKE
		if absf(speed) < 0.2:
			speed = 0.0
	else:
		if throttle > 0.01:
			a = ACCEL * throttle - ROLL
		elif throttle < -0.01:
			if speed > 0.2:
				a = BRAKE * throttle           # активное торможение
			else:
				a = ACCEL * throttle * 0.5     # плавный ход назад
		else:
			a = -signf(speed) * ROLL           # выбег

	speed += a * delta
	if throttle == 0.0 and not doors_open and absf(speed) < 0.05:
		speed = 0.0
	speed = clampf(speed, -REVERSE_MAX, MAX_SPEED)
	if _len > 0.0:
		progress = fposmod(progress + speed * delta, _len)
		_place()

func _place() -> void:
	if _curve == null or _len <= 0.0:
		return
	var total := CARS * CAR_LEN + (CARS - 1) * CAR_GAP
	for i in range(CARS):
		# центр вагона i относительно центра состава (0 — головной, впереди)
		var off := progress + total * 0.5 - HALF - i * (CAR_LEN + CAR_GAP)
		var p := _sample(off)
		var ahead := _sample(off + 0.6)
		var car := _cars[i]
		car.position = p
		if p.distance_to(ahead) > 0.001:
			car.look_at(ahead, Vector3.UP)

func _sample(o: float) -> Vector3:
	return _curve.sample_baked(fposmod(o, _len))

func speed_kmh() -> float:
	return absf(speed) * 3.6

# --- двери вагонов ----------------------------------------------------------

func _set_doors_open(v: bool) -> void:
	if v == doors_open:
		return
	doors_open = v
	_animate_doors(v)

## Плавно раздвигает (open) или сдвигает створки платформенной стороны.
func _animate_doors(open: bool) -> void:
	for d in _doors:
		var node: Node3D = d["node"]
		if not is_instance_valid(node):
			continue
		if d.has("tween") and d["tween"] != null and d["tween"].is_valid():
			d["tween"].kill()
		var target_z: float = d["open"] if open else d["closed"]
		var tw := create_tween()
		tw.tween_property(node, "position:z", target_z, 0.55) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		d["tween"] = tw

# --- материалы --------------------------------------------------------------

func _init_materials() -> void:
	_ext = _flat(Color(0.66, 0.71, 0.76), 0.35, 0.4)     # светло-серо-голубой стальной кузов (Еж3)
	_skirt = _flat(Color(0.13, 0.24, 0.46), 0.2, 0.45)   # тёмно-синяя юбка
	_trim = _flat(Color(0.17, 0.36, 0.64), 0.2, 0.45)    # синяя поясная полоса
	_red = _flat(Color(0.66, 0.15, 0.16), 0.1, 0.5)      # красная маска передка
	_door = _flat(Color(0.58, 0.63, 0.69), 0.25, 0.4)    # двери в цвет кузова, чуть светлее
	_floor = _flat(Color(0.17, 0.18, 0.21), 0.0, 0.9)
	_seat = _flat(Color(0.18, 0.34, 0.62), 0.0, 0.6)
	_pole = _flat(Color(0.86, 0.72, 0.24), 0.6, 0.3)
	_dark = _flat(Color(0.13, 0.14, 0.16), 0.0, 0.8)
	_skinm = _flat(Color(0.9, 0.72, 0.56), 0.0, 0.9)
	_people = [
		_flat(Color(0.78, 0.22, 0.22), 0.0, 0.9),
		_flat(Color(0.20, 0.35, 0.62), 0.0, 0.9),
		_flat(Color(0.24, 0.52, 0.30), 0.0, 0.9),
		_flat(Color(0.72, 0.60, 0.18), 0.0, 0.9),
		_flat(Color(0.45, 0.28, 0.55), 0.0, 0.9),
	]
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.45, 0.55, 0.63, 0.30)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.metallic = 0.2
	_glass.roughness = 0.1
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(1.0, 0.98, 0.92)
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.97, 0.9)
	_glow.emission_energy_multiplier = 2.5

func _flat(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

# --- вагон ------------------------------------------------------------------

func _build_car(car: Node3D, lead: bool) -> void:
	var body_len := CAR_LEN - 0.3
	# подрамник/пол-структура
	_box(car, Vector3(2.5, FLOOR, body_len), Vector3(0, FLOOR * 0.5, 0), _ext)
	# крыша
	_box(car, Vector3(2.5, 0.14, body_len), Vector3(0, ROOF - 0.07, 0), _ext)

	for sx in [-HW, HW]:
		var platform: bool = sx < 0.0   # платформенная (левая по ходу) сторона — с проёмами
		# надоконный пояс-перемычка над дверьми — сплошной с обеих сторон
		_box(car, Vector3(0.08, ROOF - 0.14 - WIN_TOP, body_len), Vector3(sx, (WIN_TOP + ROOF - 0.14) * 0.5, 0), _ext)
		# борт под окнами и оконная лента: на платформенной стороне разорваны под
		# дверные проёмы, чтобы через открытые двери был виден перрон из салона
		for seg in _side_segments(body_len * 0.5, platform):
			var z0: float = seg[0]
			var z1: float = seg[1]
			var zc := (z0 + z1) * 0.5
			var ln := z1 - z0
			_box(car, Vector3(0.06, 0.16, ln), Vector3(sx * 1.03, WIN_BOT - 0.1, zc), _trim)                     # синяя поясная полоса
			_box(car, Vector3(0.08, WIN_BOT - FLOOR, ln), Vector3(sx, (FLOOR + WIN_BOT) * 0.5, zc), _skirt)      # тёмно-синяя юбка
			_box(car, Vector3(0.05, WIN_TOP - WIN_BOT, ln), Vector3(sx, (WIN_BOT + WIN_TOP) * 0.5, zc), _glass)  # стекло
			# горизонтальные рёбра гофра по низу борта
			for ry in [FLOOR + 0.18, FLOOR + 0.42]:
				_box(car, Vector3(0.03, 0.05, ln), Vector3(sx * 1.04, ry, zc), _ext)
		# оконные стойки (в глухих оконных секциях, вне проёмов)
		for mz in [-3.3, -1.1, 1.1, 3.3]:
			_box(car, Vector3(0.1, WIN_TOP - WIN_BOT, 0.12), Vector3(sx, (WIN_BOT + WIN_TOP) * 0.5, mz), _ext)
		# двери (по две с каждой стороны, у платформы)
		for dz in [-2.6, 2.6]:
			_build_door(car, sx, dz)

	# торцы вагона с дверью в переход (у головного передний торец открыт под кабину)
	_build_end(car, HALF - 0.05)
	if not lead:
		_build_end(car, -HALF + 0.05)

	_build_salon(car, lead)

	if lead:
		_build_front_face(car)
		_build_cab(car)
		_build_headlights(car)
		_build_salon_camera(car)
		_build_exterior_camera(car)
		_build_front_camera(car)
		_build_face_camera(car)

func _build_end(car: Node3D, z: float) -> void:
	_box(car, Vector3(2.5, ROOF - 0.14 - FLOOR, 0.08), Vector3(0, (FLOOR + ROOF - 0.14) * 0.5, z), _ext)
	_box(car, Vector3(0.85, 1.7, 0.04), Vector3(0, FLOOR + 0.85, z), _dark)   # дверь перехода

func _side_segments(half: float, platform: bool) -> Array:
	# Интервалы борта вдоль z. На платформенной стороне вырезаны проёмы под двери
	# (dz=±2.6), поэтому борт строится тремя кусками; иначе — цельный борт.
	if not platform:
		return [[-half, half]]
	var hw := DOOR_W * 0.5
	return [[-half, -2.6 - hw], [-2.6 + hw, 2.6 - hw], [2.6 + hw, half]]

func _build_door(car: Node3D, sx: float, dz: float) -> void:
	# Двухстворчатая дверь: две створки сходятся по центру проёма (dz).
	# Створки платформенной (левой по ходу, sx<0) стороны запоминаются для
	# анимации — именно они открываются, когда поезд стоит у платформы.
	var y := (FLOOR + WIN_TOP) * 0.5 + 0.05
	var h := WIN_TOP - 0.15
	var leaf_w := DOOR_W * 0.5 - 0.02
	for s: float in [-1.0, 1.0]:
		var closed_z := dz + s * DOOR_W * 0.25
		var leaf := _box(car, Vector3(0.06, h, leaf_w), Vector3(sx * 1.01, y, closed_z), _door)
		if sx < 0.0:
			_doors.append({"node": leaf, "closed": closed_z, "open": closed_z + s * DOOR_SLIDE})

func _build_salon(car: Node3D, lead: bool) -> void:
	var front := -2.4 if lead else -HALF + 0.6   # у головного салон за кабиной
	var rear := HALF - 0.6
	var mid := (front + rear) * 0.5
	var length := rear - front
	# пол салона
	_box(car, Vector3(2.34, 0.06, length), Vector3(0, FLOOR + 0.03, mid), _floor)
	# продольные диваны по бортам (сегменты вне дверных проёмов на z=±2.6)
	var segs := [0.0, 4.1] if lead else [-4.1, 0.0, 4.1]
	for sx in [-0.95, 0.95]:
		for zc in segs:
			_bench(car, sx, zc)
			if randf() < 0.55:
				_rider(car, sx, zc)
	# поручни-стойки и надпоручень
	for zc in [-2.6, 0.0, 2.6]:
		for sx in [-0.5, 0.5]:
			if lead and zc < -1.0:
				continue
			_box(car, Vector3(0.05, ROOF - 0.3 - FLOOR, 0.05), Vector3(sx, (FLOOR + ROOF - 0.3) * 0.5, zc), _pole)
	for sx in [-0.62, 0.62]:
		_box(car, Vector3(0.04, 0.04, length), Vector3(sx, 1.95, mid), _pole)
	# плафон освещения + свет в салоне
	_box(car, Vector3(0.5, 0.05, length * 0.95), Vector3(0, ROOF - 0.22, mid), _glow)
	var o := OmniLight3D.new()
	o.position = Vector3(0, 2.3, mid)
	o.omni_range = 9.0
	o.light_energy = 1.7
	o.light_color = Color(1.0, 0.96, 0.88)
	o.shadow_enabled = false
	car.add_child(o)

func _bench(car: Node3D, sx: float, zc: float) -> void:
	_box(car, Vector3(0.42, 0.12, 1.9), Vector3(sx, FLOOR + 0.22, zc), _seat)          # сиденье
	_box(car, Vector3(0.09, 0.46, 1.9), Vector3(sx + signf(sx) * 0.18, FLOOR + 0.5, zc), _seat)  # спинка

func _rider(car: Node3D, sx: float, zc: float) -> void:
	# сидящий пассажир: спина у борта, ноги свисают к проходу (к меньшему |x|)
	var shirt := _people[randi() % _people.size()]
	_box(car, Vector3(0.40, 0.50, 0.26), Vector3(sx * 0.98, 1.12, zc), shirt)   # торс
	_box(car, Vector3(0.24, 0.26, 0.24), Vector3(sx * 0.98, 1.50, zc), _skinm)  # голова
	_box(car, Vector3(0.50, 0.16, 0.42), Vector3(sx * 0.72, 0.86, zc), shirt)   # бёдра
	_box(car, Vector3(0.15, 0.44, 0.15), Vector3(sx * 0.5, 0.56, zc - 0.12), _dark)  # голени
	_box(car, Vector3(0.15, 0.44, 0.15), Vector3(sx * 0.5, 0.56, zc + 0.12), _dark)

# --- передок головного вагона (морда Еж3) -----------------------------------

func _build_front_face(car: Node3D) -> void:
	# Характерная «морда» Еж3: два лобовых окна кабины, номерное табло между
	# ними, красная нижняя маска и две круглые фары. z=-HALF — передний торец.
	var z := -HALF + 0.1
	var win0 := 1.35            # низ лобовых окон
	var win1 := 2.35            # верх лобовых окон
	var top := ROOF - 0.14
	# красная нижняя маска
	_box(car, Vector3(2.5, win0 - FLOOR, 0.1), Vector3(0, (FLOOR + win0) * 0.5, z), _red)
	# надоконная перемычка (в цвет кузова)
	_box(car, Vector3(2.5, top - win1, 0.1), Vector3(0, (win1 + top) * 0.5, z), _ext)
	# два лобовых стекла
	var wy := (win0 + win1) * 0.5
	var wh := win1 - win0 - 0.08
	_box(car, Vector3(0.9, wh, 0.05), Vector3(-0.62, wy, z - 0.03), _glass)
	_box(car, Vector3(0.9, wh, 0.05), Vector3(0.62, wy, z - 0.03), _glass)
	# центральная стойка с номерным табло и боковые стойки
	_box(car, Vector3(0.42, win1 - win0, 0.12), Vector3(0, wy, z - 0.01), _ext)
	_box(car, Vector3(0.12, win1 - win0, 0.12), Vector3(-1.16, wy, z - 0.01), _ext)
	_box(car, Vector3(0.12, win1 - win0, 0.12), Vector3(1.16, wy, z - 0.01), _ext)
	# номерное табло — светящийся квадратик на центральной стойке
	var route := StandardMaterial3D.new()
	route.albedo_color = Color(0.95, 0.85, 0.45)
	route.emission_enabled = true
	route.emission = Color(1.0, 0.85, 0.4)
	route.emission_energy_multiplier = 2.2
	_box(car, Vector3(0.3, 0.22, 0.05), Vector3(0, win1 - 0.02, z - 0.05), route)

# --- кабина головного вагона ------------------------------------------------

func _build_cab(car: Node3D) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 74.0
	cam.position = Vector3(0, 1.5, CAB_Z)
	cam.rotation = Vector3(deg_to_rad(-6), 0, 0)  # слегка вниз — видно пульт
	car.add_child(cam)
	_cams[View.CAB] = cam

	var panel := StandardMaterial3D.new()
	panel.albedo_texture = load("res://assets/textures/cab_panel.png")
	panel.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	panel.roughness = 0.7

	var z := CAB_Z
	# корпус пульта машиниста
	_box(car, Vector3(2.4, 0.95, 0.9), Vector3(0, 0.72, z - 1.1), _dark)
	# наклонная приборная панель
	_box(car, Vector3(2.2, 0.05, 0.6), Vector3(0, 1.18, z - 1.22), panel, Vector3(deg_to_rad(-38), 0, 0))
	# рукоятка контроллера (справа)
	_box(car, Vector3(0.12, 0.34, 0.12), Vector3(0.7, 1.3, z - 0.95), _dark, Vector3(deg_to_rad(-15), 0, 0))
	# индикатор-«спидометр» (слева)
	var gauge := StandardMaterial3D.new()
	gauge.albedo_color = Color(0.2, 0.7, 0.9)
	gauge.emission_enabled = true
	gauge.emission = Color(0.1, 0.4, 0.55)
	_box(car, Vector3(0.24, 0.24, 0.05), Vector3(-0.7, 1.24, z - 1.05), gauge, Vector3(deg_to_rad(-38), 0, 0))
	# стойки и перекладина лобового стекла
	_box(car, Vector3(0.16, 1.6, 0.16), Vector3(-1.1, 1.9, z - 1.35), _dark)
	_box(car, Vector3(0.16, 1.6, 0.16), Vector3(1.1, 1.9, z - 1.35), _dark)
	_box(car, Vector3(2.3, 0.22, 0.16), Vector3(0, 2.55, z - 1.35), _dark)
	# перегородка за спиной машиниста (отделяет кабину от салона), с дверью
	_box(car, Vector3(2.4, ROOF - 0.14 - FLOOR, 0.07), Vector3(0, (FLOOR + ROOF - 0.14) * 0.5, z + 0.9), _dark)
	_box(car, Vector3(0.8, 1.7, 0.03), Vector3(0.55, FLOOR + 0.85, z + 0.9), _floor)

# --- камера в салоне --------------------------------------------------------

func _build_salon_camera(car: Node3D) -> void:
	# У переднего края салона (сразу за перегородкой кабины), смотрит вдоль
	# прохода к хвосту состава: видно сиденья, поручни, окна и плафоны.
	var cam := Camera3D.new()
	cam.name = "SalonCamera"
	cam.current = false
	cam.fov = 80.0
	cam.position = Vector3(0.0, 1.68, CAB_Z + 1.6)  # чуть позади перегородки кабины
	cam.rotation = Vector3(deg_to_rad(-3), deg_to_rad(180), 0)  # взгляд в сторону хвоста
	car.add_child(cam)
	_cams[View.SALON] = cam

# --- внешние камеры ---------------------------------------------------------

func _build_exterior_camera(car: Node3D) -> void:
	# Снаружи: позади хвоста, сбоку и выше уровня крыши, смотрит вперёд вдоль
	# состава (обзор всего поезда в тоннеле). Крепится к головному вагону —
	# едет вместе с поездом, хвост тянется к ней в +Z локального пространства.
	var cam := Camera3D.new()
	cam.name = "ExteriorCamera"
	cam.current = false
	cam.fov = 70.0
	cam.position = Vector3(1.8, 3.1, 46.0)              # позади хвоста, сбоку, выше крыши
	cam.rotation = Vector3(deg_to_rad(-6), deg_to_rad(7), 0)  # чуть вниз и внутрь — 3/4 обзор
	car.add_child(cam)
	_cams[View.EXTERIOR] = cam

func _build_front_camera(car: Node3D) -> void:
	# Railfan-вид: камера на носу головного вагона, смотрит вперёд по ходу —
	# убегающий тоннель, рельсы и освещённый фарами путь (как «трейнспоттинг»
	# из передней точки поезда). Направление движения — локальный -Z.
	var cam := Camera3D.new()
	cam.name = "FrontCamera"
	cam.current = false
	cam.fov = 74.0
	var nose := -HALF + 0.05
	cam.position = Vector3(0.0, 1.55, nose - 0.5)      # чуть впереди носа, на уровне окон
	cam.rotation = Vector3(deg_to_rad(-4), 0, 0)       # взгляд вперёд, слегка вниз на путь
	car.add_child(cam)
	_cams[View.FRONT] = cam

func _build_face_camera(car: Node3D) -> void:
	# Снаружи впереди и чуть сбоку — обзор «морды» головного вагона в три
	# четверти (лобовые окна, номерное табло, фары). Наведена на нос вагона.
	var cam := Camera3D.new()
	cam.name = "FaceCamera"
	cam.current = false
	cam.fov = 58.0
	cam.position = Vector3(3.0, 2.1, -HALF - 8.5)       # впереди носа и сбоку
	car.add_child(cam)
	cam.look_at(Vector3(0.0, 1.35, -HALF + 0.1), Vector3.UP)  # прицел на морду
	_cams[View.FACE] = cam

## Делает активной камеру выбранного вида (индекс из View).
func set_view(v: int) -> void:
	for i in _cams.size():
		if _cams[i] != null:
			_cams[i].current = (i == v)

# --- фары --------------------------------------------------------------------

func _build_headlights(car: Node3D) -> void:
	var nose := -HALF + 0.05
	for x in [-0.85, 0.85]:
		var s := SpotLight3D.new()
		s.position = Vector3(x, 0.9, nose)
		s.spot_range = 90.0
		s.spot_angle = 46.0
		s.spot_attenuation = 0.9
		s.light_energy = 12.0
		s.light_color = Color(1.0, 0.95, 0.85)
		s.rotation.x = deg_to_rad(-3)   # чуть вниз — освещает путь и стены
		s.shadow_enabled = false
		car.add_child(s)
		# светящиеся «стёкла» фар
		var bulb := StandardMaterial3D.new()
		bulb.albedo_color = Color(1.0, 0.97, 0.85)
		bulb.emission_enabled = true
		bulb.emission = Color(1.0, 0.95, 0.8)
		bulb.emission_energy_multiplier = 3.0
		_box(car, Vector3(0.28, 0.2, 0.08), Vector3(x, 0.9, nose - 0.02), bulb)
