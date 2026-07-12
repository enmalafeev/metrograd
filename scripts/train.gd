extends Node3D
## Поезд метро из 4 вагонов с салоном: кинематика движения + кабина, фары, камера.
##
## Движется по замкнутой кривой маршрута (world.get_curve()) по дистанции progress,
## где progress — центр состава. Каждый вагон ставится на кривую отдельно (по своему
## смещению вдоль неё) и ориентируется по касательной, поэтому состав правильно
## изгибается на разворотных петлях. Головной вагон (0) несёт кабину, фары и камеру.

const MAX_SPEED := 16.0   # м/с (~58 км/ч)
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

var speed := 0.0
var throttle := 0.0       # -1..1: + тяга, - тормоз
var doors_open := false
var progress := 0.0       # дистанция центра состава вдоль кривой, м

var _curve: Curve3D
var _len := 0.0
var _cars: Array[Node3D] = []
var _cab_cam: Camera3D      # вид из кабины машиниста
var _salon_cam: Camera3D    # вид в салоне вагона

# --- материалы --------------------------------------------------------------
var _ext: StandardMaterial3D      # кузов
var _trim: StandardMaterial3D     # цветная полоса
var _glass: StandardMaterial3D    # окна
var _door: StandardMaterial3D     # двери
var _floor: StandardMaterial3D    # пол салона
var _seat: StandardMaterial3D     # сиденья
var _pole: StandardMaterial3D     # поручни
var _glow: StandardMaterial3D     # плафоны освещения
var _dark: StandardMaterial3D     # кабина / тёмные детали

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

# --- материалы --------------------------------------------------------------

func _init_materials() -> void:
	_ext = _flat(Color(0.62, 0.65, 0.72), 0.4, 0.35)
	_trim = _flat(Color(0.78, 0.16, 0.19), 0.2, 0.4)
	_door = _flat(Color(0.28, 0.32, 0.38), 0.3, 0.35)
	_floor = _flat(Color(0.17, 0.18, 0.21), 0.0, 0.9)
	_seat = _flat(Color(0.18, 0.34, 0.62), 0.0, 0.6)
	_pole = _flat(Color(0.86, 0.72, 0.24), 0.6, 0.3)
	_dark = _flat(Color(0.13, 0.14, 0.16), 0.0, 0.8)
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
		# цветная полоса по борту (снаружи, под окнами)
		_box(car, Vector3(0.06, 0.16, body_len), Vector3(sx * 1.03, WIN_BOT - 0.1, 0), _trim)
		# юбка под окнами
		_box(car, Vector3(0.08, WIN_BOT - FLOOR, body_len), Vector3(sx, (FLOOR + WIN_BOT) * 0.5, 0), _ext)
		# надоконный пояс
		_box(car, Vector3(0.08, ROOF - 0.14 - WIN_TOP, body_len), Vector3(sx, (WIN_TOP + ROOF - 0.14) * 0.5, 0), _ext)
		# оконная лента (стекло)
		_box(car, Vector3(0.05, WIN_TOP - WIN_BOT, body_len), Vector3(sx, (WIN_BOT + WIN_TOP) * 0.5, 0), _glass)
		# оконные стойки
		for mz in [-3.3, -1.1, 1.1, 3.3]:
			_box(car, Vector3(0.1, WIN_TOP - WIN_BOT, 0.12), Vector3(sx, (WIN_BOT + WIN_TOP) * 0.5, mz), _ext)
		# двери (по две с каждой стороны, у платформы)
		for dz in [-2.6, 2.6]:
			_box(car, Vector3(0.06, WIN_TOP - 0.15, 1.3), Vector3(sx * 1.01, (FLOOR + WIN_TOP) * 0.5 + 0.05, dz), _door)

	# торцы вагона с дверью в переход (у головного передний торец открыт под кабину)
	_build_end(car, HALF - 0.05)
	if not lead:
		_build_end(car, -HALF + 0.05)

	_build_salon(car, lead)

	if lead:
		_build_cab(car)
		_build_headlights(car)
		_build_salon_camera(car)

func _build_end(car: Node3D, z: float) -> void:
	_box(car, Vector3(2.5, ROOF - 0.14 - FLOOR, 0.08), Vector3(0, (FLOOR + ROOF - 0.14) * 0.5, z), _ext)
	_box(car, Vector3(0.85, 1.7, 0.04), Vector3(0, FLOOR + 0.85, z), _dark)   # дверь перехода

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

# --- кабина головного вагона ------------------------------------------------

func _build_cab(car: Node3D) -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 74.0
	cam.position = Vector3(0, 1.5, CAB_Z)
	cam.rotation = Vector3(deg_to_rad(-6), 0, 0)  # слегка вниз — видно пульт
	car.add_child(cam)
	_cab_cam = cam

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
	_salon_cam = cam

## Переключает активную камеру: true — салон, false — кабина.
func set_interior_view(on: bool) -> void:
	if _cab_cam == null or _salon_cam == null:
		return
	_salon_cam.current = on
	_cab_cam.current = not on

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
