extends CharacterBody3D

@onready var visuals = $Character  # Character Model
@onready var camera_arm = $SpringArm3D
@onready var camera = $SpringArm3D/Camera3D

# --- Movement Settings ---
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 12.0
@export var acceleration: float = 30.0
@export var friction: float = 100.0     # decel
@export var rotation_speed: float = 20.0

# --- Direction Penaly Settings ---
@export var backward_speed_mult: float = 0.5
@export var strafe_speed_mult: float = 0.8
var is_sprinting: bool = false
var is_aiming: bool = false

# --- Jump Fatigue Settings ---
@export var base_jump_velocity: float = 8.0
@export var speed_jump_bonus: float = 0.4    # Speed * bonus = extra jump height
@export var fatigue_cooldown: float = 0.3    # Seconds on ground until jump height is fully restored
@export var min_jump_percent: float = 0.4    # Minimum jump height

# --- Equipment ---
@onready var equipment := $EquipmentPivot
@onready var bullet_cast := $EquipmentPivot/Hand/Gun/RayCast3D	

var can_shoot: bool = true
@onready var fire_rate := $Firerate
signal firing(is_firing: bool)

@export var ads_speed_mult: float = 0.6 # 60% speed while aiming
@export var recoil_power: Vector2 = Vector2(2, 0.03)

# --- Animations ---
@onready var anim_player := $AnimationPlayer
@export var idle_time: float = 2.0
@export var muzzle_flash = preload("res://muzzle_flash.tscn")
@onready var flash_parent = $EquipmentPivot/Hand/Gun/MuzzleFlash

var floor_time: int = 0
var last_active_time: int = 0
var current_speed: float = 0.0

# --- Game ---
@export var max_health: float = 3.0
var health: float = max_health

func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func animate(type: String) -> void:
	if anim_player.current_animation == "shoot": # optimize later
		return
	match type:
		"move":
			if is_on_floor() and current_speed > walk_speed: anim_player.play("move")
			else: anim_player.play("RESET")
		"idle":
			if Time.get_ticks_msec() - last_active_time >  idle_time * 1000 and not is_aiming: anim_player.play("idle")
			else: anim_player.play("RESET")
		"shoot":
			anim_player.stop()
			anim_player.play("shoot")

func calculate_jump_velocity() -> float:
	var tslj = (Time.get_ticks_msec() - floor_time) / 1000.0
	floor_time = -1
	
	# A. Speed Bonus: Higher speed = higher jump
	var speed_factor = current_speed * speed_jump_bonus
	
	# B. Fatigue: Repeated jumps have reduce height
	# Clamps between min_jump_percent and 100%
	var fatigue_factor = clamp(tslj / fatigue_cooldown, min_jump_percent, 1.0)
	
	return (base_jump_velocity + speed_factor) * fatigue_factor

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	if Input.is_action_just_released("shoot"):
		firing.emit(false)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	
	# Check sprint state before movement logic
	is_sprinting = Input.is_action_pressed("sprint") and is_on_floor() and Input.get_vector("left", "right", "up", "down").y < 0
	
	# SPRINT CANCELS ADS
	if is_sprinting and is_aiming:
		camera_arm.stop_aim() # Force camera back to hip

	move(delta)

	if Input.is_action_pressed("shoot"): shoot()

	# Gun Look-At
	var target_pos = camera.global_transform.origin - camera.global_transform.basis.z * 100.0
	equipment.look_at(target_pos, Vector3.UP)

func move(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * 2.5 * delta

	var input_dir := Input.get_vector("left", "right", "up", "down")
	var speed_multiplier = 1.0
	
	# 1. Base Sprint/Walk speed
	var base_target_speed = sprint_speed if is_sprinting else walk_speed
	
	# 2. Apply ADS Penalty
	if is_aiming:
		base_target_speed *= ads_speed_mult

	# 3. Apply Directional Penalties (Backwards/Strafe)
	if input_dir.length() > 0:
		var dot = input_dir.normalized().dot(Vector2.UP) 
		if dot >= 0:
			speed_multiplier = lerp(strafe_speed_mult, 1.0, dot)
		else:
			speed_multiplier = lerp(strafe_speed_mult, backward_speed_mult, -dot)

	var target_speed = base_target_speed * speed_multiplier
	
	# Calculate Direction
	var forward = camera_arm.global_transform.basis.z
	var right = camera_arm.global_transform.basis.x
	forward.y = 0
	right.y = 0
	var direction = (forward * input_dir.y + right * input_dir.x).normalized()

	# Smoothed movement (Lerp Velocity)
	if direction:
		current_speed = move_toward(current_speed, target_speed, acceleration * delta)
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		current_speed = move_toward(current_speed, 0, friction * delta)
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)
	
	# 5. Handle Jumping

	if is_on_floor() and floor_time == -1:
		floor_time = Time.get_ticks_msec()

	if is_on_floor() and Input.is_action_pressed("jump"):
		velocity.y = calculate_jump_velocity() 
	
	# Visual Rotation and Animation
	handle_visuals(delta, direction)
	move_and_slide()

func handle_visuals(delta: float, direction: Vector3) -> void:
	var camera_yaw = camera_arm.rotation.y
	
	if direction.length() > 0.1:
		# 1. Calculate the angle the character WOULD face if they turned fully
		var movement_angle = atan2(-direction.x, -direction.z)
		
		# 2. Get the difference between where the camera is looking and the movement
		var angle_diff = angle_difference(camera_yaw, movement_angle)
		
		# 3. 1.0 = Forward, 0.0 = Strafe, -1.0 = Back
		var input_dir := Input.get_vector("left", "right", "up", "down")
		var forward_dot = input_dir.normalized().dot(Vector2.UP)
		
		# 4. Map the dot product to a rotation weight
		# Forward (1.0) -> 100% of the movement angle
		# Backward (-1.0) -> 30% of the movement angle
		var turn_weight = remap(forward_dot, -1.0, 1.0, 0.0, 1.0)
		
		# 5. Calculate final yaw: Start at camera look, add a weighted slice of the movement turn
		var target_visual_yaw = camera_yaw + (angle_diff * turn_weight)
		
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_visual_yaw, rotation_speed * delta)
		animate("move")
	else:
		# When standing still, always face the camera direction
		visuals.rotation.y = lerp_angle(visuals.rotation.y, camera_yaw, rotation_speed * delta)
		animate("idle")

func shoot() -> void:
	if not can_shoot: return
	can_shoot = false
	fire_rate.start()
	
	var kick = Vector2(recoil_power.x, randf_range(-recoil_power.y, recoil_power.y))
	camera_arm.apply_recoil(kick)
	
	fire_shot.rpc() # Visuals for the gun (muzzle flash)
	firing.emit(true)
	
	if bullet_cast.is_colliding():
		var hit_obj = bullet_cast.get_collider()
		var col_point = bullet_cast.get_collision_point()
		var normal = bullet_cast.get_collision_normal()
		
		var bullet_dir = (col_point - bullet_cast.global_position).normalized()
	
		if hit_obj.has_method("hurt"):
			hit_obj.hurt.rpc_id(hit_obj.get_multiplayer_authority(), 1.0)
			rpc("sync_impact", "enemy", col_point, normal, bullet_dir)
		else:
			rpc("sync_impact", "terrain", col_point, normal, bullet_dir)
			rpc("sync_impact", "decal", col_point, normal, bullet_dir)

@rpc("any_peer", "call_local")
func sync_impact(type: String, pos: Vector3, normal: Vector3, dir: Vector3):
	ImpactManager.spawn_impact(type, pos, normal, dir)

func _on_aim_toggled(aiming: bool) -> void:
	is_aiming = aiming
	if aiming: visuals.hide()
	else: visuals.show()

@rpc("call_local")
func fire_shot() -> void:
	animate("shoot")
	last_active_time = Time.get_ticks_msec()
	var flash = muzzle_flash.instantiate()
	flash_parent.add_child(flash)
	flash.global_transform = flash_parent.global_transform
	
	flash.emitting = true

@rpc("any_peer")
func hurt(damage: float):
	health -= damage
	if health <= 0:
		health = max_health
		position = Vector3.ZERO # fix later

func _ready() -> void:
	if not is_multiplayer_authority(): return
	camera.current = true
	floor_snap_length = 0.5
	apply_floor_snap()

	# Connect to the camera's signal
	camera_arm.aim_toggled.connect(_on_aim_toggled)

func _on_firerate_timeout() -> void:
	can_shoot = true
