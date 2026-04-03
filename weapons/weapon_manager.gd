class_name WeaponManager
extends Node3D

@export var current_weapon : WeaponResource
@export var muzzle_flash_anchor_path : NodePath = NodePath("../EquipmentPivot/Hand/MuzzleFlashAnchor")
@export var shot_max_distance: float = 70.0
@export var occluded_shot_volume_reduction_db: float = -10.0
@export var world_model_vertical_aim_only: bool = true
@export var world_model_pitch_scale: float = 1.0
@export var world_model_pitch_neutral: float = 0.0
@export var world_model_pitch_min: float = -1.1
@export var world_model_pitch_max: float = 0.8
@export var world_model_mesh_yaw_offset: float = 0.0
@export var world_model_sync_from_authority: bool = true
@export var world_model_follow_ik_only: bool = true

@onready var bullet_cast : RayCast3D = $"../EquipmentPivot/Hand/BulletRayCast"
@onready var muzzle_flash_anchor : Node3D = get_node_or_null(muzzle_flash_anchor_path) as Node3D
@onready var camera_arm : Node = $"../SpringArm3D"
@onready var player : Node = $".."
@onready var fire_rate_timer : Timer = $FireRateTimer
@export var view_model_container : Node3D
@export var world_model_container : Node3D

var current_view_model : Node3D
var current_world_model : Node3D
var _world_model_base_local_basis: Basis = Basis.IDENTITY
var _world_model_base_local_position: Vector3 = Vector3.ZERO
var _world_model_base_local_scale: Vector3 = Vector3.ONE

@export var allow_shoot := true

# Audio
@onready var audio_stream_player := $AudioStreamPlayer3D

func _clear_weapon_models() -> void:
	if current_view_model and is_instance_valid(current_view_model):
		current_view_model.queue_free()
	if current_world_model and is_instance_valid(current_world_model):
		current_world_model.queue_free()
	current_view_model = null
	current_world_model = null
	_world_model_base_local_basis = Basis.IDENTITY
	_world_model_base_local_position = Vector3.ZERO
	_world_model_base_local_scale = Vector3.ONE

func _resolve_world_model_container() -> void:
	if world_model_container and is_instance_valid(world_model_container):
		return
	if not player or not is_instance_valid(player):
		return

	var candidate: Node = player.get_node_or_null("Character/Container/orange_astro/Armature/Skeleton3D/BoneAttachment3D/WorldModel")
	if candidate is Node3D:
		world_model_container = candidate as Node3D
		return

	candidate = player.get_node_or_null("Character/Container/orange_astro/Armature/Skeleton3D/BoneAttachment3D")
	if candidate is Node3D:
		world_model_container = candidate as Node3D
		return

	candidate = player.get_node_or_null("%WorldModel")
	if candidate is Node3D:
		world_model_container = candidate as Node3D
		return

	var found := player.find_child("WorldModel", true, false)
	if found is Node3D:
		world_model_container = found as Node3D

func refill_current_weapon_reserve_to_max() -> void:
	if not current_weapon:
		return
	current_weapon.reserve_ammo = max(current_weapon.max_reserve_ammo, 0)

func equip_weapon_template(weapon_template: WeaponResource, fill_full_ammo: bool = false) -> void:
	if not weapon_template:
		return

	if current_weapon:
		current_weapon.trigger_down = false
		current_weapon.is_equipped = false

	_clear_weapon_models()
	stop_sounds()

	current_weapon = weapon_template.duplicate(true)
	if fill_full_ammo:
		current_weapon.current_ammo = max(current_weapon.magazine_capacity, 0)
		current_weapon.reserve_ammo = max(current_weapon.max_reserve_ammo, 0)

	update_weapon_model()

func update_weapon_model() -> void:
	_clear_weapon_models()
	_resolve_world_model_container()

	if current_weapon != null:
		if current_weapon.resource_path != "" and current_weapon.weapon_manager != self:
			current_weapon = current_weapon.duplicate(true)

		current_weapon.weapon_manager = self
		
		if view_model_container and current_weapon.view_model:
			current_view_model = current_weapon.view_model.instantiate()
			view_model_container.add_child(current_view_model)
			current_view_model.position = current_weapon.view_model_pos;
			current_view_model.rotation = current_weapon.view_model_rot;
			current_view_model.scale = current_weapon.view_model_scale;

		if world_model_container and current_weapon.world_model:
			current_world_model = current_weapon.world_model.instantiate()
			world_model_container.add_child(current_world_model)
			current_world_model.position = current_weapon.world_model_pos;
			current_world_model.rotation = current_weapon.world_model_rot;
			current_world_model.scale = current_weapon.world_model_scale;
			_world_model_base_local_basis = current_world_model.basis.orthonormalized()
			_world_model_base_local_position = current_world_model.position
			_world_model_base_local_scale = current_world_model.scale

		fire_rate_timer.wait_time = max(current_weapon.fire_rate_time, 0.01)
		if muzzle_flash_anchor:
			muzzle_flash_anchor.position = current_weapon.muzzle_flash_position
			
		current_weapon.is_equipped = true
	
	if player.has_method("update_view_and_world_model_masks"):
		player.update_view_and_world_model_masks()

func play_anim(anim_id : String) -> void:
	if not current_view_model or not is_instance_valid(current_view_model):
		return
	var anim_player : AnimationPlayer = current_view_model.get_node_or_null("AnimationPlayer")
	if not anim_player or not anim_player.has_animation(anim_id):
		return
		
	anim_player.seek(0.0)
	anim_player.play(anim_id)

func get_anim_length(anim_id: String) -> float:
	if not current_view_model or not is_instance_valid(current_view_model):
		return 0.0
	var anim_player : AnimationPlayer = current_view_model.get_node_or_null("AnimationPlayer")
	if not anim_player or not anim_player.has_animation(anim_id):
		return 0.0
	return anim_player.get_animation(anim_id).length

func queue_anim(anim_id : String):
	if not current_view_model or not is_instance_valid(current_view_model):
		return
	var anim_player : AnimationPlayer = current_view_model.get_node_or_null("AnimationPlayer")
	if not anim_player: return
	anim_player.queue(anim_id)

func play_sound(sound : AudioStream):
	_play_sound_internal(sound, 0.0)

func _play_sound_internal(sound: AudioStream, volume_db: float) -> void:
	if not sound or not audio_stream_player or not is_instance_valid(audio_stream_player):
		return
	if audio_stream_player.stream != sound:
		audio_stream_player.stream = sound
	audio_stream_player.max_distance = shot_max_distance
	audio_stream_player.volume_db = volume_db
	audio_stream_player.play()

func _is_sound_occluded_from_listener(sound_origin: Vector3) -> bool:
	var listener_camera = get_viewport().get_camera_3d()
	if not listener_camera:
		return false

	var exclude: Array = []
	if player is CollisionObject3D:
		exclude.append(player)

	var listener_player = listener_camera.get_parent()
	if listener_player and listener_player.get_parent() and listener_player.get_parent() is CollisionObject3D:
		exclude.append(listener_player.get_parent())

	var query := PhysicsRayQueryParameters3D.create(listener_camera.global_position, sound_origin)
	query.exclude = exclude
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider = hit.get("collider")
	return collider != player

@rpc("any_peer", "call_remote", "unreliable")
func play_remote_shot_sound() -> void:
	if not current_weapon or not current_weapon.shoot_sound:
		return

	var volume_db := 0.0
	var sound_origin := global_position
	if audio_stream_player and is_instance_valid(audio_stream_player):
		sound_origin = audio_stream_player.global_position
	if _is_sound_occluded_from_listener(sound_origin):
		volume_db += occluded_shot_volume_reduction_db
	_play_sound_internal(current_weapon.shoot_sound, volume_db)

func stop_sounds():
	if audio_stream_player and is_instance_valid(audio_stream_player):
		audio_stream_player.stop()

func set_trigger_pressed(pressed: bool) -> void:
	if not current_weapon:
		return
	current_weapon.trigger_down = pressed and allow_shoot

func request_reload() -> void:
	if not current_weapon:
		return
	current_weapon.reload_pressed()

func _physics_process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		return
	if not player.is_multiplayer_authority():
		return
	if not current_weapon or not allow_shoot:
		return
	if not current_weapon.trigger_down:
		return
	_try_fire()

func _process(delta: float) -> void:
	if current_weapon:
		current_weapon.on_process(delta)
	if not world_model_follow_ik_only:
		_update_world_model_pitch_only_aim()

func _basis_from_to(from_dir: Vector3, to_dir: Vector3) -> Basis:
	var from_n := from_dir.normalized()
	var to_n := to_dir.normalized()
	var dot: float = clampf(from_n.dot(to_n), -1.0, 1.0)
	if dot >= 0.9999:
		return Basis.IDENTITY

	var axis := from_n.cross(to_n)
	if axis.length_squared() <= 0.0001:
		axis = Vector3.UP.cross(from_n)
		if axis.length_squared() <= 0.0001:
			axis = Vector3.RIGHT.cross(from_n)
	axis = axis.normalized()
	return Basis(axis, acos(dot))

func _update_world_model_pitch_only_aim() -> void:
	if not world_model_vertical_aim_only:
		return
	if not current_world_model or not is_instance_valid(current_world_model):
		return
	if not player or not is_instance_valid(player):
		return
	if not (player is Node3D):
		return
	if not camera_arm or not is_instance_valid(camera_arm):
		return

	var parent_node := current_world_model.get_parent_node_3d()
	if parent_node == null:
		return

	if world_model_sync_from_authority and not player.is_multiplayer_authority():
		var replicated_forward: Variant = player.get("network_world_model_forward")
		var replicated_up: Variant = player.get("network_world_model_up")
		if replicated_forward is Vector3 and replicated_up is Vector3:
			var synced_forward: Vector3 = (replicated_forward as Vector3)
			var synced_up: Vector3 = (replicated_up as Vector3)
			if synced_forward.length_squared() > 0.0001 and synced_up.length_squared() > 0.0001:
				synced_forward = synced_forward.normalized()
				synced_up = synced_up.normalized()
				if absf(synced_forward.dot(synced_up)) > 0.98:
					synced_up = Vector3.UP
				var synced_right: Vector3 = synced_forward.cross(synced_up)
				if synced_right.length_squared() > 0.0001:
					synced_right = synced_right.normalized()
					synced_up = synced_right.cross(synced_forward).normalized()
					var synced_global_basis := Basis(synced_right, synced_up, -synced_forward).orthonormalized()
					var synced_local_basis: Basis = (parent_node.global_transform.basis.inverse() * synced_global_basis).orthonormalized()
					current_world_model.basis = synced_local_basis.scaled(_world_model_base_local_scale)
					current_world_model.position = _world_model_base_local_position
					return

	var player_up: Vector3 = Vector3.UP
	var yaw_basis := Basis(player_up, camera_arm.rotation.y)
	var yaw_forward: Vector3 = (yaw_basis * Vector3.FORWARD).normalized()
	var yaw_right: Vector3 = yaw_forward.cross(player_up)
	if yaw_right.length_squared() <= 0.0001:
		yaw_right = Vector3.RIGHT
	yaw_right = yaw_right.normalized()

	var local_pitch: float = camera_arm.rotation.x
	var pitch_delta: float = clampf((local_pitch - world_model_pitch_neutral) * world_model_pitch_scale, world_model_pitch_min, world_model_pitch_max)
	var pitched_forward: Vector3 = (Basis(yaw_right, pitch_delta) * yaw_forward).normalized()
	# Guarantee the muzzle always points away from the player body.
	if pitched_forward.dot(yaw_forward) < 0.0:
		pitched_forward = -pitched_forward

	# Apply yaw correction around player-up to keep the gun upright while honoring per-weapon yaw.
	var weapon_yaw_offset: float = 0.0
	var weapon_pitch_offset: float = 0.0
	var weapon_roll_offset: float = 0.0
	if current_weapon:
		weapon_yaw_offset = current_weapon.world_model_rot.y
		weapon_pitch_offset = current_weapon.world_model_rot.x
		weapon_roll_offset = current_weapon.world_model_rot.z
	var corrected_forward: Vector3 = (Basis(player_up, world_model_mesh_yaw_offset + weapon_yaw_offset) * pitched_forward).normalized()
	if corrected_forward.dot(yaw_forward) < 0.0:
		corrected_forward = -corrected_forward

	# Lock roll by deriving right from player up and the desired forward direction.
	var target_right: Vector3 = corrected_forward.cross(player_up)
	if target_right.length_squared() <= 0.0001:
		target_right = yaw_right
	target_right = target_right.normalized()
	var target_up: Vector3 = target_right.cross(corrected_forward).normalized()
	var target_global_basis := Basis(target_right, target_up, -corrected_forward).orthonormalized()

	# Apply per-weapon pitch/roll offsets after upright yaw solve.
	if absf(weapon_pitch_offset) > 0.0001 or absf(weapon_roll_offset) > 0.0001:
		var pitch_offset_basis := Basis(target_right, weapon_pitch_offset)
		var roll_offset_basis := Basis(corrected_forward, weapon_roll_offset)
		target_global_basis = (roll_offset_basis * pitch_offset_basis * target_global_basis).orthonormalized()
		target_right = target_global_basis.x.normalized()
		target_up = target_global_basis.y.normalized()
		corrected_forward = (-target_global_basis.z).normalized()

	if world_model_sync_from_authority and player.is_multiplayer_authority():
		player.set("network_world_model_forward", corrected_forward)
		player.set("network_world_model_up", target_up)

	var target_local_basis: Basis = (parent_node.global_transform.basis.inverse() * target_global_basis).orthonormalized()

	current_world_model.basis = target_local_basis.scaled(_world_model_base_local_scale)
	current_world_model.position = _world_model_base_local_position

func _try_fire() -> void:
	if not current_weapon:
		return
	if not current_weapon.can_fire_shot():
		current_weapon.reload_pressed()
		return
	if not fire_rate_timer.is_stopped():
		return

	fire_rate_timer.start()
	_apply_recoil()
	current_weapon.fire_shot()
	play_remote_shot_sound.rpc()
	play_fire_effects.rpc()

	if player.has_signal("firing"):
		player.emit_signal("firing", true)

	if not bullet_cast:
		return

	bullet_cast.force_raycast_update()
	if not bullet_cast.is_colliding():
		return

	var hit_obj = bullet_cast.get_collider()
	var col_point = bullet_cast.get_collision_point()
	var normal = bullet_cast.get_collision_normal()
	var bullet_dir = (col_point - bullet_cast.global_position).normalized()
	var spawn_decal := false

	if hit_obj is Node and hit_obj.has_method("hurt"):
		hit_obj.hurt.rpc_id(hit_obj.get_multiplayer_authority(), current_weapon.damage)
		sync_impact.rpc("enemy", col_point, normal, bullet_dir)
	else:
		if hit_obj is Node and hit_obj.has_method("request_bullet_impulse"):
			var hit_node := hit_obj as Node
			var authority_id := hit_node.get_multiplayer_authority()
			var strength_scale: float = max(current_weapon.damage * 0.5, 10.0)
			if authority_id == multiplayer.get_unique_id() and hit_node.has_method("apply_bullet_impulse"):
				hit_node.call("apply_bullet_impulse", col_point, bullet_dir, strength_scale)
			elif authority_id > 0:
				hit_node.rpc_id(authority_id, "request_bullet_impulse", col_point, bullet_dir, strength_scale)
			spawn_decal = false
		elif hit_obj is StaticBody3D:
			# Restrict decals to static terrain-like geometry.
			spawn_decal = true
		sync_impact.rpc("terrain", col_point, normal, bullet_dir)
		if spawn_decal:
			sync_impact.rpc("decal", col_point, normal, bullet_dir)

func _apply_recoil() -> void:
	if not camera_arm or not camera_arm.has_method("apply_recoil"):
		return
	var kick = Vector2(current_weapon.recoil_power.x, randf_range(-current_weapon.recoil_power.y, current_weapon.recoil_power.y))
	camera_arm.apply_recoil(kick)

@rpc("call_local")
func play_fire_effects() -> void:
	if not current_weapon or not current_weapon.muzzle_flash_scene:
		return

	var flash = current_weapon.muzzle_flash_scene.instantiate()
	if not (flash is Node3D):
		return
	var flash_node := flash as Node3D

	add_child(flash_node)
	var anchor : Node3D = muzzle_flash_anchor if muzzle_flash_anchor else bullet_cast
	if anchor:
		flash_node.global_transform = anchor.global_transform
		if not muzzle_flash_anchor and current_weapon.muzzle_flash_position != Vector3.ZERO:
			flash_node.global_transform = flash_node.global_transform.translated_local(current_weapon.muzzle_flash_position)

	if flash_node is GPUParticles3D:
		(flash_node as GPUParticles3D).emitting = true

@rpc("any_peer", "call_local")
func sync_impact(type: String, pos: Vector3, normal: Vector3, dir: Vector3):
	ImpactManager.spawn_impact(type, pos, normal, dir)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	fire_rate_timer.one_shot = true
	_resolve_world_model_container()
	if current_weapon:
		fire_rate_timer.wait_time = max(current_weapon.fire_rate_time, 0.01)
		if muzzle_flash_anchor:
			muzzle_flash_anchor.position = current_weapon.muzzle_flash_position

func _exit_tree() -> void:
	if current_weapon:
		current_weapon.trigger_down = false
		if current_weapon.weapon_manager == self:
			current_weapon.weapon_manager = null
	stop_sounds()
