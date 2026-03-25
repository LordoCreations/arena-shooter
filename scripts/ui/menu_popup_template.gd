class_name MenuPopupTemplate
extends Control

signal confirmed
signal cancelled

var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _restore_mouse_mode_on_close := false

@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Title
@onready var message_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TextBox/MarginContainer/Message
@onready var primary_button: Button = $PanelContainer/MarginContainer/VBoxContainer/Buttons/PrimaryButton
@onready var secondary_button: Button = $PanelContainer/MarginContainer/VBoxContainer/Buttons/SecondaryButton

func _ready() -> void:
	hide()
	primary_button.pressed.connect(_on_primary_pressed)
	secondary_button.pressed.connect(_on_secondary_pressed)

func open_popup(title_text: String, message_text: String, primary_text: String = "OK", secondary_text: String = "") -> void:
	_previous_mouse_mode = Input.mouse_mode
	_restore_mouse_mode_on_close = _previous_mouse_mode != Input.MOUSE_MODE_VISIBLE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	z_as_relative = false
	z_index = 1000
	move_to_front()
	mouse_filter = Control.MOUSE_FILTER_STOP

	title_label.text = title_text
	message_label.text = message_text
	primary_button.text = primary_text
	if secondary_text.is_empty():
		secondary_button.hide()
	else:
		secondary_button.show()
		secondary_button.text = secondary_text
	show()
	primary_button.grab_focus()

func set_message_text(message_text: String) -> void:
	message_label.text = message_text

func close_popup() -> void:
	hide()
	if _restore_mouse_mode_on_close:
		Input.mouse_mode = _previous_mouse_mode
	_restore_mouse_mode_on_close = false

func _on_primary_pressed() -> void:
	confirmed.emit()

func _on_secondary_pressed() -> void:
	cancelled.emit()
