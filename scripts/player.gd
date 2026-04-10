extends CharacterBody3D

@onready var visuals = $Character  # Character Model
@onready var camera_arm = $SpringArm3D
@onready var camera = $SpringArm3D/Camera3D
@onready var character_skeleton: Skeleton3D = $Character/Container/orange_astro/Armature/Skeleton3D
@onready var convergence_ray: RayCast3D = $SpringArm3D/Camera3D/Convergence
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

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
@export var network_equipped_weapon_path: String = "res://weapons/pistol/pistol.tres"
@export var network_world_model_forward: Vector3 = Vector3.FORWARD
@export var network_world_model_up: Vector3 = Vector3.UP
@export var network_is_dead: bool = false
var _last_applied_network_weapon_path: String = ""

# --- HUD ---
@onready var hud = $SpringArm3D/Camera3D/HUD
@onready var health_lag_bar = $SpringArm3D/Camera3D/HUD/HealthContainer/HealthLagBar
@onready var health_bar = $SpringArm3D/Camera3D/HUD/HealthContainer/HealthBar
@onready var health_text_label = $SpringArm3D/Camera3D/HUD/HealthContainer/HealthValueLabel
@onready var ammo_label = $SpringArm3D/Camera3D/HUD/AmmoContainer/AmmoLabel
@onready var reserve_ammo_label = $SpringArm3D/Camera3D/HUD/AmmoContainer/ReserveAmmoLabel
@onready var hud_hit_flash = $SpringArm3D/Camera3D/HUD/HitFlash
@onready var player_hud_overlay = $SpringArm3D/Camera3D/HUD/PlayerHudOverlay
@onready var respawn_hud = $SpringArm3D/Camera3D/HUD/RespawnHUD
@onready var crosshair = $SpringArm3D/Camera3D/Crosshair
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
@export var respawn_delay_seconds: float = 5.0
@export var death_particle_burst_count: int = 7
@export var death_particle_burst_radius: float = 0.35
@export var death_particle_height_offset: float = 1.1
@export var death_particle_upward_bias: float = 0.55
@export var ik_convergence_distance: float = 90.0
@export var ik_convergence_lerp_speed: float = 28.0
@export var ik_hands_forward_distance: float = 0.48
@export var ik_hands_vertical_offset: float = -0.02
@export var ik_hands_clasp_separation: float = 0.06
@export var ik_hands_centerline_offset: float = 0.065
@export var ik_hands_max_spread: float = 0.12
@export var ik_pitch_vertical_scale: float = 0.30
@export var ik_hands_max_vertical_offset: float = 0.35
@export var ik_upper_arm_outward_bias: float = 0.10
@export var ik_midline_guard_distance: float = 0.12
@export var ik_elbow_outward_bias: float = 1.50
@export var ik_elbow_down_bias: float = 1.05
@export var ik_elbow_forward_bias: float = 0.16
@export var ik_forearm_barrel_drop: float = 0.07
@export var ik_clasp_focus_forward_offset: float = 0.04
@export var ik_palm_clasp_forward_offset: float = 0.02
@export var ik_palm_clasp_bias: float = 0.82
@export var ik_close_hold_on_up_pitch: float = 0.08
@export var ik_elbow_drop_on_up_pitch: float = 0.45
@export var ik_hand_forearm_follow: float = 0.35
@export var ik_hand_roll_offset_degrees: float = 0.0
@export var ik_lock_gun_vertical: bool = true

var _loot_prompt_label: Label
const LOOT_INTERACT_DISTANCE := 2.4
@export var interact_hold_duration_seconds: float = 0.5

var _interact_hold_progress: float = 0.0
var _interact_hold_target: Node = null
var _is_interact_holding: bool = false
var _is_dead: bool = false
var _respawn_unlock_time_ms: int = 0
var _respawn_ready: bool = false
var _damage_bar_visible_until_ms: int = 0
var _last_damage_time_ms: int = 0
var _hud_health_ratio: float = 1.0
var _hud_lag_ratio: float = 1.0
var _overhead_health_ratio: float = 1.0
var _overhead_lag_ratio: float = 1.0
var _overhead_lag_hold_until_ms: int = 0
var _hud_hit_flash_strength: float = 0.0
var _overhead_hit_flash_strength: float = 0.0
var _arm_ik_blend: float = 0.0
var _ik_setup_complete: bool = false
var _ik_forward_sign: float = 1.0
var _right_upper_arm_bone_idx: int = -1
var _left_upper_arm_bone_idx: int = -1
var _right_hand_bone_idx: int = -1
var _left_hand_bone_idx: int = -1
var _right_arm_ik_modifier: Node = null
var _left_arm_ik_modifier: Node = null
var _right_ik_target: Node3D = null
var _left_ik_target: Node3D = null
var _right_ik_pole: Node3D = null
var _left_ik_pole: Node3D = null
var _right_hand_parallel_basis_offset: Basis = Basis.IDENTITY
var _ik_last_gun_model_id: int = 0
var _ik_cached_weapon_world_model_rot: Vector3 = Vector3.ZERO
var _ik_right_hand_to_gun_basis_offset: Basis = Basis.IDENTITY
var _ik_gun_basis_offset_ready: bool = false
var _right_hand_axis_map := {}
var _left_hand_axis_map := {}
var _parallel_hand_offset_ready: bool = false
var _parallel_hand_desired_basis: Basis = Basis.IDENTITY
var _parallel_hand_orientation_active: bool = false
var _ik_modifier_signal_connected: bool = false
var _ik_unavailable_warned: bool = false
var _ik_smoothed_convergence_distance: float = -1.0
var _ik_cached_aim_frame: int = -1
var _ik_cached_aim_target: Vector3 = Vector3.ZERO
var _active_health_pack_effects: Array[Dictionary] = []

var _hud_fill_style: StyleBoxFlat
var _overhead_fill_material: StandardMaterial3D
var _overhead_lag_material: StandardMaterial3D
var _overhead_flash_material: StandardMaterial3D

const OVERHEAD_BAR_HALF_WIDTH := 0.6
const ENEMY_BAR_COLOR := Color(0.86, 0.18, 0.18, 1.0)
const IK_EPSILON := 0.0001
const ENEMY_REMOTE_ALBEDO_TEXTURE: Texture2D = preload("res://assets/purple_astro_Image_0.jpg")
const RESPAWN_WEAPON_PATH := "res://weapons/pistol/pistol.tres"


# Visibility
const VIEW_MODEL_LAYER = 9
const WORLD_MODEL_LAYER = 2
@onready var viewModel = %ViewModel
@onready var worldModel = %WorldModel

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
	if _is_dead:
		weapon_manager.set_trigger_pressed(false)
		return
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
	if not is_multiplayer_authority() or not MultiplayerManager.controls_enabled or _is_dead:
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
	if _is_dead:
		_loot_prompt_label.visible = false
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
		elif int(loot_type_value) == 2:
			loot_name = "Health"

	_loot_prompt_label.text = "Hold [E] to open %s" % loot_name
	_loot_prompt_label.visible = true

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		_apply_remote_dead_state()
		if _is_dead:
			return
		update_nameplate_visibility()
		_apply_animation_state(network_is_sprinting, network_anim_blend)
		return

	if _is_dead:
		velocity = Vector3.ZERO
		weapon_manager.set_trigger_pressed(false)
		return

	if global_position.y <= world_fall_kill_y:
		_kill_from_world_fall()
		return

	var controls_enabled = MultiplayerManager.controls_enabled
	var sprint_pressed := Input.is_action_pressed("sprint")
	var sprint_just_pressed := Input.is_action_just_pressed("sprint")
	var can_start_sprint := controls_enabled and is_on_floor() and Input.get_vector("left", "right", "up", "down").y < 0

	if is_aiming:
		# Sprinting while ADS should drop ADS only when sprint input is newly pressed.
		if can_start_sprint and sprint_just_pressed:
			camera_arm.stop_aim()
			is_sprinting = true
		else:
			is_sprinting = false
	else:
		is_sprinting = can_start_sprint and sprint_pressed

	if not controls_enabled and is_aiming:
		camera_arm.stop_aim()
	if not controls_enabled:
		is_sprinting = false
		weapon_manager.set_trigger_pressed(false)

	move(delta, controls_enabled)

	# Gun Look-At
	var target_pos = camera.global_transform.origin - camera.global_transform.basis.z * 100.0
	equipment.look_at(target_pos, Vector3.UP)

func _process(delta: float) -> void:
	_update_respawn_hud()

	if is_multiplayer_authority() and not _is_dead:
		_update_health_pack_effects(delta)
		if health > 0.0 and health < max_health:
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
	if _is_dead:
		if is_multiplayer_authority():
			_update_ammo_display()
		return

	_sync_network_weapon_appearance()
	_update_ammo_display()
	_update_loot_prompt()
	_update_upper_body_ik(delta)

func _setup_upper_body_ik() -> void:
	_ik_setup_complete = false
	if character_skeleton == null:
		return
	if not ClassDB.class_exists("TwoBoneIK3D"):
		if not _ik_unavailable_warned:
			_ik_unavailable_warned = true
			push_warning("TwoBoneIK3D is unavailable. Use Godot 4.6+ to enable upper-body IK.")
		return

	_right_upper_arm_bone_idx = character_skeleton.find_bone("UpperArm.R")
	_left_upper_arm_bone_idx = character_skeleton.find_bone("UpperArm.L")
	_right_hand_bone_idx = character_skeleton.find_bone("Hand.R")
	_left_hand_bone_idx = character_skeleton.find_bone("Hand.L")
	var right_lower_arm_bone_idx := character_skeleton.find_bone("LowerArm.R")
	var left_lower_arm_bone_idx := character_skeleton.find_bone("LowerArm.L")
	if _right_upper_arm_bone_idx < 0 or _left_upper_arm_bone_idx < 0 or _right_hand_bone_idx < 0 or _left_hand_bone_idx < 0 or right_lower_arm_bone_idx < 0 or left_lower_arm_bone_idx < 0:
		return

	var right_end_bone_name := _resolve_arm_end_bone_name("Hand.R", "Hand.R_leaf", "LowerArm.R_leaf")
	var left_end_bone_name := _resolve_arm_end_bone_name("Hand.L", "Hand.L_leaf", "LowerArm.L_leaf")
	if right_end_bone_name == "" or left_end_bone_name == "":
		return

	_right_ik_target = _ensure_ik_anchor_node("IKRightHandTarget")
	_left_ik_target = _ensure_ik_anchor_node("IKLeftHandTarget")
	_right_ik_pole = _ensure_ik_anchor_node("IKRightElbowPole")
	_left_ik_pole = _ensure_ik_anchor_node("IKLeftElbowPole")

	_right_arm_ik_modifier = _ensure_two_bone_ik_modifier("IKRightArm")
	_left_arm_ik_modifier = _ensure_two_bone_ik_modifier("IKLeftArm")
	if _right_arm_ik_modifier == null or _left_arm_ik_modifier == null:
		return

	_configure_two_bone_ik_modifier(
		_right_arm_ik_modifier,
		"UpperArm.R",
		"LowerArm.R",
		right_end_bone_name,
		_right_ik_target,
		_right_ik_pole,
		Vector3.RIGHT
	)
	_configure_two_bone_ik_modifier(
		_left_arm_ik_modifier,
		"UpperArm.L",
		"LowerArm.L",
		left_end_bone_name,
		_left_ik_target,
		_left_ik_pole,
		Vector3.LEFT
	)
	_connect_parallel_hand_orientation_signal()
	_cache_parallel_hand_basis_offset()
	_refresh_ik_gun_basis_offset_if_needed()

	_detect_ik_forward_sign()
	_ik_setup_complete = true

func _resolve_arm_end_bone_name(primary_bone_name: String, fallback_bone_name: String, secondary_fallback_bone_name: String = "") -> String:
	if character_skeleton.find_bone(primary_bone_name) >= 0:
		return primary_bone_name
	if character_skeleton.find_bone(fallback_bone_name) >= 0:
		return fallback_bone_name
	if secondary_fallback_bone_name != "" and character_skeleton.find_bone(secondary_fallback_bone_name) >= 0:
		return secondary_fallback_bone_name
	return ""

func _ensure_ik_anchor_node(node_name: String) -> Node3D:
	var existing := character_skeleton.get_node_or_null(node_name)
	if existing is Node3D:
		return existing as Node3D
	if existing:
		existing.queue_free()

	var anchor := Node3D.new()
	anchor.name = node_name
	character_skeleton.add_child(anchor)
	return anchor

func _ensure_two_bone_ik_modifier(node_name: String) -> Node:
	var existing := character_skeleton.get_node_or_null(node_name)
	if existing and existing.get_class() == "TwoBoneIK3D":
		return existing
	if existing:
		existing.queue_free()

	var modifier_object: Object = ClassDB.instantiate("TwoBoneIK3D")
	if not (modifier_object is Node):
		return null
	var modifier := modifier_object as Node
	modifier.name = node_name
	character_skeleton.add_child(modifier)
	return modifier

func _configure_two_bone_ik_modifier(modifier: Node, root_bone_name: String, middle_bone_name: String, end_bone_name: String, target_node: Node3D, pole_node: Node3D, preferred_world_pole_dir: Vector3) -> void:
	modifier.call("set_setting_count", 1)
	modifier.call("set_root_bone_name", 0, root_bone_name)
	modifier.call("set_middle_bone_name", 0, middle_bone_name)
	modifier.call("set_end_bone_name", 0, end_bone_name)
	modifier.call("set_target_node", 0, modifier.get_path_to(target_node))
	modifier.call("set_pole_node", 0, modifier.get_path_to(pole_node))
	modifier.call("set_pole_direction", 0, SkeletonModifier3D.SECONDARY_DIRECTION_CUSTOM)
	modifier.call("set_pole_direction_vector", 0, _compute_middle_bone_local_pole_vector(middle_bone_name, preferred_world_pole_dir))
	modifier.set("active", true)
	modifier.set("influence", 1.0)
	if modifier.has_method("reset"):
		modifier.call("reset")

func _compute_middle_bone_local_pole_vector(middle_bone_name: String, preferred_world_pole_dir: Vector3) -> Vector3:
	var middle_bone_idx := character_skeleton.find_bone(middle_bone_name)
	if middle_bone_idx < 0:
		return Vector3.UP

	var world_direction := preferred_world_pole_dir.normalized()
	if world_direction.length_squared() <= IK_EPSILON:
		world_direction = Vector3.UP

	var middle_pose: Transform3D
	if character_skeleton.has_method("get_bone_global_rest"):
		middle_pose = character_skeleton.get_bone_global_rest(middle_bone_idx)
	else:
		middle_pose = character_skeleton.get_bone_global_pose_no_override(middle_bone_idx)

	var middle_world_basis := (character_skeleton.global_transform.basis * middle_pose.basis).orthonormalized()
	var local_direction: Vector3 = middle_world_basis.inverse() * world_direction
	if local_direction.length_squared() <= IK_EPSILON:
		return Vector3.UP
	return local_direction.normalized()

func _set_two_bone_ik_state(modifier: Node, enabled: bool, influence: float) -> void:
	if modifier == null:
		return
	modifier.set("active", enabled)
	modifier.set("influence", clampf(influence, 0.0, 1.0) if enabled else 0.0)

func _connect_parallel_hand_orientation_signal() -> void:
	if _ik_modifier_signal_connected or _left_arm_ik_modifier == null:
		return
	if not _left_arm_ik_modifier.has_signal("modification_processed"):
		return

	var callback: Callable = Callable(self, "_on_upper_body_ik_modification_processed")
	if _left_arm_ik_modifier.is_connected("modification_processed", callback):
		_ik_modifier_signal_connected = true
		return

	_left_arm_ik_modifier.connect("modification_processed", callback)
	_ik_modifier_signal_connected = true

func _cache_parallel_hand_basis_offset() -> void:
	_parallel_hand_offset_ready = false
	_right_hand_axis_map.clear()
	_left_hand_axis_map.clear()
	if character_skeleton == null or _right_hand_bone_idx < 0 or _left_hand_bone_idx < 0:
		return

	var visual_basis: Basis = visuals.global_transform.basis if visuals else global_transform.basis
	var model_up: Vector3 = visual_basis.y.normalized()
	var model_forward: Vector3 = -visual_basis.z.normalized()
	if model_forward.length_squared() <= IK_EPSILON:
		model_forward = Vector3.FORWARD

	var right_forward_ref: Vector3 = _get_hand_forward_reference_direction(_right_hand_bone_idx, "Hand.R_leaf", "LowerArm.R", model_forward)
	var left_forward_ref: Vector3 = _get_hand_forward_reference_direction(_left_hand_bone_idx, "Hand.L_leaf", "LowerArm.L", model_forward)
	_right_hand_axis_map = _compute_hand_orientation_axis_map(_right_hand_bone_idx, right_forward_ref, model_up)
	_left_hand_axis_map = _compute_hand_orientation_axis_map(_left_hand_bone_idx, left_forward_ref, model_up)

	# Keep orientation offset neutral; axis maps provide stable per-rig hand orientation.
	_right_hand_parallel_basis_offset = Basis.IDENTITY
	_parallel_hand_offset_ready = not _right_hand_axis_map.is_empty() and not _left_hand_axis_map.is_empty()

func _get_hand_forward_reference_direction(hand_bone_idx: int, leaf_bone_name: String, lower_bone_name: String, fallback_forward: Vector3) -> Vector3:
	var hand_pos: Vector3 = _get_bone_world_rest_position(hand_bone_idx)

	var leaf_idx := character_skeleton.find_bone(leaf_bone_name)
	if leaf_idx >= 0:
		var leaf_pos: Vector3 = _get_bone_world_rest_position(leaf_idx)
		var to_leaf: Vector3 = leaf_pos - hand_pos
		if to_leaf.length_squared() > IK_EPSILON:
			return to_leaf.normalized()

	var lower_idx := character_skeleton.find_bone(lower_bone_name)
	if lower_idx >= 0:
		var lower_pos: Vector3 = _get_bone_world_rest_position(lower_idx)
		var forearm_to_hand: Vector3 = hand_pos - lower_pos
		if forearm_to_hand.length_squared() > IK_EPSILON:
			return forearm_to_hand.normalized()

	if fallback_forward.length_squared() <= IK_EPSILON:
		return Vector3.FORWARD
	return fallback_forward.normalized()

func _compute_hand_orientation_axis_map(hand_bone_idx: int, forward_ref_world: Vector3, up_ref_world: Vector3) -> Dictionary:
	var hand_world_basis: Basis = _get_bone_world_rest_basis(hand_bone_idx)
	var forward_pick := _pick_basis_axis_for_direction(hand_world_basis, forward_ref_world, -1)
	var up_pick := _pick_basis_axis_for_direction(hand_world_basis, up_ref_world, int(forward_pick.get("idx", 2)))
	return {
		"forward_idx": int(forward_pick.get("idx", 2)),
		"forward_sign": float(forward_pick.get("sign", 1.0)),
		"up_idx": int(up_pick.get("idx", 1)),
		"up_sign": float(up_pick.get("sign", 1.0)),
	}

func _pick_basis_axis_for_direction(source_basis: Basis, direction: Vector3, excluded_axis: int = -1) -> Dictionary:
	var dir: Vector3 = direction
	if dir.length_squared() <= IK_EPSILON:
		dir = Vector3.FORWARD
	dir = dir.normalized()

	var axes := [source_basis.x.normalized(), source_basis.y.normalized(), source_basis.z.normalized()]
	var best_idx := 0
	var best_abs_dot := -1.0
	var best_sign := 1.0
	for i in range(3):
		if i == excluded_axis:
			continue
		var dot_val: float = axes[i].dot(dir)
		var abs_dot: float = absf(dot_val)
		if abs_dot > best_abs_dot:
			best_abs_dot = abs_dot
			best_idx = i
			best_sign = 1.0 if dot_val >= 0.0 else -1.0

	return {
		"idx": best_idx,
		"sign": best_sign,
	}

func _build_hand_basis_from_axis_map(axis_map: Dictionary, forward_dir: Vector3, up_dir: Vector3) -> Basis:
	if axis_map.is_empty():
		return _build_parallel_hand_aim_basis(forward_dir, Vector3.RIGHT, up_dir)

	var forward_idx := int(axis_map.get("forward_idx", 2))
	var forward_sign := float(axis_map.get("forward_sign", 1.0))
	var up_idx := int(axis_map.get("up_idx", 1))
	var up_sign := float(axis_map.get("up_sign", 1.0))

	var target_forward: Vector3 = forward_dir
	if target_forward.length_squared() <= IK_EPSILON:
		target_forward = Vector3.FORWARD
	target_forward = target_forward.normalized()

	var target_up: Vector3 = up_dir - (target_forward * up_dir.dot(target_forward))
	if target_up.length_squared() <= IK_EPSILON:
		target_up = Vector3.UP - (target_forward * Vector3.UP.dot(target_forward))
	if target_up.length_squared() <= IK_EPSILON:
		target_up = Vector3.RIGHT - (target_forward * Vector3.RIGHT.dot(target_forward))
	target_up = target_up.normalized()

	var axes := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	axes[forward_idx] = target_forward * forward_sign
	axes[up_idx] = target_up * up_sign

	var remaining_idx := 3 - forward_idx - up_idx
	if remaining_idx == 2:
		axes[2] = axes[0].cross(axes[1]).normalized()
	elif remaining_idx == 1:
		axes[1] = axes[2].cross(axes[0]).normalized()
	else:
		axes[0] = axes[1].cross(axes[2]).normalized()

	return Basis(axes[0], axes[1], axes[2]).orthonormalized()

func _build_parallel_hand_aim_basis(forward_hint: Vector3, lateral_hint: Vector3, up_hint: Vector3) -> Basis:
	var aim_forward: Vector3 = forward_hint
	if aim_forward.length_squared() <= IK_EPSILON:
		if camera:
			aim_forward = -camera.global_transform.basis.z
		elif visuals:
			aim_forward = -visuals.global_transform.basis.z
		else:
			aim_forward = -global_transform.basis.z
	if aim_forward.length_squared() <= IK_EPSILON:
		aim_forward = Vector3.FORWARD
	aim_forward = aim_forward.normalized()

	var visual_basis: Basis = visuals.global_transform.basis if visuals else global_transform.basis
	var aim_right: Vector3 = lateral_hint - (aim_forward * lateral_hint.dot(aim_forward))
	if aim_right.length_squared() <= IK_EPSILON:
		aim_right = visual_basis.x - (aim_forward * visual_basis.x.dot(aim_forward))
	if aim_right.length_squared() <= IK_EPSILON:
		var up_proj: Vector3 = up_hint - (aim_forward * up_hint.dot(aim_forward))
		if up_proj.length_squared() > IK_EPSILON:
			aim_right = up_proj.cross(aim_forward)
	if aim_right.length_squared() <= IK_EPSILON:
		aim_right = Vector3.RIGHT if absf(Vector3.RIGHT.dot(aim_forward)) < 0.98 else Vector3.FORWARD
	aim_right = aim_right.normalized()

	var aim_up: Vector3 = aim_forward.cross(aim_right)
	if aim_up.length_squared() <= IK_EPSILON:
		aim_up = Vector3.UP if absf(Vector3.UP.dot(aim_forward)) < 0.98 else Vector3.FORWARD
	aim_up = aim_up.normalized()
	# Keep a right-handed basis: x=right, y=up, z=-forward.
	aim_up = aim_right.cross(aim_forward).normalized()
	aim_right = aim_forward.cross(aim_up).normalized()

	return Basis(aim_right, aim_up, -aim_forward).orthonormalized()

func _on_upper_body_ik_modification_processed() -> void:
	if not _parallel_hand_orientation_active:
		return
	if _arm_ik_blend <= 0.001:
		return
	_apply_parallel_hand_orientation(_parallel_hand_desired_basis, _arm_ik_blend)

func _compute_forward_axis_roll_to_align_up(current_up: Vector3, desired_up: Vector3, forward_axis: Vector3) -> float:
	if forward_axis.length_squared() <= IK_EPSILON:
		return 0.0
	var axis: Vector3 = forward_axis.normalized()

	var current_proj: Vector3 = current_up - (axis * current_up.dot(axis))
	var desired_proj: Vector3 = desired_up - (axis * desired_up.dot(axis))
	if current_proj.length_squared() <= IK_EPSILON or desired_proj.length_squared() <= IK_EPSILON:
		return 0.0

	return current_proj.normalized().signed_angle_to(desired_proj.normalized(), axis)

func _refresh_ik_gun_basis_offset_if_needed() -> void:
	if not weapon_manager:
		_ik_last_gun_model_id = 0
		_ik_cached_weapon_world_model_rot = Vector3.ZERO
		_ik_gun_basis_offset_ready = false
		return

	var gun_model: Node3D = weapon_manager.current_world_model
	if gun_model == null or not is_instance_valid(gun_model):
		_ik_last_gun_model_id = 0
		_ik_cached_weapon_world_model_rot = Vector3.ZERO
		_ik_gun_basis_offset_ready = false
		return

	var current_weapon_rot: Vector3 = _get_weapon_world_model_rotation()
	var gun_model_id: int = gun_model.get_instance_id()
	if _ik_gun_basis_offset_ready and gun_model_id == _ik_last_gun_model_id and current_weapon_rot.is_equal_approx(_ik_cached_weapon_world_model_rot):
		return

	_ik_last_gun_model_id = gun_model_id
	_ik_cached_weapon_world_model_rot = current_weapon_rot
	_cache_ik_right_hand_to_gun_basis_offset(gun_model)

func _cache_ik_right_hand_to_gun_basis_offset(gun_model: Node3D) -> void:
	_ik_gun_basis_offset_ready = false
	if character_skeleton == null or _right_hand_bone_idx < 0:
		return

	var right_hand_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(_right_hand_bone_idx)
	var right_hand_world_basis: Basis = (character_skeleton.global_transform.basis * right_hand_pose.basis).orthonormalized()
	var gun_world_basis: Basis = gun_model.global_transform.basis.orthonormalized()
	if absf(right_hand_world_basis.determinant()) <= IK_EPSILON or absf(gun_world_basis.determinant()) <= IK_EPSILON:
		return

	_ik_right_hand_to_gun_basis_offset = (right_hand_world_basis.inverse() * gun_world_basis).orthonormalized()
	_ik_gun_basis_offset_ready = true

func _build_basis_from_forward_up(forward_dir: Vector3, up_hint: Vector3) -> Basis:
	var forward: Vector3 = forward_dir
	if forward.length_squared() <= IK_EPSILON:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	var up: Vector3 = up_hint - (forward * up_hint.dot(forward))
	if up.length_squared() <= IK_EPSILON:
		up = Vector3.UP - (forward * Vector3.UP.dot(forward))
	if up.length_squared() <= IK_EPSILON:
		up = Vector3.RIGHT - (forward * Vector3.RIGHT.dot(forward))
	up = up.normalized()

	var right: Vector3 = forward.cross(up)
	if right.length_squared() <= IK_EPSILON:
		right = Vector3.RIGHT if absf(Vector3.RIGHT.dot(forward)) < 0.98 else Vector3.FORWARD
	right = right.normalized()
	up = right.cross(forward).normalized()

	return Basis(right, up, -forward).orthonormalized()

func _get_locked_ik_forward(aim_basis: Basis) -> Vector3:
	var forward: Vector3 = -aim_basis.z
	var shot_origin: Vector3 = Vector3.ZERO
	var has_shot_origin: bool = false
	if weapon_manager and weapon_manager.bullet_cast and is_instance_valid(weapon_manager.bullet_cast):
		shot_origin = weapon_manager.bullet_cast.global_position
		has_shot_origin = true
	elif camera and is_instance_valid(camera):
		shot_origin = camera.global_position
		has_shot_origin = true

	if has_shot_origin:
		var shot_target: Vector3 = _get_ik_aim_target_world_position()
		var shot_dir: Vector3 = shot_target - shot_origin
		if shot_dir.length_squared() > IK_EPSILON:
			forward = shot_dir

	if forward.length_squared() <= IK_EPSILON and camera and is_instance_valid(camera):
		var camera_forward: Vector3 = -camera.global_transform.basis.z
		if camera_forward.length_squared() > IK_EPSILON:
			forward = camera_forward
	if forward.length_squared() <= IK_EPSILON:
		forward = Vector3.FORWARD
	return forward.normalized()

func _get_weapon_world_model_rotation() -> Vector3:
	if weapon_manager and weapon_manager.current_weapon:
		return weapon_manager.current_weapon.world_model_rot
	return Vector3.ZERO

func _apply_parallel_hand_orientation(aim_basis: Basis, influence: float) -> void:
	if character_skeleton == null or not character_skeleton.has_method("set_bone_global_pose_override"):
		return
	if _right_hand_bone_idx < 0 or _left_hand_bone_idx < 0:
		return
	if not _parallel_hand_offset_ready:
		_cache_parallel_hand_basis_offset()
	if not _parallel_hand_offset_ready:
		return
	_refresh_ik_gun_basis_offset_if_needed()

	var target_forward: Vector3 = _get_locked_ik_forward(aim_basis)
	var lock_up_hint: Vector3 = Vector3.UP if ik_lock_gun_vertical else aim_basis.y.normalized()
	var desired_gun_basis: Basis = _build_basis_from_forward_up(target_forward, lock_up_hint)
	var right_hand_basis: Basis
	var left_hand_basis: Basis
	if _ik_gun_basis_offset_ready:
		right_hand_basis = (desired_gun_basis * _ik_right_hand_to_gun_basis_offset.inverse()).orthonormalized()
		# Keep both hands in the same locked orientation so the grip stays parallel.
		left_hand_basis = right_hand_basis
	else:
		right_hand_basis = _build_hand_basis_from_axis_map(_right_hand_axis_map, target_forward, desired_gun_basis.y)
		var auto_roll_radians: float = _compute_forward_axis_roll_to_align_up(right_hand_basis.y, desired_gun_basis.y, target_forward)
		right_hand_basis = (Basis(target_forward, auto_roll_radians) * right_hand_basis).orthonormalized()
		left_hand_basis = right_hand_basis

	var roll_radians: float = 0.0 if ik_lock_gun_vertical else deg_to_rad(ik_hand_roll_offset_degrees)
	if absf(roll_radians) > IK_EPSILON:
		var roll_basis := Basis(target_forward, roll_radians)
		right_hand_basis = (roll_basis * right_hand_basis).orthonormalized()
		left_hand_basis = (roll_basis * left_hand_basis).orthonormalized()
	var right_hand_world_pos: Vector3 = _right_ik_target.global_position if _right_ik_target else _get_bone_world_position(_right_hand_bone_idx)
	var left_hand_world_pos: Vector3 = _left_ik_target.global_position if _left_ik_target else _get_bone_world_position(_left_hand_bone_idx)
	_apply_hand_world_basis_override(_right_hand_bone_idx, right_hand_basis, right_hand_world_pos, influence)
	_apply_hand_world_basis_override(_left_hand_bone_idx, left_hand_basis, left_hand_world_pos, influence)

func _apply_hand_world_basis_override(hand_bone_idx: int, world_basis: Basis, world_position: Vector3, influence: float) -> void:
	if hand_bone_idx < 0:
		return
	var hand_world_transform := Transform3D(world_basis, world_position)
	var hand_skeleton_transform: Transform3D = character_skeleton.global_transform.affine_inverse() * hand_world_transform
	character_skeleton.set_bone_global_pose_override(hand_bone_idx, hand_skeleton_transform, clampf(influence, 0.0, 1.0), true)

func _detect_ik_forward_sign() -> void:
	# This character rig is authored facing negative Z, so keep forward fixed.
	_ik_forward_sign = 1.0

func _compute_arm_ik_target_weight() -> float:
	if not is_multiplayer_authority():
		# Remote puppets should still show full arm IK using replicated camera/transform data.
		return 1.0
	# Keep IK active even when controls are disabled (pause/in-game menu).
	return 1.0

func _update_upper_body_ik(_delta: float) -> void:
	if character_skeleton == null:
		return
	if not character_skeleton.has_method("set_bone_global_pose_override"):
		return
	if not _ik_setup_complete:
		_setup_upper_body_ik()
		if not _ik_setup_complete:
			return

	_arm_ik_blend = _compute_arm_ik_target_weight()
	var ik_enabled := _arm_ik_blend > 0.001
	_set_two_bone_ik_state(_right_arm_ik_modifier, ik_enabled, _arm_ik_blend)
	_set_two_bone_ik_state(_left_arm_ik_modifier, ik_enabled, _arm_ik_blend)
	if not ik_enabled:
		_parallel_hand_orientation_active = false
		return

	if _right_ik_target == null or _left_ik_target == null or _right_ik_pole == null or _left_ik_pole == null:
		_parallel_hand_orientation_active = false
		return
	if _right_upper_arm_bone_idx < 0 or _left_upper_arm_bone_idx < 0:
		_parallel_hand_orientation_active = false
		return

	var right_root_world := _get_bone_world_position(_right_upper_arm_bone_idx)
	var left_root_world := _get_bone_world_position(_left_upper_arm_bone_idx)

	var shoulder_center: Vector3 = (right_root_world + left_root_world) * 0.5
	var model_basis: Basis = visuals.global_transform.basis.orthonormalized()
	var model_right: Vector3 = model_basis.x.normalized()
	var model_up: Vector3 = model_basis.y.normalized()
	var lateral_to_right: Vector3 = right_root_world - left_root_world
	lateral_to_right.y = 0.0
	if lateral_to_right.length_squared() <= IK_EPSILON:
		lateral_to_right = -model_right
	else:
		lateral_to_right = lateral_to_right.normalized()
	var aim_target: Vector3 = _get_ik_aim_target_world_position()
	var model_forward: Vector3 = aim_target - shoulder_center
	model_forward.y = 0.0
	if model_forward.length_squared() <= IK_EPSILON:
		model_forward = -camera.global_transform.basis.z
		model_forward.y = 0.0
	if model_forward.length_squared() <= IK_EPSILON:
		model_forward = Vector3.FORWARD
	model_forward = model_forward.normalized() * _ik_forward_sign

	var camera_forward: Vector3 = -camera.global_transform.basis.z.normalized()
	var up_pitch_ratio: float = maxf(0.0, camera_forward.dot(model_up))
	var pitch_vertical_offset: float = clampf(camera_forward.dot(model_up) * ik_pitch_vertical_scale, -ik_hands_max_vertical_offset, ik_hands_max_vertical_offset)
	var hold_forward_distance: float = maxf(0.26, ik_hands_forward_distance - (up_pitch_ratio * ik_close_hold_on_up_pitch))
	var elbow_down_bias: float = ik_elbow_down_bias + (up_pitch_ratio * ik_elbow_drop_on_up_pitch)

	var hand_center: Vector3 = shoulder_center + (model_forward * hold_forward_distance) + (model_up * (ik_hands_vertical_offset + pitch_vertical_offset - ik_forearm_barrel_drop))
	var half_clasp_separation: float = clampf(ik_hands_clasp_separation * 0.5, 0.0, ik_hands_max_spread * 0.5)
	var right_hand_target: Vector3 = hand_center + (lateral_to_right * half_clasp_separation)
	var left_hand_target: Vector3 = hand_center - (lateral_to_right * half_clasp_separation)
	var guard_distance: float = minf(ik_midline_guard_distance, half_clasp_separation)

	var right_side_distance: float = (right_hand_target - shoulder_center).dot(lateral_to_right)
	if right_side_distance < guard_distance:
		right_hand_target += lateral_to_right * (guard_distance - right_side_distance)

	var left_side_distance: float = (left_hand_target - shoulder_center).dot(lateral_to_right)
	if left_side_distance > -guard_distance:
		left_hand_target -= lateral_to_right * (left_side_distance + guard_distance)

	var right_pole_target: Vector3 = right_root_world + ((lateral_to_right * ik_elbow_outward_bias) + (model_forward * ik_elbow_forward_bias) - (model_up * elbow_down_bias))
	var left_pole_target: Vector3 = left_root_world + ((-lateral_to_right * ik_elbow_outward_bias) + (model_forward * ik_elbow_forward_bias) - (model_up * elbow_down_bias))
	_parallel_hand_desired_basis = _build_parallel_hand_aim_basis(aim_target - hand_center, lateral_to_right, model_up)
	_parallel_hand_orientation_active = true

	_right_ik_target.global_position = right_hand_target
	_left_ik_target.global_position = left_hand_target
	_right_ik_pole.global_position = right_pole_target
	_left_ik_pole.global_position = left_pole_target

func _get_ik_aim_target_world_position() -> Vector3:
	var current_frame: int = Engine.get_process_frames()
	if _ik_cached_aim_frame == current_frame:
		return _ik_cached_aim_target

	var ray_origin: Vector3 = camera.global_transform.origin
	var ray_direction: Vector3 = -camera.global_transform.basis.z.normalized()
	var ray_end: Vector3 = ray_origin + (ray_direction * ik_convergence_distance)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.exclude = [self]
	if convergence_ray:
		query.collision_mask = convergence_ray.collision_mask

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var desired_distance: float = ik_convergence_distance
	if not hit.is_empty() and hit.has("position"):
		desired_distance = minf(ik_convergence_distance, ray_origin.distance_to(hit["position"]))

	if _ik_smoothed_convergence_distance < 0.0:
		_ik_smoothed_convergence_distance = desired_distance
	else:
		var dt: float = maxf(get_process_delta_time(), 0.0001)
		var follow_alpha: float = 1.0 - exp(-maxf(ik_convergence_lerp_speed, 0.0) * dt)
		_ik_smoothed_convergence_distance = lerpf(_ik_smoothed_convergence_distance, desired_distance, clampf(follow_alpha, 0.0, 1.0))

	_ik_smoothed_convergence_distance = clampf(_ik_smoothed_convergence_distance, 0.05, ik_convergence_distance)
	_ik_cached_aim_target = ray_origin + (ray_direction * _ik_smoothed_convergence_distance)
	_ik_cached_aim_frame = current_frame
	return _ik_cached_aim_target

func _get_bone_world_position(bone_idx: int) -> Vector3:
	if character_skeleton == null or bone_idx < 0:
		return global_position
	var bone_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(bone_idx)
	return (character_skeleton.global_transform * bone_pose).origin

func _get_bone_world_rest_position(bone_idx: int) -> Vector3:
	if character_skeleton == null or bone_idx < 0:
		return global_position
	var bone_rest: Transform3D
	if character_skeleton.has_method("get_bone_global_rest"):
		bone_rest = character_skeleton.get_bone_global_rest(bone_idx)
	else:
		bone_rest = character_skeleton.get_bone_global_pose_no_override(bone_idx)
	return (character_skeleton.global_transform * bone_rest).origin

func _get_bone_world_basis(bone_idx: int) -> Basis:
	if character_skeleton == null or bone_idx < 0:
		return global_transform.basis.orthonormalized()
	var bone_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(bone_idx)
	return (character_skeleton.global_transform.basis * bone_pose.basis).orthonormalized()

func _get_bone_world_rest_basis(bone_idx: int) -> Basis:
	if character_skeleton == null or bone_idx < 0:
		return global_transform.basis.orthonormalized()
	var bone_rest: Transform3D
	if character_skeleton.has_method("get_bone_global_rest"):
		bone_rest = character_skeleton.get_bone_global_rest(bone_idx)
	else:
		bone_rest = character_skeleton.get_bone_global_pose_no_override(bone_idx)
	return (character_skeleton.global_transform.basis * bone_rest.basis).orthonormalized()

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

func _handle_loot_push_collisions() -> void:
	return

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

func _get_current_weapon_resource_path() -> String:
	if not weapon_manager or not weapon_manager.current_weapon:
		return ""
	if weapon_manager.current_weapon.resource_path != "":
		return weapon_manager.current_weapon.resource_path
	return network_equipped_weapon_path

func _sync_network_weapon_appearance() -> void:
	if not weapon_manager:
		return

	if is_multiplayer_authority():
		var current_weapon_path := _get_current_weapon_resource_path()
		if current_weapon_path != "" and network_equipped_weapon_path != current_weapon_path:
			network_equipped_weapon_path = current_weapon_path
		if current_weapon_path != "":
			_last_applied_network_weapon_path = current_weapon_path
		return

	if network_equipped_weapon_path == "":
		return
	if network_equipped_weapon_path == _last_applied_network_weapon_path:
		return
	if not ResourceLoader.exists(network_equipped_weapon_path):
		return

	var weapon_resource = load(network_equipped_weapon_path)
	if not (weapon_resource is WeaponResource):
		return

	weapon_manager.equip_weapon_template(weapon_resource, false)
	_last_applied_network_weapon_path = network_equipped_weapon_path

func set_username(new_username: String) -> void:
	var cleaned := MultiplayerManager.sanitize_username(new_username, player_id)
	username = cleaned
	if username_tag:
		username_tag.text = cleaned
	if is_multiplayer_authority():
		MultiplayerManager.player_username = cleaned

func _connect_world_hud_signals() -> void:
	if not is_multiplayer_authority():
		return

	var world := get_tree().current_scene
	if world == null:
		return

	if player_hud_overlay and player_hud_overlay.has_method("set_local_peer_id"):
		player_hud_overlay.call("set_local_peer_id", multiplayer.get_unique_id())

	if world.has_signal("scoreboard_changed") and not world.scoreboard_changed.is_connected(_on_world_scoreboard_changed):
		world.scoreboard_changed.connect(_on_world_scoreboard_changed)
	if world.has_signal("kill_feed_added") and not world.kill_feed_added.is_connected(_on_world_kill_feed_added):
		world.kill_feed_added.connect(_on_world_kill_feed_added)

	if world.has_method("get_scoreboard_snapshot"):
		_on_world_scoreboard_changed(world.call("get_scoreboard_snapshot"))
	if player_hud_overlay and player_hud_overlay.has_method("clear_kill_feed"):
		player_hud_overlay.call("clear_kill_feed")
	if world.has_method("get_kill_feed_snapshot"):
		var existing_feed: Array = world.call("get_kill_feed_snapshot")
		for feed_index in range(existing_feed.size() - 1, -1, -1):
			var feed_entry = existing_feed[feed_index]
			if typeof(feed_entry) == TYPE_DICTIONARY:
				_on_world_kill_feed_added(feed_entry)

func _on_world_scoreboard_changed(entries: Array) -> void:
	if not is_multiplayer_authority():
		return
	if player_hud_overlay and player_hud_overlay.has_method("update_scoreboard"):
		player_hud_overlay.call("update_scoreboard", entries)

func _on_world_kill_feed_added(entry: Dictionary) -> void:
	if not is_multiplayer_authority():
		return
	if player_hud_overlay and player_hud_overlay.has_method("push_kill_feed_entry"):
		player_hud_overlay.call("push_kill_feed_entry", entry)

func _set_dead_visual_state(dead: bool) -> void:
	if collision_shape:
		collision_shape.disabled = dead

	if is_multiplayer_authority():
		if visuals:
			visuals.visible = not dead
		if equipment:
			equipment.visible = not dead
		if dead and is_aiming:
			is_aiming = false
			camera_arm.stop_aim()
		if weapon_manager:
			weapon_manager.allow_shoot = not dead
		if viewModel:
			viewModel.visible = not dead
		if worldModel:
			worldModel.visible = not dead
	else:
		visible = not dead

	if dead:
		damage_bar_root.hide()
		username_tag.hide()

func _apply_remote_dead_state() -> void:
	if is_multiplayer_authority():
		return
	if _is_dead == network_is_dead:
		return
	_is_dead = network_is_dead
	_set_dead_visual_state(_is_dead)

func _update_respawn_hud() -> void:
	if not is_multiplayer_authority():
		return
	if respawn_hud == null:
		return
	if not _is_dead:
		return

	var remaining_seconds: float = maxf(float(_respawn_unlock_time_ms - Time.get_ticks_msec()) / 1000.0, 0.0)
	if respawn_hud.has_method("update_countdown"):
		respawn_hud.call("update_countdown", remaining_seconds)

	if remaining_seconds <= 0.0 and not _respawn_ready:
		_respawn_ready = true
		if respawn_hud.has_method("set_respawn_ready"):
			respawn_hud.call("set_respawn_ready", true)

func _on_respawn_requested() -> void:
	if not is_multiplayer_authority():
		return
	if not _is_dead or not _respawn_ready:
		return
	spawn()

func _start_death_state(attacker_peer_id: int) -> void:
	if _is_dead:
		return

	_is_dead = true
	_active_health_pack_effects.clear()
	network_is_dead = true
	_respawn_ready = false
	_respawn_unlock_time_ms = Time.get_ticks_msec() + int(respawn_delay_seconds * 1000.0)
	velocity = Vector3.ZERO
	_spawn_death_particle_burst()
	_reset_crosshair_spread()
	_set_dead_visual_state(true)
	weapon_manager.set_trigger_pressed(false)

	if is_multiplayer_authority() and respawn_hud and respawn_hud.has_method("show_countdown"):
		respawn_hud.call("show_countdown", respawn_delay_seconds)

	_report_death_to_world(attacker_peer_id)

func _reset_crosshair_spread() -> void:
	if not is_multiplayer_authority():
		return
	if crosshair and crosshair.has_method("reset_spread"):
		crosshair.call("reset_spread")

func _spawn_death_particle_burst() -> void:
	if not is_multiplayer_authority():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = int(Time.get_ticks_usec()) ^ (multiplayer.get_unique_id() << 8)
	var burst_origin := global_position + Vector3.UP * death_particle_height_offset
	var burst_count: int = max(death_particle_burst_count, 1)

	for _burst_i in range(burst_count):
		var yaw := rng.randf_range(0.0, TAU)
		var lateral := Vector3(cos(yaw), 0.0, sin(yaw))
		var radial_offset := rng.randf_range(0.03, death_particle_burst_radius)
		var vertical_jitter := rng.randf_range(-0.08, 0.2)
		var burst_pos := burst_origin + (lateral * radial_offset) + (Vector3.UP * vertical_jitter)
		var burst_dir := (lateral * rng.randf_range(0.45, 1.0)) + (Vector3.UP * rng.randf_range(0.25, death_particle_upward_bias))
		if burst_dir.length_squared() <= IK_EPSILON:
			burst_dir = Vector3.UP
		_sync_death_particle.rpc(burst_pos, Vector3.UP, burst_dir.normalized())

@rpc("any_peer", "call_local", "reliable")
func _sync_death_particle(pos: Vector3, normal: Vector3, dir: Vector3) -> void:
	var resolved_normal := normal.normalized() if normal.length_squared() > IK_EPSILON else Vector3.UP
	var resolved_dir := dir.normalized() if dir.length_squared() > IK_EPSILON else Vector3.UP
	ImpactManager.spawn_impact("enemy", pos, resolved_normal, resolved_dir)

func _report_death_to_world(attacker_peer_id: int) -> void:
	var world := get_tree().current_scene
	if world == null or not world.has_method("report_player_death"):
		return

	var victim_peer_id := multiplayer.get_unique_id()
	var killer_peer_id := attacker_peer_id if attacker_peer_id > 0 else 0

	if multiplayer.multiplayer_peer == null:
		world.call("report_player_death", victim_peer_id, killer_peer_id)
		return

	if multiplayer.is_server():
		world.call_deferred("report_player_death", victim_peer_id, killer_peer_id)
	else:
		world.rpc("report_player_death", victim_peer_id, killer_peer_id)

func _apply_enemy_albedo_variant() -> void:
	if is_multiplayer_authority():
		return
	if visuals == null:
		return

	for mesh_node in visuals.find_children("*", "MeshInstance3D", true, false):
		if not (mesh_node is MeshInstance3D):
			continue

		var mesh_instance := mesh_node as MeshInstance3D
		if worldModel != null and worldModel.is_ancestor_of(mesh_instance):
			continue
		var source_material = mesh_instance.get_active_material(0)
		if not (source_material is StandardMaterial3D):
			continue

		mesh_instance.material_override = _create_enemy_albedo_material(source_material as StandardMaterial3D)

func _create_enemy_albedo_material(source_material: StandardMaterial3D) -> StandardMaterial3D:
	var copied_material = source_material.duplicate(true)
	if copied_material is StandardMaterial3D:
		var standard_copy := copied_material as StandardMaterial3D
		standard_copy.albedo_texture = ENEMY_REMOTE_ALBEDO_TEXTURE
		return standard_copy

	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = source_material.albedo_color
	fallback.albedo_texture = ENEMY_REMOTE_ALBEDO_TEXTURE
	fallback.metallic = source_material.metallic
	fallback.roughness = source_material.roughness
	fallback.metallic_texture = source_material.metallic_texture
	fallback.normal_texture = source_material.normal_texture
	return fallback

func give_full_reserve_ammo_local() -> void:
	if not is_multiplayer_authority():
		return
	if weapon_manager and weapon_manager.has_method("refill_current_weapon_reserve_to_max"):
		weapon_manager.refill_current_weapon_reserve_to_max()
	_update_ammo_display()

@rpc("any_peer", "call_remote", "reliable")
func give_full_reserve_ammo() -> void:
	give_full_reserve_ammo_local()

func apply_health_pack_local(immediate_heal: float, regen_heal_per_second: float, regen_duration_seconds: float) -> void:
	if not is_multiplayer_authority() or _is_dead:
		return

	_apply_heal_amount(maxf(immediate_heal, 0.0))

	var regen_rate: float = maxf(regen_heal_per_second, 0.0)
	var regen_duration: float = maxf(regen_duration_seconds, 0.0)
	if regen_rate > 0.0 and regen_duration > 0.0:
		_active_health_pack_effects.append({
			"rate": regen_rate,
			"remaining": regen_duration,
		})

@rpc("any_peer", "call_remote", "reliable")
func apply_health_pack(immediate_heal: float, regen_heal_per_second: float, regen_duration_seconds: float) -> void:
	apply_health_pack_local(immediate_heal, regen_heal_per_second, regen_duration_seconds)

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
	network_equipped_weapon_path = weapon_resource_path
	_last_applied_network_weapon_path = weapon_resource_path
	_update_ammo_display()

@rpc("any_peer", "call_remote", "reliable")
func equip_weapon_full_from_path(weapon_resource_path: String) -> void:
	equip_weapon_full_from_path_local(weapon_resource_path)

func _kill_from_world_fall() -> void:
	if _is_dead:
		return
	health = 0.0
	_set_local_health_ratio(0.0)
	_start_death_state(0)

func _reset_weapon_on_spawn() -> void:
	if not is_multiplayer_authority():
		return
	if weapon_manager == null or not is_instance_valid(weapon_manager):
		return
	equip_weapon_full_from_path_local(RESPAWN_WEAPON_PATH)

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

func _apply_heal_amount(amount: float) -> float:
	if not is_multiplayer_authority():
		return 0.0
	if _is_dead or amount <= 0.0:
		return 0.0

	var previous_health: float = health
	health = clampf(health + amount, 0.0, max_health)
	if health > previous_health:
		_set_local_health_ratio(health / max_health)
	return health - previous_health

func _update_health_pack_effects(delta: float) -> void:
	if not is_multiplayer_authority() or _is_dead:
		return
	if _active_health_pack_effects.is_empty():
		return

	var total_heal: float = 0.0
	for effect_idx in range(_active_health_pack_effects.size() - 1, -1, -1):
		var effect: Dictionary = _active_health_pack_effects[effect_idx]
		var remaining: float = float(effect.get("remaining", 0.0))
		var rate: float = float(effect.get("rate", 0.0))
		if remaining <= 0.0 or rate <= 0.0:
			_active_health_pack_effects.remove_at(effect_idx)
			continue

		var tick_time: float = minf(delta, remaining)
		total_heal += rate * tick_time
		remaining -= tick_time
		if remaining <= 0.0:
			_active_health_pack_effects.remove_at(effect_idx)
		else:
			effect["remaining"] = remaining
			_active_health_pack_effects[effect_idx] = effect

	if total_heal > 0.0:
		_apply_heal_amount(total_heal)

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
	if _is_dead:
		is_aiming = false
		return
	is_aiming = aiming
	if aiming:
		camera.set_cull_mask_value(WORLD_MODEL_LAYER, false)
		camera.set_cull_mask_value(VIEW_MODEL_LAYER, true)
		visuals.hide()
	else:
		camera.set_cull_mask_value(WORLD_MODEL_LAYER, true)
		camera.set_cull_mask_value(VIEW_MODEL_LAYER, false)
		visuals.show()

func cancel_sprint_for_ads() -> void:
	is_sprinting = false

func is_dead() -> bool:
	return _is_dead

@rpc("any_peer")
func hurt(damage: float, attacker_peer_id: int = 0):
	if _is_dead:
		return
	var resolved_attacker_peer_id := attacker_peer_id
	if resolved_attacker_peer_id <= 0:
		resolved_attacker_peer_id = multiplayer.get_remote_sender_id()
	var prev_health = health
	health -= damage
	health = clamp(health, 0.0, max_health)
	_last_damage_time_ms = Time.get_ticks_msec()
	_set_local_health_ratio(health / max_health)
	if health < (max_health * 0.5) and health < prev_health:
		_hud_hit_flash_strength = 1.0
	if resolved_attacker_peer_id > 0 and resolved_attacker_peer_id != multiplayer.get_unique_id():
		_show_damage_to_attacker.rpc_id(resolved_attacker_peer_id, health / max_health)

	if health <= 0:
		_start_death_state(resolved_attacker_peer_id)

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
	network_equipped_weapon_path = _get_current_weapon_resource_path()
	_last_applied_network_weapon_path = network_equipped_weapon_path
	_respawn_ready = false
	_respawn_unlock_time_ms = 0


	if is_multiplayer_authority():
		set_username(MultiplayerManager.player_username)
		username_tag.hide()
		MultiplayerManager.register_local_peer_username(player_id)
		_connect_world_hud_signals()
	else:
		_apply_enemy_albedo_variant()

	if respawn_hud and respawn_hud.has_signal("respawn_requested") and not respawn_hud.respawn_requested.is_connected(_on_respawn_requested):
		respawn_hud.respawn_requested.connect(_on_respawn_requested)
	if respawn_hud and respawn_hud.has_method("hide_hud"):
		respawn_hud.call("hide_hud")

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
		_is_dead = network_is_dead
		_set_dead_visual_state(_is_dead)
		return
	
	hud.show()
	_create_loot_prompt()
	_update_ammo_display()
	_setup_upper_body_ik()
	_ik_smoothed_convergence_distance = ik_convergence_distance
	_ik_cached_aim_frame = -1
		
	camera.current = true
	floor_snap_length = 0.5
	apply_floor_snap()
	spawn()

	# Connect to the camera's signal
	camera_arm.aim_toggled.connect(_on_aim_toggled)

func spawn() -> void:
	_is_dead = false
	_active_health_pack_effects.clear()
	network_is_dead = false
	_respawn_ready = false
	_respawn_unlock_time_ms = 0
	velocity = Vector3.ZERO
	_set_dead_visual_state(false)
	_reset_crosshair_spread()
	_reset_weapon_on_spawn()
	if respawn_hud and respawn_hud.has_method("hide_hud"):
		respawn_hud.call("hide_hud")

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
		var world := get_tree().current_scene
		if world and world.has_method("_refresh_input_state"):
			world.call("_refresh_input_state")
