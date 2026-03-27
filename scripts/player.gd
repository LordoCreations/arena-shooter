extends CharacterBody3D

@onready var visuals = $Character  # Character Model
@onready var camera_arm = $SpringArm3D
@onready var camera = $SpringArm3D/Camera3D

# --- Movement Settings ---
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 12.0
@export var acceleration: float = 30.0
@export var friction: float = 100.0     # decel
@export var air_resistance: float = 0.01
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
@export var min_jump_percent: float = 0.8    # Minimum jump height

var floor_time: int = 0
var current_speed: float = 0.0

# --- Equipment ---
@onready var weapon_manager := $WeaponManager
@onready var equipment := $EquipmentPivot

signal firing(is_firing: bool)

@export var ads_speed_mult: float = 0.6 # 60% speed while aiming

# --- Health ---
@export var max_health: float = 100.0
var health: float = max_health

# --- Animations ---
@onready var animation_tree : AnimationTree = $Character/Container/AnimationTree
@onready var state_machine_pb : AnimationNodeStateMachinePlayback = $Character/Container/AnimationTree.get("parameters/playback")
@export var idle_time: float = 2.0
@export var network_anim_blend: Vector2 = Vector2.ZERO
@export var network_is_sprinting: bool = false

# --- Game ---
@onready var spawn_loc = get_parent()
var player_id: int

# --- Multiplayer ---
var username = ""

# --- HUD ---
@onready var hud = $SpringArm3D/Camera3D/HUD
@onready var health_lag_bar = $SpringArm3D/Camera3D/HUD/HealthContainer/HealthLagBar
@onready var health_bar = $SpringArm3D/Camera3D/HUD/HealthContainer/HealthBar
@onready var health_text_label = $SpringArm3D/Camera3D/HUD/HealthContainer/HealthValueLabel
@onready var ammo_label = $SpringArm3D/Camera3D/HUD/AmmoContainer/AmmoLabel
@onready var hud_hit_flash = $SpringArm3D/Camera3D/HUD/HitFlash
@onready var username_tag = $Username
@onready var damage_bar_root = $DamageBarRoot
@onready var damage_bar_fill = $DamageBarRoot/Fill
@onready var damage_bar_lag = $DamageBarRoot/DamageLag
@onready var damage_bar_flash = $DamageBarRoot/HitFlash
@export var nameplate_visible_distance: float = 20.0
@export var damage_bar_visible_seconds: float = 4.0
@export var damage_lag_speed: float = 1.8
@export var enemy_damage_lag_speed: float = 1.8
@export var enemy_damage_lag_hold_seconds: float = 0.05
@export var hit_flash_decay_speed: float = 3.6
@export var regen_delay_seconds: float = 6.0
@export var regen_percent_per_second: float = 0.03

var _damage_bar_visible_until_ms: int = 0
var _last_damage_time_ms: int = 0
var _hud_health_ratio: float = 1.0
var _hud_lag_ratio: float = 1.0
var _overhead_health_ratio: float = 1.0
var _overhead_lag_ratio: float = 1.0
var _overhead_lag_hold_until_ms: int = 0
var _hud_hit_flash_strength: float = 0.0
var _overhead_hit_flash_strength: float = 0.0

var _hud_fill_style: StyleBoxFlat
var _overhead_fill_material: StandardMaterial3D
var _overhead_lag_material: StandardMaterial3D
var _overhead_flash_material: StandardMaterial3D

const OVERHEAD_BAR_HALF_WIDTH := 0.6
const ENEMY_BAR_COLOR := Color(0.86, 0.18, 0.18, 1.0)


# Visibility
const VIEW_MODEL_LAYER = 9
const WORLD_MODEL_LAYER = 2
@onready var viewModel = $SpringArm3D/Camera3D/ViewModel
@onready var worldModel = $Character/Container/orange_astro/Armature/Skeleton3D/BoneAttachment3D/WorldModel

func _enter_tree() -> void:
	set_multiplayer_authority(str(name).to_int())

func animate() -> void:
	# TODO Jumping animations?
	var rel_vel = visuals.global_transform.basis.inverse() * ((self.velocity * Vector3(1, 0, 1)) / get_move_speed())
	var rel_vel_xz = Vector2(rel_vel.x, -rel_vel.z)
	network_anim_blend = rel_vel_xz
	network_is_sprinting = is_sprinting
	_apply_animation_state(network_is_sprinting, network_anim_blend)

func _apply_animation_state(sprinting: bool, blend: Vector2) -> void:
	if sprinting:
		state_machine_pb.travel("RunBlendSpace2D")
		animation_tree.set("parameters/RunBlendSpace2D/blend_position", blend)
	else:
		state_machine_pb.travel("WalkBlendSpace2D")
		animation_tree.set("parameters/WalkBlendSpace2D/blend_position", blend)

func calculate_jump_velocity() -> float:
	var tslj = (Time.get_ticks_msec() - floor_time) / 1000.0
	floor_time = -1
	
	# A. Speed Bonus: Higher speed = higher jump
	var speed_factor = current_speed * speed_jump_bonus
	
	# B. Fatigue: Repeated jumps have reduce height
	# Clamps between min_jump_percent and 100%
	var fatigue_factor = clamp(tslj / fatigue_cooldown + min_jump_percent, min_jump_percent, 1.0)
	
	return (base_jump_velocity + speed_factor) * fatigue_factor

func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority(): return
	if not MultiplayerManager.controls_enabled:
		weapon_manager.set_trigger_pressed(false)
		return

	if event.is_action_pressed("shoot"):
		weapon_manager.set_trigger_pressed(true)
	elif event.is_action_released("shoot"):
		weapon_manager.set_trigger_pressed(false)
		firing.emit(false)

	if event.is_action_pressed("reload"):
		weapon_manager.request_reload()

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		update_nameplate_visibility()
		_apply_animation_state(network_is_sprinting, network_anim_blend)
		return

	var controls_enabled = MultiplayerManager.controls_enabled
	
	# Check sprint state before movement logic
	is_sprinting = controls_enabled and Input.is_action_pressed("sprint") and is_on_floor() and Input.get_vector("left", "right", "up", "down").y < 0
	
	# SPRINT CANCELS ADS
	if is_sprinting and is_aiming:
		camera_arm.stop_aim() # Force camera back to hip
	if not controls_enabled and is_aiming:
		camera_arm.stop_aim()
	if not controls_enabled:
		weapon_manager.set_trigger_pressed(false)

	move(delta, controls_enabled)

	# Gun Look-At
	var target_pos = camera.global_transform.origin - camera.global_transform.basis.z * 100.0
	equipment.look_at(target_pos, Vector3.UP)

func _process(delta: float) -> void:
	if is_multiplayer_authority() and health > 0.0 and health < max_health:
		var seconds_since_damage = (Time.get_ticks_msec() - _last_damage_time_ms) / 1000.0
		if seconds_since_damage >= regen_delay_seconds:
			health = min(max_health, health + (max_health * regen_percent_per_second) * delta)
			_set_local_health_ratio(health / max_health)

	_hud_lag_ratio = move_toward(_hud_lag_ratio, _hud_health_ratio, damage_lag_speed * delta)
	if Time.get_ticks_msec() >= _overhead_lag_hold_until_ms:
		_overhead_lag_ratio = move_toward(_overhead_lag_ratio, _overhead_health_ratio, enemy_damage_lag_speed * delta)
	_hud_hit_flash_strength = move_toward(_hud_hit_flash_strength, 0.0, hit_flash_decay_speed * delta)
	_overhead_hit_flash_strength = move_toward(_overhead_hit_flash_strength, 0.0, hit_flash_decay_speed * delta)

	_update_hud_health_visuals()
	_update_damage_bar_visuals()
	_update_ammo_display()

func get_move_speed() -> float:
	return sprint_speed if is_sprinting else walk_speed;

func move(delta: float, allow_player_input: bool = true) -> void:
	if not is_on_floor():
		velocity += get_gravity() * 2.5 * delta

	var input_dir := Vector2.ZERO
	if allow_player_input:
		input_dir = Input.get_vector("left", "right", "up", "down")
	var speed_multiplier = 1.0
	
	# 1. Base Sprint/Walk speed
	var base_target_speed = get_move_speed()
	
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

	# Smoothly accelerate the horizontal velocity vector to avoid instant direction snaps.
	var horizontal_velocity = Vector2(velocity.x, velocity.z)
	if direction:
		var target_horizontal_velocity = Vector2(direction.x, direction.z) * target_speed
		horizontal_velocity = horizontal_velocity.move_toward(target_horizontal_velocity, acceleration * delta)
	else:
		var decel = air_resistance if not is_on_floor() else friction
		horizontal_velocity = horizontal_velocity.move_toward(Vector2.ZERO, decel * delta)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.y
	current_speed = horizontal_velocity.length()
	
	# 5. Handle Jumping

	if is_on_floor() and floor_time == -1:
		floor_time = Time.get_ticks_msec()

	if allow_player_input and is_on_floor() and Input.is_action_pressed("jump"):
		velocity.y = calculate_jump_velocity() 
	
	# Visual Rotation and Animation
	handle_visuals(delta)
	move_and_slide()

func handle_visuals(delta: float) -> void:
	var camera_yaw = camera_arm.rotation.y
	
	self.rotation.y = camera_arm.rotation.y
	visuals.rotation.y = lerp_angle(visuals.rotation.y, camera_yaw, rotation_speed * delta)

	animate()

func update_nameplate_visibility():
	# 1. Get the local player's camera
	var local_player = get_viewport().get_camera_3d()
	if not local_player:
		damage_bar_root.hide()
		return

	damage_bar_root.look_at(local_player.global_position, Vector3.UP, true)

	var dist = global_position.distance_to(local_player.global_position)

	# 2. Check Distance
	if dist > nameplate_visible_distance:
		username_tag.hide()
		damage_bar_root.hide()
		return

	# 3. Check Line of Sight (Raycast)
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		local_player.global_position, 
		global_position + Vector3(0, 1.5, 0) # Ray to the head area
	)
	# Exclude the local player's body from the raycast
	query.exclude = [local_player.get_parent().get_parent()] 

	var result = space_state.intersect_ray(query)

	# If the ray hits nothing, or hits THIS player, we have line of sight
	if result.is_empty() or result.collider == self:
		username_tag.show()
		_update_damage_bar_visibility(true)
	else:
		username_tag.hide()
		damage_bar_root.hide()

func _update_damage_bar_visibility(can_see_target: bool) -> void:
	if not can_see_target:
		damage_bar_root.hide()
		return
	if Time.get_ticks_msec() > _damage_bar_visible_until_ms:
		damage_bar_root.hide()
		return
	damage_bar_root.show()

func _set_damage_bar_ratio(ratio: float) -> void:
	var clamped_ratio = clamp(ratio, 0.0, 1.0)
	if clamped_ratio < _overhead_health_ratio:
		# Immediate health drop, white lag holds previous value then decays.
		_overhead_lag_ratio = max(_overhead_lag_ratio, _overhead_health_ratio)
		_overhead_lag_hold_until_ms = Time.get_ticks_msec() + int(enemy_damage_lag_hold_seconds * 1000.0)
	_overhead_health_ratio = clamped_ratio

func _set_damage_mesh_ratio(mesh: MeshInstance3D, ratio: float) -> void:
	var clamped_ratio = clamp(ratio, 0.0, 1.0)
	mesh.scale = Vector3(max(clamped_ratio, 0.001), 1.0, 1.0)
	# Keep the left edge fixed as the fill shrinks.
	mesh.position.x = -OVERHEAD_BAR_HALF_WIDTH * (1.0 - clamped_ratio)

func _hud_health_color_from_ratio(ratio: float) -> Color:
	var full_health = Color(0.0, 0.7172733, 0.3805772, 1.0)
	var low_health = Color(0.87, 0.13, 0.13, 1.0)
	var t = clamp(pow(1.0 - clamp(ratio, 0.0, 1.0), 0.8), 0.0, 1.0)
	return full_health.lerp(low_health, t)

func _enemy_health_color_from_ratio(_ratio: float) -> Color:
	# Enemy health bar stays a constant red tone.
	return ENEMY_BAR_COLOR

func _update_hud_health_visuals() -> void:
	health_bar.value = 100.0 * _hud_health_ratio
	health_lag_bar.value = 100.0 * _hud_lag_ratio
	var health_color = _hud_health_color_from_ratio(_hud_health_ratio)
	if _hud_fill_style:
		_hud_fill_style.bg_color = health_color

	if health_text_label:
		var current_health = int(round(clamp(health, 0.0, max_health)))
		var max_health_int = int(round(max_health))
		health_text_label.text = str(current_health) + "/" + str(max_health_int)
		health_text_label.add_theme_color_override("font_color", health_color)

	var bar_rect = health_bar.get_global_rect()
	var hud_rect = hud.get_global_rect()
	hud_hit_flash.position = bar_rect.position - hud_rect.position
	hud_hit_flash.size = bar_rect.size
	hud_hit_flash.modulate.a = 0.8 * _hud_hit_flash_strength

func _update_ammo_display() -> void:
	if not ammo_label:
		return
	if not is_multiplayer_authority():
		ammo_label.text = ""
		return
	if not weapon_manager or not weapon_manager.current_weapon:
		ammo_label.text = "--/--"
		return

	var weapon = weapon_manager.current_weapon
	ammo_label.text = str(max(weapon.current_ammo, 0)) + "/" + str(max(weapon.magazine_capacity, 0))

func _update_damage_bar_visuals() -> void:
	_set_damage_mesh_ratio(damage_bar_fill, _overhead_health_ratio)
	_set_damage_mesh_ratio(damage_bar_lag, _overhead_lag_ratio)
	if _overhead_fill_material:
		_overhead_fill_material.albedo_color = _enemy_health_color_from_ratio(_overhead_health_ratio)
	if _overhead_lag_material:
		var lag_gap = max(0.0, _overhead_lag_ratio - _overhead_health_ratio)
		var lag_alpha = clamp(lag_gap * 4.0, 0.0, 0.85)
		var lag_color = Color(1.0, 1.0, 1.0, lag_alpha)
		_overhead_lag_material.albedo_color = lag_color
	if _overhead_flash_material:
		_overhead_flash_material.albedo_color.a = 0.0

func _set_local_health_ratio(ratio: float) -> void:
	var clamped_ratio = clamp(ratio, 0.0, 1.0)
	if clamped_ratio < _hud_health_ratio:
		_hud_lag_ratio = max(_hud_lag_ratio, _hud_health_ratio)
	_hud_health_ratio = clamped_ratio

func update_view_and_world_model_masks():
	if is_multiplayer_authority():
		for child in %ViewModel.find_children("*", "VisualInstance3D", true, false):
			child.set_layer_mask_value(1, false)
			child.set_layer_mask_value(VIEW_MODEL_LAYER, true)
			if child is GeometryInstance3D:
				child.cast_shadow = false
		for child in %WorldModel.find_children("*", "VisualInstance3D", true, false):
			child.set_layer_mask_value(1, false)
			child.set_layer_mask_value(WORLD_MODEL_LAYER, true)
		camera.set_cull_mask_value(WORLD_MODEL_LAYER, true)
		camera.set_cull_mask_value(VIEW_MODEL_LAYER, false)
	else:
		%ViewModel.hide()
		%WorldModel.show()

func _on_aim_toggled(aiming: bool) -> void:
	is_aiming = aiming
	if aiming:
		camera.set_cull_mask_value(WORLD_MODEL_LAYER, false)
		camera.set_cull_mask_value(VIEW_MODEL_LAYER, true)
		visuals.hide()
	else:
		camera.set_cull_mask_value(WORLD_MODEL_LAYER, true)
		camera.set_cull_mask_value(VIEW_MODEL_LAYER, false)
		visuals.show()
@rpc("any_peer")
func hurt(damage: float):
	var attacker_peer_id = multiplayer.get_remote_sender_id()
	var prev_health = health
	health -= damage
	health = clamp(health, 0.0, max_health)
	_last_damage_time_ms = Time.get_ticks_msec()
	_set_local_health_ratio(health / max_health)
	if health < (max_health * 0.5) and health < prev_health:
		_hud_hit_flash_strength = 1.0
	if attacker_peer_id > 0 and attacker_peer_id != multiplayer.get_unique_id():
		_show_damage_to_attacker.rpc_id(attacker_peer_id, health / max_health)

	if health <= 0:
		hide()
		spawn()

@rpc("authority", "call_remote")
func _show_damage_to_attacker(health_ratio: float) -> void:
	_damage_bar_visible_until_ms = Time.get_ticks_msec() + int(damage_bar_visible_seconds * 1000.0)
	_set_damage_bar_ratio(health_ratio)
	damage_bar_root.show()

@rpc("authority", "call_remote")
func _clear_enemy_damage_bar() -> void:
	_damage_bar_visible_until_ms = 0
	_overhead_health_ratio = 1.0
	_overhead_lag_ratio = 1.0
	_overhead_lag_hold_until_ms = 0
	_overhead_hit_flash_strength = 0.0
	damage_bar_root.hide()
	

func _ready():
	update_view_and_world_model_masks()
	weapon_manager.update_weapon_model()


	if is_multiplayer_authority():
		username = MultiplayerManager.player_username
		username = username if username and len(username) > 0 else "Player " + str(player_id)
		username_tag.text = username
		username_tag.hide()

	var fill_style = health_bar.get("theme_override_styles/fill")
	if fill_style is StyleBoxFlat:
		_hud_fill_style = fill_style.duplicate()
		health_bar.add_theme_stylebox_override("fill", _hud_fill_style)

	var fill_material = damage_bar_fill.material_override
	if fill_material is StandardMaterial3D:
		_overhead_fill_material = fill_material.duplicate()
		damage_bar_fill.material_override = _overhead_fill_material

	var lag_material = damage_bar_lag.material_override
	if lag_material is StandardMaterial3D:
		_overhead_lag_material = lag_material.duplicate()
		damage_bar_lag.material_override = _overhead_lag_material

	# Prevent z-fighting so white lag remains visible against the red fill mesh.
	damage_bar_lag.position.z = -0.002

	var flash_material = damage_bar_flash.material_override
	if flash_material is StandardMaterial3D:
		_overhead_flash_material = flash_material.duplicate()
		damage_bar_flash.material_override = _overhead_flash_material


	if not is_multiplayer_authority():
		username_tag.show()
		damage_bar_root.hide()
		show()
		return
	
	hud.show()
	_update_ammo_display()
		
	camera.current = true
	floor_snap_length = 0.5
	apply_floor_snap()
	spawn()

	# Connect to the camera's signal
	camera_arm.aim_toggled.connect(_on_aim_toggled)

func spawn() -> void:
	health = max_health
	_last_damage_time_ms = Time.get_ticks_msec()
	show()
	position = MultiplayerManager.respawn_point
	_set_local_health_ratio(health / max_health)
	_hud_lag_ratio = _hud_health_ratio
	_damage_bar_visible_until_ms = 0
	_overhead_health_ratio = 1.0
	_overhead_lag_ratio = 1.0
	_overhead_lag_hold_until_ms = 0
	_overhead_hit_flash_strength = 0.0
	_hud_hit_flash_strength = 0.0
	_set_damage_bar_ratio(1.0)
	damage_bar_root.hide()
	_update_ammo_display()
	if is_multiplayer_authority():
		_clear_enemy_damage_bar.rpc()
