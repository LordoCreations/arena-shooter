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
var _left_arm_chain := {}
var _right_arm_chain := {}
var _ik_forward_sign: float = 1.0
var _right_hand_gun_basis_offset: Basis = Basis.IDENTITY
var _left_hand_gun_basis_offset: Basis = Basis.IDENTITY
var _right_hand_axis_map := {}
var _left_hand_axis_map := {}
var _last_ik_gun_model_id: int = 0
var _ik_smoothed_convergence_distance: float = -1.0
var _ik_cached_aim_frame: int = -1
var _ik_cached_aim_target: Vector3 = Vector3.ZERO

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

	if is_multiplayer_authority() and not _is_dead and health > 0.0 and health < max_health:
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
	var right_hand_idx := character_skeleton.find_bone("Hand.R")
	var left_hand_idx := character_skeleton.find_bone("Hand.L")
	var right_hand_leaf_idx := character_skeleton.find_bone("Hand.R_leaf")
	var left_hand_leaf_idx := character_skeleton.find_bone("Hand.L_leaf")
	var right_tip_idx := right_hand_idx if right_hand_idx >= 0 else character_skeleton.find_bone("LowerArm.R_leaf")
	var left_tip_idx := left_hand_idx if left_hand_idx >= 0 else character_skeleton.find_bone("LowerArm.L_leaf")

	_right_arm_chain = {
		"side": "right",
		"upper": character_skeleton.find_bone("UpperArm.R"),
		"lower": character_skeleton.find_bone("LowerArm.R"),
		"hand": right_hand_idx,
		"leaf": right_hand_leaf_idx,
		"tip": right_tip_idx,
	}
	_left_arm_chain = {
		"side": "left",
		"upper": character_skeleton.find_bone("UpperArm.L"),
		"lower": character_skeleton.find_bone("LowerArm.L"),
		"hand": left_hand_idx,
		"leaf": left_hand_leaf_idx,
		"tip": left_tip_idx,
	}

	var right_valid := int(_right_arm_chain.get("upper", -1)) >= 0 and int(_right_arm_chain.get("lower", -1)) >= 0 and int(_right_arm_chain.get("tip", -1)) >= 0
	var left_valid := int(_left_arm_chain.get("upper", -1)) >= 0 and int(_left_arm_chain.get("lower", -1)) >= 0 and int(_left_arm_chain.get("tip", -1)) >= 0
	_ik_setup_complete = right_valid and left_valid
	if _ik_setup_complete:
		_detect_ik_forward_sign()
		_cache_hand_gun_basis_offsets()
		_cache_hand_axis_maps()

func _detect_ik_forward_sign() -> void:
	# This character rig is authored facing negative Z, so keep forward fixed.
	_ik_forward_sign = 1.0

func _get_gun_world_basis_for_ik() -> Basis:
	# Build a stable world basis that points directly toward the actual shot/aim target.
	var aim_origin: Vector3 = global_transform.origin
	if weapon_manager and weapon_manager.current_world_model and is_instance_valid(weapon_manager.current_world_model):
		aim_origin = weapon_manager.current_world_model.global_transform.origin
	elif equipment and is_instance_valid(equipment):
		aim_origin = equipment.global_transform.origin
	elif camera and is_instance_valid(camera):
		aim_origin = camera.global_transform.origin

	var aim_target: Vector3 = _get_ik_aim_target_world_position()
	var aim_forward: Vector3 = aim_target - aim_origin
	if aim_forward.length_squared() <= IK_EPSILON:
		if camera and is_instance_valid(camera):
			aim_forward = -camera.global_transform.basis.z
		elif equipment and is_instance_valid(equipment):
			aim_forward = -equipment.global_transform.basis.z
		else:
			aim_forward = -global_transform.basis.z
	aim_forward = aim_forward.normalized()

	var up_ref: Vector3 = visuals.global_transform.basis.y.normalized()
	if absf(up_ref.dot(aim_forward)) > 0.98:
		up_ref = Vector3.UP if absf(Vector3.UP.dot(aim_forward)) < 0.98 else Vector3.RIGHT
	var aim_right: Vector3 = up_ref.cross(aim_forward)
	if aim_right.length_squared() <= IK_EPSILON:
		aim_right = camera.global_transform.basis.x if camera and is_instance_valid(camera) else Vector3.RIGHT
	aim_right = aim_right.normalized()
	var aim_up: Vector3 = aim_forward.cross(aim_right).normalized()
	return Basis(aim_right, aim_up, -aim_forward).orthonormalized()

func _cache_hand_gun_basis_offsets() -> void:
	if character_skeleton == null:
		return
	var gun_basis := _get_gun_world_basis_for_ik()
	if gun_basis.determinant() == 0.0:
		return

	_right_hand_gun_basis_offset = _compute_hand_gun_basis_offset(_right_arm_chain, gun_basis)
	_left_hand_gun_basis_offset = _compute_hand_gun_basis_offset(_left_arm_chain, gun_basis)

func _cache_hand_axis_maps() -> void:
	if character_skeleton == null:
		return
	var right_root_world := _get_arm_root_world_position(_right_arm_chain)
	var left_root_world := _get_arm_root_world_position(_left_arm_chain)
	var shoulder_center_world: Vector3 = (right_root_world + left_root_world) * 0.5
	var model_up: Vector3 = visuals.global_transform.basis.y.normalized()

	_right_hand_axis_map = _compute_hand_axis_map(_right_arm_chain, shoulder_center_world, model_up)
	_left_hand_axis_map = _compute_hand_axis_map(_left_arm_chain, shoulder_center_world, model_up)
	_right_arm_chain["axis_map"] = _right_hand_axis_map
	_left_arm_chain["axis_map"] = _left_hand_axis_map

func _compute_hand_axis_map(chain: Dictionary, shoulder_center_world: Vector3, model_up: Vector3) -> Dictionary:
	var hand_idx := int(chain.get("hand", -1))
	if hand_idx < 0:
		return {}

	var hand_rest: Transform3D
	if character_skeleton.has_method("get_bone_global_rest"):
		hand_rest = character_skeleton.get_bone_global_rest(hand_idx)
	else:
		hand_rest = character_skeleton.get_bone_global_pose_no_override(hand_idx)

	var hand_world: Transform3D = character_skeleton.global_transform * hand_rest

	# Use hand leaf direction as the primary finger reference when available.
	var finger_ref_dir := Vector3.ZERO
	var leaf_idx := int(chain.get("leaf", -1))
	if leaf_idx >= 0:
		var leaf_rest: Transform3D
		if character_skeleton.has_method("get_bone_global_rest"):
			leaf_rest = character_skeleton.get_bone_global_rest(leaf_idx)
		else:
			leaf_rest = character_skeleton.get_bone_global_pose_no_override(leaf_idx)
		var leaf_world: Transform3D = character_skeleton.global_transform * leaf_rest
		finger_ref_dir = leaf_world.origin - hand_world.origin

	if finger_ref_dir.length_squared() <= IK_EPSILON:
		var lower_idx := int(chain.get("lower", -1))
		if lower_idx >= 0:
			var lower_rest: Transform3D
			if character_skeleton.has_method("get_bone_global_rest"):
				lower_rest = character_skeleton.get_bone_global_rest(lower_idx)
			else:
				lower_rest = character_skeleton.get_bone_global_pose_no_override(lower_idx)
			var lower_world: Transform3D = character_skeleton.global_transform * lower_rest
			finger_ref_dir = hand_world.origin - lower_world.origin

	if finger_ref_dir.length_squared() <= IK_EPSILON:
		var outward_dir: Vector3 = hand_world.origin - shoulder_center_world
		outward_dir = outward_dir - (model_up * outward_dir.dot(model_up))
		if outward_dir.length_squared() <= IK_EPSILON:
			var model_right: Vector3 = visuals.global_transform.basis.x.normalized()
			outward_dir = -model_right if str(chain.get("side", "")) == "right" else model_right
		finger_ref_dir = outward_dir

	finger_ref_dir = finger_ref_dir.normalized()

	var down_dir: Vector3 = -model_up.normalized()
	var finger_axis_pick := _pick_basis_axis_for_direction(hand_world.basis, finger_ref_dir, -1)
	var palm_axis_pick := _pick_basis_axis_for_direction(hand_world.basis, down_dir, int(finger_axis_pick.get("idx", 0)))

	return {
		"finger_idx": int(finger_axis_pick.get("idx", 0)),
		"finger_sign": float(finger_axis_pick.get("sign", 1.0)),
		"palm_idx": int(palm_axis_pick.get("idx", 1)),
		"palm_sign": float(palm_axis_pick.get("sign", 1.0)),
	}

func _pick_basis_axis_for_direction(source_basis: Basis, direction: Vector3, excluded_axis: int = -1) -> Dictionary:
	var axes := [source_basis.x.normalized(), source_basis.y.normalized(), source_basis.z.normalized()]
	var best_idx := 0
	var best_abs_dot := -1.0
	var best_sign := 1.0
	for i in range(3):
		if i == excluded_axis:
			continue
		var dot_val: float = axes[i].dot(direction)
		var abs_dot: float = absf(dot_val)
		if abs_dot > best_abs_dot:
			best_abs_dot = abs_dot
			best_idx = i
			best_sign = 1.0 if dot_val >= 0.0 else -1.0

	return {
		"idx": best_idx,
		"sign": best_sign,
	}

func _build_hand_world_basis_from_axis_map(axis_map: Dictionary, finger_dir: Vector3, palm_dir: Vector3) -> Basis:
	var finger_idx := int(axis_map.get("finger_idx", 0))
	var finger_sign := float(axis_map.get("finger_sign", 1.0))
	var palm_idx := int(axis_map.get("palm_idx", 1))
	var palm_sign := float(axis_map.get("palm_sign", 1.0))

	var target_finger := finger_dir.normalized()
	var target_palm := palm_dir - (target_finger * palm_dir.dot(target_finger))
	if target_palm.length_squared() <= IK_EPSILON:
		target_palm = Vector3.UP - (target_finger * Vector3.UP.dot(target_finger))
	if target_palm.length_squared() <= IK_EPSILON:
		target_palm = Vector3.RIGHT - (target_finger * Vector3.RIGHT.dot(target_finger))
	target_palm = target_palm.normalized()

	var axes := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	axes[finger_idx] = target_finger * finger_sign
	axes[palm_idx] = target_palm * palm_sign

	var remaining_idx := 3 - finger_idx - palm_idx
	if remaining_idx == 2:
		axes[2] = axes[0].cross(axes[1]).normalized()
	elif remaining_idx == 1:
		axes[1] = axes[2].cross(axes[0]).normalized()
	else:
		axes[0] = axes[1].cross(axes[2]).normalized()

	return Basis(axes[0], axes[1], axes[2]).orthonormalized()

func _compute_hand_gun_basis_offset(chain: Dictionary, gun_basis: Basis) -> Basis:
	var hand_idx := int(chain.get("hand", -1))
	if hand_idx < 0:
		return Basis.IDENTITY
	var hand_world_basis: Basis
	if character_skeleton.has_method("get_bone_global_rest"):
		var hand_rest: Transform3D = character_skeleton.get_bone_global_rest(hand_idx)
		hand_world_basis = (character_skeleton.global_transform.basis * hand_rest.basis).orthonormalized()
	else:
		var hand_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(hand_idx)
		hand_world_basis = (character_skeleton.global_transform.basis * hand_pose.basis).orthonormalized()
	return (gun_basis.inverse() * hand_world_basis).orthonormalized()

func _refresh_hand_gun_offsets_if_needed() -> void:
	var model_id := 0
	if weapon_manager and weapon_manager.current_world_model and is_instance_valid(weapon_manager.current_world_model):
		model_id = weapon_manager.current_world_model.get_instance_id()
	if model_id != _last_ik_gun_model_id:
		_last_ik_gun_model_id = model_id
		_cache_hand_gun_basis_offsets()

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

	var target_weight := _compute_arm_ik_target_weight()
	_arm_ik_blend = target_weight

	if _arm_ik_blend <= 0.001:
		_clear_upper_body_ik_overrides()
		return
	_refresh_hand_gun_offsets_if_needed()
	var gun_basis := _get_gun_world_basis_for_ik()

	var right_root_world := _get_arm_root_world_position(_right_arm_chain)
	var left_root_world := _get_arm_root_world_position(_left_arm_chain)

	var shoulder_center: Vector3 = (right_root_world + left_root_world) * 0.5
	var model_basis: Basis = visuals.global_transform.basis.orthonormalized()
	var model_right: Vector3 = model_basis.x.normalized()
	var model_up: Vector3 = model_basis.y.normalized()
	var model_forward: Vector3 = -model_basis.z
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
	var half_clasp_separation: float = clampf(ik_hands_centerline_offset, 0.0, ik_hands_max_spread * 0.5)
	var right_hand_target: Vector3 = hand_center + (model_right * half_clasp_separation)
	var left_hand_target: Vector3 = hand_center - (model_right * half_clasp_separation)
	var guard_distance: float = minf(ik_midline_guard_distance, half_clasp_separation)

	var right_side_distance: float = (right_hand_target - shoulder_center).dot(model_right)
	if right_side_distance < guard_distance:
		right_hand_target += model_right * (guard_distance - right_side_distance)

	var left_side_distance: float = (left_hand_target - shoulder_center).dot(model_right)
	if left_side_distance > -guard_distance:
		left_hand_target -= model_right * (left_side_distance + guard_distance)

	var right_elbow_axis: Vector3 = ((model_right * ik_elbow_outward_bias) + (model_forward * ik_elbow_forward_bias) - (model_up * elbow_down_bias)).normalized()
	var left_elbow_axis: Vector3 = ((-model_right * ik_elbow_outward_bias) + (model_forward * ik_elbow_forward_bias) - (model_up * elbow_down_bias)).normalized()
	var clasp_focus: Vector3 = hand_center + (model_forward * ik_clasp_focus_forward_offset)
	var right_center_inward: Vector3 = clasp_focus - right_hand_target
	var left_center_inward: Vector3 = clasp_focus - left_hand_target
	var right_palm_focus: Vector3 = left_hand_target + (model_forward * ik_palm_clasp_forward_offset)
	var left_palm_focus: Vector3 = right_hand_target + (model_forward * ik_palm_clasp_forward_offset)
	var clasp_bias: float = clampf(ik_palm_clasp_bias, 0.0, 1.0)
	var right_inward_dir: Vector3 = right_center_inward.lerp(right_palm_focus - right_hand_target, clasp_bias)
	var left_inward_dir: Vector3 = left_center_inward.lerp(left_palm_focus - left_hand_target, clasp_bias)
	if right_inward_dir.length_squared() <= IK_EPSILON:
		right_inward_dir = left_hand_target - right_hand_target
	if left_inward_dir.length_squared() <= IK_EPSILON:
		left_inward_dir = right_hand_target - left_hand_target
	right_inward_dir = right_inward_dir.normalized()
	left_inward_dir = left_inward_dir.normalized()

	_apply_arm_target_ik(_right_arm_chain, right_hand_target, right_elbow_axis, gun_basis, right_inward_dir, _arm_ik_blend)
	_apply_arm_target_ik(_left_arm_chain, left_hand_target, left_elbow_axis, gun_basis, left_inward_dir, _arm_ik_blend)

func _clear_upper_body_ik_overrides() -> void:
	if character_skeleton == null or not character_skeleton.has_method("set_bone_global_pose_override"):
		return
	if not _ik_setup_complete:
		return
	if character_skeleton.has_method("clear_bones_global_pose_override"):
		character_skeleton.clear_bones_global_pose_override()
		return
	_set_arm_chain_override_weight(_right_arm_chain, 0.0)
	_set_arm_chain_override_weight(_left_arm_chain, 0.0)

func _set_arm_chain_override_weight(chain: Dictionary, weight: float) -> void:
	var upper_idx := int(chain.get("upper", -1))
	var lower_idx := int(chain.get("lower", -1))
	var hand_idx := int(chain.get("hand", -1))
	if upper_idx < 0 or lower_idx < 0:
		return

	var upper_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(upper_idx)
	var lower_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(lower_idx)
	character_skeleton.set_bone_global_pose_override(upper_idx, upper_pose, weight, true)
	character_skeleton.set_bone_global_pose_override(lower_idx, lower_pose, weight, true)
	if hand_idx >= 0:
		var hand_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(hand_idx)
		character_skeleton.set_bone_global_pose_override(hand_idx, hand_pose, weight, true)

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

func _get_arm_root_world_position(chain: Dictionary) -> Vector3:
	var upper_idx := int(chain.get("upper", -1))
	if upper_idx < 0:
		return Vector3.ZERO
	var upper_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(upper_idx)
	return (character_skeleton.global_transform * upper_pose).origin

func _apply_arm_target_ik(chain: Dictionary, tip_target_world: Vector3, preferred_elbow_axis_world: Vector3, gun_basis: Basis, inward_dir_world: Vector3, weight: float) -> void:
	var upper_idx := int(chain.get("upper", -1))
	var lower_idx := int(chain.get("lower", -1))
	var hand_idx := int(chain.get("hand", -1))
	var tip_idx := int(chain.get("tip", -1))
	if upper_idx < 0 or lower_idx < 0 or tip_idx < 0:
		return

	var upper_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(upper_idx)
	var lower_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(lower_idx)
	var tip_pose: Transform3D = character_skeleton.get_bone_global_pose_no_override(tip_idx)

	var skeleton_world: Transform3D = character_skeleton.global_transform
	var upper_world: Transform3D = skeleton_world * upper_pose
	var lower_world: Transform3D = skeleton_world * lower_pose
	var tip_world: Transform3D = skeleton_world * tip_pose

	var root_position: Vector3 = upper_world.origin
	var joint_position: Vector3 = lower_world.origin
	var tip_position: Vector3 = tip_world.origin

	if (tip_position - root_position).length_squared() <= IK_EPSILON:
		return

	var solved := _solve_two_bone_chain(root_position, joint_position, tip_position, tip_target_world, preferred_elbow_axis_world)
	if solved.is_empty():
		return

	var solved_joint: Vector3 = solved.get("joint", joint_position)
	var solved_tip: Vector3 = solved.get("tip", tip_position)

	var upper_from: Vector3 = joint_position - root_position
	var upper_to: Vector3 = solved_joint - root_position
	var lower_from: Vector3 = tip_position - joint_position
	var lower_to: Vector3 = solved_tip - solved_joint
	if upper_from.length_squared() <= IK_EPSILON or upper_to.length_squared() <= IK_EPSILON:
		return
	if lower_from.length_squared() <= IK_EPSILON or lower_to.length_squared() <= IK_EPSILON:
		return

	var upper_basis := _rotate_basis_towards_direction(upper_world.basis, upper_from, upper_to)
	var lower_basis := _rotate_basis_towards_direction(lower_world.basis, lower_from, lower_to)

	var solved_upper_world := Transform3D(upper_basis, root_position)
	var solved_lower_world := Transform3D(lower_basis, solved_joint)

	var solved_upper_skeleton: Transform3D = skeleton_world.affine_inverse() * solved_upper_world
	var solved_lower_skeleton: Transform3D = skeleton_world.affine_inverse() * solved_lower_world

	character_skeleton.set_bone_global_pose_override(upper_idx, solved_upper_skeleton, weight, true)
	character_skeleton.set_bone_global_pose_override(lower_idx, solved_lower_skeleton, weight, true)

	if hand_idx >= 0:
		_apply_hand_rotation_override(chain, hand_idx, tip_target_world, solved_joint, gun_basis, inward_dir_world, weight)

func _apply_hand_rotation_override(chain: Dictionary, hand_idx: int, hand_target_world: Vector3, forearm_origin_world: Vector3, gun_basis: Basis, inward_dir_world: Vector3, weight: float) -> void:
	if character_skeleton == null:
		return
	if not weapon_manager or not weapon_manager.current_world_model or not is_instance_valid(weapon_manager.current_world_model):
		return
	var side := str(chain.get("side", ""))
	var axis_map: Dictionary = chain.get("axis_map", {})
	if axis_map.is_empty():
		axis_map = _right_hand_axis_map if side == "right" else _left_hand_axis_map

	var target_hand_basis: Basis
	if axis_map.is_empty():
		var hand_basis_offset: Basis = _right_hand_gun_basis_offset if side == "right" else _left_hand_gun_basis_offset
		target_hand_basis = (gun_basis * hand_basis_offset).orthonormalized()
	else:
		var gun_finger_dir: Vector3 = -gun_basis.z.normalized()
		var forearm_dir: Vector3 = hand_target_world - forearm_origin_world
		if forearm_dir.length_squared() <= IK_EPSILON:
			forearm_dir = gun_finger_dir
		else:
			forearm_dir = forearm_dir.normalized()
		var forearm_follow: float = clampf(ik_hand_forearm_follow, 0.0, 1.0)
		var finger_dir: Vector3 = (gun_finger_dir * (1.0 - forearm_follow)) + (forearm_dir * forearm_follow)
		if finger_dir.length_squared() <= IK_EPSILON:
			finger_dir = gun_finger_dir
		finger_dir = finger_dir.normalized()

		var inward_dir: Vector3 = inward_dir_world.normalized()
		if inward_dir.length_squared() <= IK_EPSILON:
			inward_dir = (-visuals.global_transform.basis.x).normalized() if side == "right" else visuals.global_transform.basis.x.normalized()
		inward_dir = inward_dir - (finger_dir * inward_dir.dot(finger_dir))
		if inward_dir.length_squared() <= IK_EPSILON:
			inward_dir = (visuals.global_transform.basis.y - (finger_dir * visuals.global_transform.basis.y.dot(finger_dir))).normalized()
		if inward_dir.length_squared() <= IK_EPSILON:
			inward_dir = (-visuals.global_transform.basis.x).normalized() if side == "right" else visuals.global_transform.basis.x.normalized()
		target_hand_basis = _build_hand_world_basis_from_axis_map(axis_map, finger_dir, inward_dir)

	var hand_world_transform := Transform3D(target_hand_basis, hand_target_world)
	var hand_skeleton_transform: Transform3D = character_skeleton.global_transform.affine_inverse() * hand_world_transform
	character_skeleton.set_bone_global_pose_override(hand_idx, hand_skeleton_transform, weight, true)

func _solve_two_bone_chain(root_pos: Vector3, joint_pos: Vector3, tip_pos: Vector3, target_pos: Vector3, preferred_bend_axis: Vector3 = Vector3.ZERO) -> Dictionary:
	var upper_len := root_pos.distance_to(joint_pos)
	var lower_len := joint_pos.distance_to(tip_pos)
	if upper_len <= IK_EPSILON or lower_len <= IK_EPSILON:
		return {}

	var target_delta := target_pos - root_pos
	var target_dist := target_delta.length()
	if target_dist <= IK_EPSILON:
		return {}

	var min_reach: float = absf(upper_len - lower_len) + 0.0001
	var max_reach: float = upper_len + lower_len - 0.0001
	var clamped_dist: float = clampf(target_dist, min_reach, max_reach)
	var target_dir: Vector3 = target_delta / target_dist

	var bend_axis: Vector3 = Vector3.ZERO
	if preferred_bend_axis.length_squared() > IK_EPSILON:
		bend_axis = preferred_bend_axis.normalized()
		bend_axis = bend_axis - (target_dir * bend_axis.dot(target_dir))
		if bend_axis.length_squared() > IK_EPSILON:
			bend_axis = bend_axis.normalized()

	if bend_axis.length_squared() <= IK_EPSILON:
		var bend_normal := (joint_pos - root_pos).cross(tip_pos - joint_pos)
		if bend_normal.length_squared() <= IK_EPSILON:
			bend_normal = character_skeleton.global_transform.basis.z.cross(target_dir)
		if bend_normal.length_squared() <= IK_EPSILON:
			bend_normal = Vector3.UP
		bend_normal = bend_normal.normalized()
		bend_axis = bend_normal.cross(target_dir)
		if bend_axis.length_squared() <= IK_EPSILON:
			bend_axis = character_skeleton.global_transform.basis.y
		bend_axis = bend_axis.normalized()

	var cos_root: float = clampf((upper_len * upper_len + clamped_dist * clamped_dist - lower_len * lower_len) / (2.0 * upper_len * clamped_dist), -1.0, 1.0)
	var sin_root := sqrt(max(0.0, 1.0 - (cos_root * cos_root)))

	var solved_joint: Vector3 = root_pos + (target_dir * (cos_root * upper_len)) + (bend_axis * (sin_root * upper_len))
	var solved_tip: Vector3 = root_pos + (target_dir * clamped_dist)
	if target_dist <= max_reach:
		solved_tip = target_pos

	return {
		"joint": solved_joint,
		"tip": solved_tip,
	}

func _rotate_basis_towards_direction(source_basis: Basis, from_dir: Vector3, to_dir: Vector3) -> Basis:
	var from_n := from_dir.normalized()
	var to_n := to_dir.normalized()
	var dot: float = clampf(from_n.dot(to_n), -1.0, 1.0)
	if dot >= 0.9999:
		return source_basis

	var axis := from_n.cross(to_n)
	if axis.length_squared() <= IK_EPSILON:
		axis = source_basis.x
		if abs(axis.normalized().dot(from_n)) > 0.95:
			axis = source_basis.z
	axis = axis.normalized()

	var angle := acos(dot)
	return Basis(axis, angle) * source_basis

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
	network_is_dead = true
	_respawn_ready = false
	_respawn_unlock_time_ms = Time.get_ticks_msec() + int(respawn_delay_seconds * 1000.0)
	velocity = Vector3.ZERO
	_set_dead_visual_state(true)
	weapon_manager.set_trigger_pressed(false)

	if is_multiplayer_authority() and respawn_hud and respawn_hud.has_method("show_countdown"):
		respawn_hud.call("show_countdown", respawn_delay_seconds)

	_report_death_to_world(attacker_peer_id)

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
	network_is_dead = false
	_respawn_ready = false
	_respawn_unlock_time_ms = 0
	velocity = Vector3.ZERO
	_set_dead_visual_state(false)
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
