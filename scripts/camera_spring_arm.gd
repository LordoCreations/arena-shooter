extends SpringArm3D

@export var mouse_sensitivity: float = 0.005
@export var lerp_speed: float = 12.0
@export var min_pitch: float = -PI / 3
@export var max_pitch: float = PI / 4

# --- Recoil Settings ---
@export var recoil_recovery: float = 10.0
@export var recoil_snap: float = 5.0
@export var recoil_persistent_ratio: float = 0.25

@onready var camera: Camera3D = $Camera3D
signal aim_toggled(is_aiming: bool)

var target_height: float
var target_length: float
var target_h_offset: float
var target_fov: float

var mouse_yaw: float = 0.0
var mouse_pitch: float = 0.0

# Recoil tracking
var recoil_rot: Vector2 = Vector2.ZERO        # Current actual recoil
var target_recoil_rot: Vector2 = Vector2.ZERO # The "goal" recoil point

var is_aiming_state: bool = false

func _ready() -> void:
	if not is_multiplayer_authority(): return
	add_excluded_object(get_parent().get_rid())
	reset_camera()

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	if not MultiplayerManager.controls_enabled: return
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity = mouse_sensitivity * (camera.fov / 90.0)
		
		mouse_yaw -= event.relative.x * sensitivity
		mouse_pitch -= event.relative.y * sensitivity
		mouse_pitch = clamp(mouse_pitch, min_pitch, max_pitch)

	if event.is_action_pressed("aim"):
		var player_node := get_parent()
		if player_node and bool(player_node.get("is_sprinting")):
			if player_node.has_method("cancel_sprint_for_ads"):
				player_node.call("cancel_sprint_for_ads")
			else:
				player_node.set("is_sprinting", false)
		start_aim()
	elif event.is_action_released("aim"):
		stop_aim()

func start_aim():
	is_aiming_state = true
	set_camera_goals(1.5, 0, 0.0, _get_ads_fov())
	aim_toggled.emit(true)

func _get_ads_fov() -> float:
	var player_node = get_parent()
	if player_node and player_node.get("weapon_manager"):
		var wm = player_node.get("weapon_manager")
		if wm and wm.current_weapon:
			return wm.current_weapon.ads_fov
	return 50.0

func stop_aim():
	is_aiming_state = false
	reset_camera()
	snap_to_camera_goals()
	aim_toggled.emit(false)

func reset_camera() -> void:
	set_camera_goals(2.0, 2.5, 0.6, 90.0)

func set_camera_goals(height: float, length: float, h_offset: float, fov: float) -> void:
	target_height = height
	target_length = length
	target_h_offset = h_offset
	target_fov = fov

func snap_to_camera_goals() -> void:
	position.y = target_height
	spring_length = target_length
	camera.h_offset = target_h_offset
	camera.fov = target_fov

func apply_recoil(amount: Vector2):
	# Reduced the exponent to 1.0 or 2.0 so ADS recoil isn't too weak
	var fov_mult = 0.5 if is_aiming_state else 1.0
	var scaled_kick = amount * fov_mult

	# Keep a portion of recoil as permanent view drift so it does not fully recover.
	var persistent_kick = scaled_kick * recoil_persistent_ratio
	mouse_pitch = clamp(mouse_pitch + persistent_kick.x, min_pitch, max_pitch)
	mouse_yaw += persistent_kick.y

	# Remaining kick is temporary recoil that decays over time.
	var transient_kick = scaled_kick - persistent_kick
	var pitch_min_offset = min_pitch - mouse_pitch
	var pitch_max_offset = max_pitch - mouse_pitch
	target_recoil_rot.x = clamp(target_recoil_rot.x + transient_kick.x, pitch_min_offset, pitch_max_offset)
	target_recoil_rot.y += transient_kick.y

func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return

	# 1. RECOIL LOGIC
	# target_recoil_rot is the "peak" of the kick
	# recoil_rot is the current camera position

	# Return the target to zero
	target_recoil_rot = lerp(target_recoil_rot, Vector2.ZERO, delta * recoil_recovery)

	# Move the camera toward the target (The Snap)
	recoil_rot = lerp(recoil_rot, target_recoil_rot, delta * recoil_snap)

	# 2. APPLY ROTATION
	var target_pitch = clamp(mouse_pitch + recoil_rot.x, min_pitch, max_pitch)
	rotation.x = lerp_angle(rotation.x, target_pitch, delta * 25.0)
	rotation.y = lerp_angle(rotation.y, mouse_yaw + recoil_rot.y, delta * 25.0)
	
	
	# 3. TRANSFORMATIONS
	position.y = lerp(position.y, target_height, delta * lerp_speed)
	spring_length = lerp(spring_length, target_length, delta * lerp_speed)
	camera.h_offset = lerp(camera.h_offset, target_h_offset, delta * lerp_speed)
	camera.fov = lerp(camera.fov, target_fov, delta * lerp_speed)
