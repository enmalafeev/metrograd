extends Control
## Вертикальный рычаг контроллера машиниста.
## Вверх — тяга (0..+1), вниз — тормоз (0..-1), отпустил — нейтраль (выбег).
## Работает и на тач-экране, и мышью.

var value := 0.0
var _dragging := false

func _ready() -> void:
	custom_minimum_size = Vector2(96, 300)
	size = custom_minimum_size

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_dragging = true
			_set_from_y(event.position.y)
		else:
			_dragging = false
			value = 0.0            # пружина в нейтраль
			queue_redraw()
	elif _dragging and (event is InputEventScreenDrag or event is InputEventMouseMotion):
		_set_from_y(event.position.y)

func _set_from_y(y: float) -> void:
	var center := size.y * 0.5
	value = clampf((center - y) / center, -1.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	# корпус слайдера
	draw_rect(Rect2(w * 0.32, 0, w * 0.36, h), Color(0.08, 0.09, 0.11))
	# зона тяги (верх) и торможения (низ)
	draw_rect(Rect2(w * 0.32, 0, w * 0.36, h * 0.5), Color(0.12, 0.45, 0.18, 0.55))
	draw_rect(Rect2(w * 0.32, h * 0.5, w * 0.36, h * 0.5), Color(0.55, 0.16, 0.13, 0.55))
	# центральная риска (нейтраль)
	draw_rect(Rect2(w * 0.2, h * 0.5 - 2, w * 0.6, 4), Color(0.9, 0.9, 0.5))
	# рукоятка
	var ky := (h * 0.5) - value * (h * 0.5)
	draw_rect(Rect2(w * 0.08, ky - 16, w * 0.84, 32), Color(0.85, 0.86, 0.92))
	draw_rect(Rect2(w * 0.08, ky - 3, w * 0.84, 6), Color(0.2, 0.2, 0.24))
