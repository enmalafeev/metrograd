extends Node
## Корень демо: вывод 3D-мира на экран, HUD, управление и логика маршрута.

const STOP_TOL := 8.0    # допуск точной остановки у центра платформы, м
const PLAT_TOL := 14.0   # в пределах платформы, но не по центру
const DWELL := 1.5       # задержка "посадка пассажиров" перед закрытием дверей

@onready var world: Node3D = $World3D/World
@onready var train: Node3D = $World3D/Train
@onready var screen: TextureRect = $HUD/Screen

var lever: Control
var speed_label: Label
var station_label: Label
var hint_label: Label
var doors_button: Button

var next_idx := 1        # индекс следующей станции (старт на «Восточной» = 0)
var doors_open := false
var dwell_ok := true     # можно ли уже закрыть двери

func _ready() -> void:
	screen.texture = $World3D.get_texture()
	_build_hud()
	_update_hud()

func _process(_delta: float) -> void:
	var t: float = lever.value
	if Input.is_action_pressed("throttle_up"):
		t = 1.0
	elif Input.is_action_pressed("throttle_down"):
		t = -1.0
	train.throttle = t
	train.doors_open = doors_open
	if Input.is_action_just_pressed("doors"):
		_toggle_doors()
	_update_hud()

# --- двери / прибытие -------------------------------------------------------

func _aligned() -> bool:
	if next_idx >= world.stations.size():
		return false
	var d: float = absf(train.position.z - world.station_z(next_idx))
	return d <= STOP_TOL and absf(train.speed) < 0.15

func _toggle_doors() -> void:
	if not doors_open:
		if _aligned():
			doors_open = true
			dwell_ok = false
			get_tree().create_timer(DWELL).timeout.connect(func() -> void: dwell_ok = true)
	elif dwell_ok:
		doors_open = false
		next_idx += 1   # едем к следующей станции

# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	speed_label = _label(64, Color(1, 1, 1))
	speed_label.position = Vector2(36, 24)
	$HUD.add_child(speed_label)

	station_label = _label(30, Color(0.8, 0.92, 1.0))
	station_label.position = Vector2(360, 34)
	station_label.size = Vector2(560, 40)
	station_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$HUD.add_child(station_label)

	hint_label = _label(28, Color(1.0, 0.92, 0.6))
	hint_label.position = Vector2(240, 640)
	hint_label.size = Vector2(800, 50)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$HUD.add_child(hint_label)

	lever = preload("res://scripts/cab_controls.gd").new()
	lever.position = Vector2(1150, 200)
	$HUD.add_child(lever)

	doors_button = Button.new()
	doors_button.text = "ДВЕРИ"
	doors_button.position = Vector2(44, 590)
	doors_button.size = Vector2(170, 96)
	doors_button.add_theme_font_size_override("font_size", 30)
	doors_button.pressed.connect(_toggle_doors)
	$HUD.add_child(doors_button)

func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _update_hud() -> void:
	speed_label.text = "%d км/ч" % roundi(train.speed_kmh())
	var stopped: bool = absf(train.speed) < 0.15

	if next_idx >= world.stations.size():
		station_label.text = "Конечная станция"
		hint_label.text = "Маршрут завершён"
		doors_button.disabled = not doors_open
		return

	var st_name: String = str(world.stations[next_idx]["name"])
	station_label.text = "Следующая: " + st_name
	# положительное значение = станция впереди
	var remaining: float = train.position.z - world.station_z(next_idx)

	if doors_open:
		hint_label.text = "Двери открыты — посадка…" if not dwell_ok else "Двери открыты — нажмите «ДВЕРИ» чтобы закрыть"
	elif stopped:
		var d: float = absf(remaining)
		if d <= STOP_TOL:
			hint_label.text = "Прибыли на «%s». Откройте двери" % st_name
		elif d <= PLAT_TOL:
			hint_label.text = "Почти! Подъедьте к центру платформы"
		elif remaining > 0:
			hint_label.text = "Впереди %d м до станции" % roundi(remaining)
		else:
			hint_label.text = "Проехали станцию — сдайте назад (тормоз вниз)"
	else:
		hint_label.text = "%d м до «%s»" % [maxi(0, roundi(remaining)), st_name]

	doors_button.disabled = not (_aligned() or doors_open)
