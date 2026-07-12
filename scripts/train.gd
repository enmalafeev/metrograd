extends Node3D
## Поезд метро: кинематика движения + камера и интерьер кабины.
## Движется по замкнутой кривой маршрута (world.get_curve()) по дистанции progress.
## Разворот на конечных заложен в саму кривую (петли), поэтому поезд всегда едет
## "вперёд" — направление меняет геометрия пути, а не сам поезд.

const MAX_SPEED := 16.0   # м/с (~58 км/ч)
const REVERSE_MAX := 3.0
const ACCEL := 2.8        # м/с² при полной тяге
const BRAKE := 5.5        # м/с² при полном торможении
const ROLL := 0.5         # сопротивление на выбеге

var speed := 0.0
var throttle := 0.0       # -1..1: + тяга, - тормоз
var doors_open := false
var progress := 0.0       # дистанция вдоль кривой, м

var _curve: Curve3D
var _len := 0.0

func _ready() -> void:
	_build_cab()
	_build_headlights()

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
	var p := _curve.sample_baked(progress)
	var ahead := _curve.sample_baked(fposmod(progress + 0.6, _len))
	position = p
	if p.distance_to(ahead) > 0.001:
		look_at(ahead, Vector3.UP)

func speed_kmh() -> float:
	return absf(speed) * 3.6

# --- фары -------------------------------------------------------------------

func _build_headlights() -> void:
	# два прожектора на носу светят вперёд (-Z), освещая тоннель
	for x in [-0.85, 0.85]:
		var s := SpotLight3D.new()
		s.position = Vector3(x, 0.9, -1.7)
		s.spot_range = 90.0
		s.spot_angle = 46.0
		s.spot_attenuation = 0.9
		s.light_energy = 12.0
		s.light_color = Color(1.0, 0.95, 0.85)
		s.rotation.x = deg_to_rad(-3)   # чуть вниз — освещает путь и стены
		s.shadow_enabled = false
		add_child(s)
		# маленькие светящиеся «стёкла» фар
		var bulb := StandardMaterial3D.new()
		bulb.albedo_color = Color(1.0, 0.97, 0.85)
		bulb.emission_enabled = true
		bulb.emission = Color(1.0, 0.95, 0.8)
		bulb.emission_energy_multiplier = 3.0
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.28, 0.2, 0.08)
		mi.mesh = bm
		mi.material_override = bulb
		mi.position = Vector3(x, 0.9, -1.72)
		add_child(mi)

# --- кабина -----------------------------------------------------------------

func _build_cab() -> void:
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.fov = 74.0
	cam.position = Vector3(0, 1.5, 0)
	cam.rotation = Vector3(deg_to_rad(-6), 0, 0)  # слегка вниз — видно пульт
	add_child(cam)

	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.14, 0.16)
	dark.roughness = 0.8

	var panel := StandardMaterial3D.new()
	panel.albedo_texture = load("res://assets/textures/cab_panel.png")
	panel.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	panel.roughness = 0.7

	# корпус пульта машиниста
	_cab_box(Vector3(2.9, 0.95, 0.9), Vector3(0, 0.72, -0.9), Vector3.ZERO, dark)
	# наклонная приборная панель, обращённая к машинисту
	_cab_box(Vector3(2.7, 0.05, 0.6), Vector3(0, 1.18, -1.02), Vector3(deg_to_rad(-38), 0, 0), panel)
	# рукоятка контроллера (деталь на пульте, справа)
	_cab_box(Vector3(0.12, 0.34, 0.12), Vector3(0.7, 1.3, -0.75), Vector3(deg_to_rad(-15), 0, 0), dark)
	# круглый индикатор-«спидометр» на панели (слева)
	var gauge := StandardMaterial3D.new()
	gauge.albedo_color = Color(0.2, 0.7, 0.9)
	gauge.emission_enabled = true
	gauge.emission = Color(0.1, 0.4, 0.55)
	_cab_box(Vector3(0.24, 0.24, 0.05), Vector3(-0.7, 1.24, -0.85), Vector3(deg_to_rad(-38), 0, 0), gauge)
	# стойки лобового стекла
	_cab_box(Vector3(0.16, 1.6, 0.16), Vector3(-1.25, 1.9, -1.15), Vector3.ZERO, dark)
	_cab_box(Vector3(0.16, 1.6, 0.16), Vector3(1.25, 1.9, -1.15), Vector3.ZERO, dark)
	# верхняя перекладина рамы
	_cab_box(Vector3(2.7, 0.22, 0.16), Vector3(0, 2.55, -1.15), Vector3.ZERO, dark)

func _cab_box(size: Vector3, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
