extends Node3D
## Поезд метро: кинематика движения + камера и интерьер кабины.
## Едет вдоль -Z. throttle и doors_open выставляются извне (main.gd).

const MAX_SPEED := 16.0   # м/с (~58 км/ч)
const REVERSE_MAX := 3.0
const ACCEL := 2.8        # м/с² при полной тяге
const BRAKE := 5.5        # м/с² при полном торможении
const ROLL := 0.5         # сопротивление на выбеге

var speed := 0.0
var throttle := 0.0       # -1..1: + тяга, - тормоз
var doors_open := false

func _ready() -> void:
	_build_cab()

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
	position.z -= speed * delta

func speed_kmh() -> float:
	return absf(speed) * 3.6

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
