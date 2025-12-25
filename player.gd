extends CharacterBody3D

@onready var visuals = $Character  # Character Model
@onready var camera_arm = $SpringArm3D
@onready var camera = $SpringArm3D/Camera3D

# --- Movement Settings ---
@export var walk_speed: float = 8.0
@export var sprint_speed: float = 10.0
@export var acceleration: float = 15.0
@export var friction: float = 60.0     # decel
@export var rotation_speed: float = 10.0

# --- Direction Penaly Settings ---
@export var backward_speed_mult: float = 0.5
@export var strafe_speed_mult: float = 0.8

# --- Jump Fatigue Settings ---
@export var base_jump_velocity: float = 6.0
@export var speed_jump_bonus: float = 0.4    # Speed * bonus = extra jump height
@export var fatigue_cooldown: float = 0.3    # Seconds on ground until jump height is fully restored
@export var min_jump_percent: float = 0.4    # Minimum jump height

# --- Equipment ---
@onready var equipment = $EquipmentPivot

var floor_time: int = 0
var current_speed: float = 0.0

func _physics_process(delta: float) -> void:
	# 1. Handle Gravity
	if not is_on_floor():
		velocity += get_gravity() * 2.5 * delta

	# 3. Get Input and Calculate Direction relative to Camera
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var speed_multiplier = 1.0
	
	# 3ai. Speed Penalties
	if input_dir.length() > 0:
		var dot = input_dir.normalized().dot(Vector2.UP) 

		# 1.0 (Forward) -> Multiplier 1.0
		# 0.0 (Strafe)  -> Multiplier strafe_speed_mult
		# -1.0 (Back)   -> Multiplier backward_speed_mult
		if dot >= 0:
			speed_multiplier = lerp(strafe_speed_mult, 1.0, dot)
		else:
			speed_multiplier = lerp(strafe_speed_mult, backward_speed_mult, -dot)

	# 3aii. Determine Base Target Speed
	var is_sprinting = Input.is_action_pressed("sprint")
	var base_target_speed = sprint_speed if is_sprinting else walk_speed

	# 3aiii. Apply the multiplier to the target speed
	var target_speed = base_target_speed * speed_multiplier
	
	var forward = camera_arm.global_transform.basis.z
	var right = camera_arm.global_transform.basis.x
	forward.y = 0
	right.y = 0
	
	# speed is always same in any direction
	var direction = (forward * input_dir.y + right * input_dir.x).normalized()

	# 4. smoothed movement
	if direction:
		# Gradually increase speed toward target
		current_speed = move_toward(current_speed, target_speed, acceleration * delta)
		
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
	else:
		# Gradually decelerate
		current_speed = move_toward(current_speed, 0, friction * delta)
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)
	
	var camera_yaw = camera_arm.rotation.y

	if direction.length() > 0.1:
		var movement_angle = atan2(-direction.x, -direction.z)
		var diff = angle_difference(camera_yaw, movement_angle)

		var camera_forward = -camera_arm.global_transform.basis.z
		camera_forward.y = 0
		camera_forward = camera_forward.normalized()
		var forward_dot = direction.dot(camera_forward)
		
		# Moving Forward (1.0) -> lean_factor is 1.0
		# Strafing (0.0)       -> lean_factor is 0.5
		# Moving Backward (-1) -> lean_factor is 0.0 (No jitter!)
		var lean_factor = remap(forward_dot, -1.0, 1.0, 0.0, 1.0)

		var base_lean = 0.5
		var target_visual_yaw = camera_yaw + (diff * base_lean * lean_factor)

		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_visual_yaw, rotation_speed * delta)
	else:
		visuals.rotation.y = lerp_angle(visuals.rotation.y, camera_yaw, rotation_speed * delta)

	# 5. Handle Jumping
	if is_on_floor and floor_time == -1:
		floor_time = Time.get_ticks_msec()
	
	if is_on_floor() and Input.is_action_pressed("jump"):
		velocity.y = calculate_jump_velocity()
	move_and_slide()
	
	# CRITICAL handle gun movement
	var target_pos = camera.global_transform.origin - camera.global_transform.basis.z * 100.0
	# Vector3.UP keeps the gun from twisting sideways
	equipment.look_at(target_pos, Vector3.UP)

func calculate_jump_velocity() -> float:
	var tslj = (Time.get_ticks_msec() - floor_time) / 1000.0
	floor_time = -1
	
	# A. Speed Bonus: Higher speed = higher jump
	var speed_factor = current_speed * speed_jump_bonus
	
	# B. Fatigue: Repeated jumps have reduce height
	# Clamps between min_jump_percent and 100%
	var fatigue_factor = clamp(tslj / fatigue_cooldown, min_jump_percent, 1.0)
	
	return (base_jump_velocity + speed_factor) * fatigue_factor


func _ready():
	floor_snap_length = 0.5
	apply_floor_snap()

	# Connect to the camera's signal
	camera_arm.aim_toggled.connect(_on_aim_toggled)

# This function runs whenever the player presses or releases 'aim'
func _on_aim_toggled(is_aiming: bool) -> void:
	if is_aiming:
		visuals.hide() # Hides the character model
	else:
		visuals.show() # Shows the character model
