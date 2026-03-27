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
@onready var reserve_ammo_label = $SpringArm3D/Camera3D/HUD/AmmoContainer/ReserveAmmoLabel
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
@export var world_fall_kill_y: float = -45.0

var _loot_prompt_label: Label
const LOOT_INTERACT_DISTANCE := 2.4
const LOOT_PUSH_DISTANCE := 3.2
const LOOT_PLAYER_PUSH_SCALE := 4.0
@export var interact_hold_duration_seconds: float = 0.5

var _interact_hold_progress: float = 0.0
var _interact_hold_target: Node = null
var _is_interact_holding: bool = false
var _next_loot_push_time_ms: int = 0

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

	if event.is_action_released("interact"):
		_reset_interact_hold_state()

func _try_interact_loot_box(collider_node: Node = null) -> void:
	if collider_node == null:
		collider_node = _find_nearby_loot_box(false, LOOT_INTERACT_DISTANCE)
	if collider_node == null:
		return

	var authority_id := collider_node.get_multiplayer_authority()
	if authority_id == multiplayer.get_unique_id() and collider_node.has_method("interact_from_peer"):
		collider_node.call("interact_from_peer", multiplayer.get_unique_id())
	elif authority_id > 0:
		collider_node.rpc_id(authority_id, "request_interact")


func _find_nearby_loot_box(require_pushable: bool = false, max_distance: float = LOOT_INTERACT_DISTANCE) -> Node:
	if get_tree() == null:
		return null
	var loot_nodes := get_tree().get_nodes_in_group("loot_boxes")
	var closest_loot: Node = null
	var closest_distance: float = INF
	for loot_node in loot_nodes:
		if not (loot_node is Node):
			continue
		var collider_node := loot_node as Node
		if not collider_node.has_method("request_interact"):
			continue
		if not (collider_node is Node3D):
			continue
		if require_pushable:
			var pushable_value = collider_node.get("pushable")
			if typeof(pushable_value) != TYPE_BOOL or not bool(pushable_value):
				continue

		var allowed_distance := max_distance
		if not require_pushable:
			var interact_value = collider_node.get("interaction_distance")
			if typeof(interact_value) == TYPE_FLOAT or typeof(interact_value) == TYPE_INT:
				allowed_distance = max(allowed_distance, float(interact_value))

		var loot_position := (collider_node as Node3D).global_position
		var delta := loot_position - global_position
		var horizontal_distance := Vector2(delta.x, delta.z).length()
		if horizontal_distance > allowed_distance:
			continue
		if abs(delta.y) > 2.5:
			continue

		if horizontal_distance < closest_distance:
			closest_distance = horizontal_distance
			closest_loot = collider_node

	return closest_loot

func _reset_interact_hold_state() -> void:
	_interact_hold_progress = 0.0
	_interact_hold_target = null
	_is_interact_holding = false

func _update_interact_hold(delta: float) -> void:
	if not is_multiplayer_authority() or not MultiplayerManager.controls_enabled:
		_reset_interact_hold_state()
		return

	if not Input.is_action_pressed("interact"):
		_reset_interact_hold_state()
		return

	var nearby_loot := _find_nearby_loot_box(false, LOOT_INTERACT_DISTANCE)
	if nearby_loot == null:
		_reset_interact_hold_state()
		return

	_is_interact_holding = true
	if _interact_hold_target != nearby_loot:
		_interact_hold_target = nearby_loot
		_interact_hold_progress = 0.0

	var hold_duration: float = max(interact_hold_duration_seconds, 0.01)
	_interact_hold_progress = clamp(_interact_hold_progress + (delta / hold_duration), 0.0, 1.0)
	if _interact_hold_progress >= 1.0:
		_try_interact_loot_box(_interact_hold_target)
		_interact_hold_progress = 0.0

func should_show_interact_hold_indicator() -> bool:
	return _is_interact_holding and _interact_hold_target != null

func get_interact_hold_progress() -> float:
	return clamp(_interact_hold_progress, 0.0, 1.0)

func _create_loot_prompt() -> void:
	if hud == null:
		return
	if _loot_prompt_label and is_instance_valid(_loot_prompt_label):
		return

	_loot_prompt_label = Label.new()
	_loot_prompt_label.name = "LootPrompt"
	_loot_prompt_label.anchor_left = 0.5
	_loot_prompt_label.anchor_right = 0.5
	_loot_prompt_label.anchor_top = 1.0
	_loot_prompt_label.anchor_bottom = 1.0
	_loot_prompt_label.offset_left = -240.0
	_loot_prompt_label.offset_right = 240.0
	_loot_prompt_label.offset_top = -138.0
	_loot_prompt_label.offset_bottom = -84.0
	_loot_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loot_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loot_prompt_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
	_loot_prompt_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_loot_prompt_label.add_theme_constant_override("outline_size", 2)
	_loot_prompt_label.add_theme_font_size_override("font_size", 28)
	_loot_prompt_label.visible = false
	hud.add_child(_loot_prompt_label)

func _update_loot_prompt() -> void:
	if not is_multiplayer_authority():
		return
	if _loot_prompt_label == null or not is_instance_valid(_loot_prompt_label):
		return
	if not MultiplayerManager.controls_enabled:
		_loot_prompt_label.visible = false
		return

	var loot_node := _find_nearby_loot_box()
	if loot_node == null:
		_loot_prompt_label.visible = false
		return

	var loot_type_value = loot_node.get("loot_type")
	var loot_name := "Loot"
	if typeof(loot_type_value) == TYPE_INT:
		if int(loot_type_value) == 0:
			loot_name = "Ammo"
		elif int(loot_type_value) == 1:
			loot_name = "Gun"

	_loot_prompt_label.text = "Hold [E] to open %s" % loot_name
	_loot_prompt_label.visible = true

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		update_nameplate_visibility()
		_apply_animation_state(network_is_sprinting, network_anim_blend)
		return

	if global_position.y <= world_fall_kill_y:
		_kill_from_world_fall()
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
	_update_interact_hold(delta)

	_update_hud_health_visuals()
	_update_damage_bar_visuals()
	_update_ammo_display()
	_update_loot_prompt()

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
	_handle_loot_push_collisions()

func _handle_loot_push_collisions() -> void:
	if not is_multiplayer_authority():
		return
	if not MultiplayerManager.controls_enabled:
		return
	if Time.get_ticks_msec() < _next_loot_push_time_ms:
		return

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed <= 0.2:
		return

	var collider_node := _find_nearby_loot_box(true, LOOT_PUSH_DISTANCE)
	if collider_node == null or not (collider_node is Node3D):
		return

	var push_direction := Vector3(velocity.x, 0.0, velocity.z)
	if push_direction.is_zero_approx():
		return

	var strength_scale: float = clamp(horizontal_speed / LOOT_PLAYER_PUSH_SCALE, 0.25, 2.5)
	var authority_id := collider_node.get_multiplayer_authority()
	var hit_position := (collider_node as Node3D).global_position + Vector3.UP * 0.2
	var max_push_speed: float = horizontal_speed
	_next_loot_push_time_ms = Time.get_ticks_msec() + 55

	if authority_id == multiplayer.get_unique_id() and collider_node.has_method("apply_player_push"):
		collider_node.call("apply_player_push", hit_position, push_direction, strength_scale, max_push_speed)
	elif authority_id > 0:
		collider_node.rpc_id(authority_id, "request_player_push", hit_position, push_direction, strength_scale, max_push_speed)

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
		if reserve_ammo_label:
			reserve_ammo_label.text = ""
		return
	if not weapon_manager or not weapon_manager.current_weapon:
		ammo_label.text = "--/--"
		if reserve_ammo_label:
			reserve_ammo_label.text = "--"
		return

	var weapon = weapon_manager.current_weapon
	ammo_label.text = str(max(weapon.current_ammo, 0)) + "/" + str(max(weapon.magazine_capacity, 0))
	if reserve_ammo_label:
		reserve_ammo_label.text = str(max(weapon.reserve_ammo, 0))

func give_full_reserve_ammo_local() -> void:
	if not is_multiplayer_authority():
		return
	if weapon_manager and weapon_manager.has_method("refill_current_weapon_reserve_to_max"):
		weapon_manager.refill_current_weapon_reserve_to_max()
	_update_ammo_display()

@rpc("any_peer", "call_remote", "reliable")
func give_full_reserve_ammo() -> void:
	give_full_reserve_ammo_local()

func equip_weapon_full_from_path_local(weapon_resource_path: String) -> void:
	if not is_multiplayer_authority():
		return
	if weapon_resource_path == "":
		return
	if not ResourceLoader.exists(weapon_resource_path):
		return
	var weapon_resource = load(weapon_resource_path)
	if not (weapon_resource is WeaponResource):
		return
	if weapon_manager and weapon_manager.has_method("equip_weapon_template"):
		weapon_manager.equip_weapon_template(weapon_resource, true)
	_update_ammo_display()

@rpc("any_peer", "call_remote", "reliable")
func equip_weapon_full_from_path(weapon_resource_path: String) -> void:
	equip_weapon_full_from_path_local(weapon_resource_path)

func _kill_from_world_fall() -> void:
	health = 0.0
	hide()
	spawn()

func _get_spawn_zone_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var world := get_tree().current_scene
	if world == null:
		return positions

	var zones_root := world.get_node_or_null("SpawnZones")
	if zones_root == null:
		return positions

	for child in zones_root.get_children():
		if child is Node3D:
			positions.append((child as Node3D).global_position)
	return positions

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
	_create_loot_prompt()
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
	var spawn_positions := _get_spawn_zone_positions()
	if spawn_positions.is_empty():
		position = MultiplayerManager.respawn_point
	else:
		global_position = spawn_positions[randi() % spawn_positions.size()]
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
