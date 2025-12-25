extends SpringArm3D

@export var mouse_sensitivity: float = 0.005
@export var lerp_speed: float = 12.0

@onready var camera: Camera3D = $Camera3D
signal aim_toggled(is_aiming: bool)

var target_height: float
var target_length: float
var target_h_offset: float
var target_fov: float

var mouse_yaw: float = 0.0
var mouse_pitch: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Ensure the SpringArm ignores the player's collision body
	add_excluded_object(get_parent().get_rid())
	reset_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity = mouse_sensitivity * (camera.fov / 90.0)  # fit sens to fov

		mouse_yaw -= event.relative.x * sensitivity
		mouse_pitch -= event.relative.y * sensitivity
		mouse_pitch = clamp(mouse_pitch, -PI/3, PI/4)

	if event.is_action_pressed("aim"):
		set_camera_goals(1.5, 0, 0.0, 30.0)
		aim_toggled.emit(true)
	elif event.is_action_released("aim"):
		reset_camera()
		aim_toggled.emit(false)

func reset_camera() -> void:
	set_camera_goals(2.0, 2.5, 0.6, 90.0)

func set_camera_goals(height: float, length: float, h_offset: float, fov: float) -> void:
	target_height = height
	target_length = length
	target_h_offset = h_offset
	target_fov = fov

func _process(delta: float) -> void:
	# 1. APPLY ROTATION
	rotation.x = lerp_angle(rotation.x, mouse_pitch, delta * 25.0)
	rotation.y = lerp_angle(rotation.y, mouse_yaw, delta * 25.0)
	
	# 2. APPLY TRANSFORMATIONS
	position.y = lerp(position.y, target_height, delta * lerp_speed)
	spring_length = lerp(spring_length, target_length, delta * lerp_speed)
	
	# 3. CAMERA OFFSET & FOV
	camera.h_offset = lerp(camera.h_offset, target_h_offset, delta * lerp_speed)
	camera.fov = lerp(camera.fov, target_fov, delta * lerp_speed)
