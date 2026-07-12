extends Control
## Дискретный контроллер машиниста (реверсор с фиксированными позициями).
##
## Рукоятка щёлкает по фиксированным позициям и ОСТАЁТСЯ на выбранной —
## держать кнопку мыши не нужно. Клик/тап по слайдеру переводит рукоятку
## в ближайшую позицию; можно и протянуть. main.gd читает поле value.
##   Ход-1..3 → тяга (0..+1), 0 → выбег (нейтраль), Тормоз-1..3 → торможение (0..-1).

# позиции сверху вниз: 3 хода, нейтраль, 3 тормоза
const NOTCHES := [1.0, 2.0 / 3.0, 1.0 / 3.0, 0.0, -1.0 / 3.0, -2.0 / 3.0, -1.0]
const LABELS := ["Х3", "Х2", "Х1", "0", "Т1", "Т2", "Т3"]
const NEUTRAL := 3       # индекс нейтрали
const PAD := 26.0        # отступ сверху/снизу до крайних позиций

var value := 0.0
var _index := NEUTRAL

func _ready() -> void:
	custom_minimum_size = Vector2(132, 320)
	size = custom_minimum_size

func _gui_input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed:
		_set_from_y(event.position.y)
	elif event is InputEventScreenDrag:
		_set_from_y(event.position.y)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_set_from_y(event.position.y)

func _set_from_y(y: float) -> void:
	var usable := size.y - PAD * 2.0
	var t := clampf((y - PAD) / usable, 0.0, 1.0)   # 0 — верх, 1 — низ
	var idx := clampi(roundi(t * (NOTCHES.size() - 1)), 0, NOTCHES.size() - 1)
	if idx != _index:
		_index = idx
		value = NOTCHES[_index]
		queue_redraw()

func _notch_y(i: int) -> float:
	var usable := size.y - PAD * 2.0
	return PAD + usable * float(i) / float(NOTCHES.size() - 1)

func _draw() -> void:
	var w := size.x
	var top := _notch_y(0)
	var bot := _notch_y(NOTCHES.size() - 1)
	var midy := _notch_y(NEUTRAL)
	# корпус слайдера
	draw_rect(Rect2(w * 0.30, top - 10, w * 0.34, bot - top + 20), Color(0.08, 0.09, 0.11))
	# зона тяги (сверху) и торможения (снизу)
	draw_rect(Rect2(w * 0.30, top - 10, w * 0.34, midy - (top - 10)), Color(0.12, 0.45, 0.18, 0.5))
	draw_rect(Rect2(w * 0.30, midy, w * 0.34, (bot + 10) - midy), Color(0.55, 0.16, 0.13, 0.5))
	# риски позиций и подписи
	var font := ThemeDB.fallback_font
	for i in NOTCHES.size():
		var y := _notch_y(i)
		var on := i == _index
		var neutral := i == NEUTRAL
		var tick := Color(0.95, 0.9, 0.4) if neutral else Color(0.5, 0.52, 0.58)
		draw_rect(Rect2(w * 0.2, y - 1.5, w * 0.24, 3), tick)
		draw_rect(Rect2(w * 0.56, y - 1.5, w * 0.24, 3), tick)
		var col := Color(1.0, 0.95, 0.6) if on else Color(0.7, 0.72, 0.78)
		draw_string(font, Vector2(w * 0.82, y + 5), LABELS[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	# рукоятка на текущей позиции
	var ky := _notch_y(_index)
	draw_rect(Rect2(w * 0.12, ky - 13, w * 0.64, 26), Color(0.85, 0.86, 0.92))
	draw_rect(Rect2(w * 0.12, ky - 3, w * 0.64, 6), Color(0.2, 0.2, 0.24))
