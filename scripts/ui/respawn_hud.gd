extends Control

signal respawn_requested

@onready var countdown_label: Label = $TopCenter/CountdownLabel
@onready var respawn_button: Button = $CenterButton/RespawnButton

var _remaining_seconds: float = 0.0

func _ready() -> void:
	hide()
	mouse_filter = Control.MOUSE_FILTER_STOP
	respawn_button.visible = false
	respawn_button.disabled = true
	if not respawn_button.pressed.is_connected(_on_respawn_button_pressed):
		respawn_button.pressed.connect(_on_respawn_button_pressed)

func show_countdown(seconds: float) -> void:
	_remaining_seconds = max(seconds, 0.0)
	show()
	_refresh_view()

func update_countdown(seconds_left: float) -> void:
	_remaining_seconds = max(seconds_left, 0.0)
	_refresh_view()

func set_respawn_ready(is_ready: bool) -> void:
	respawn_button.visible = is_ready
	respawn_button.disabled = not is_ready
	if is_ready:
		countdown_label.text = "Respawn ready"
	else:
		_refresh_view()

func hide_hud() -> void:
	hide()
	respawn_button.visible = false
	respawn_button.disabled = true

func _refresh_view() -> void:
	if _remaining_seconds > 0.0:
		countdown_label.text = "Respawn in %d s" % int(ceil(_remaining_seconds))
		respawn_button.visible = false
		respawn_button.disabled = true
	else:
		countdown_label.text = "Respawn ready"
		respawn_button.visible = true
		respawn_button.disabled = false

func _on_respawn_button_pressed() -> void:
	respawn_requested.emit()
