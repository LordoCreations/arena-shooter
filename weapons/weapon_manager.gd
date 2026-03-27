class_name WeaponManager
extends Node3D

@export var current_weapon : WeaponResource
@export var muzzle_flash_anchor_path : NodePath = NodePath("../EquipmentPivot/Hand/MuzzleFlashAnchor")
@export var shot_max_distance: float = 70.0
@export var occluded_shot_volume_reduction_db: float = -10.0

@onready var bullet_cast : RayCast3D = $"../EquipmentPivot/Hand/BulletRayCast"
@onready var muzzle_flash_anchor : Node3D = get_node_or_null(muzzle_flash_anchor_path) as Node3D
@onready var camera_arm : Node = $"../SpringArm3D"
@onready var player : Node = $".."
@onready var fire_rate_timer : Timer = $FireRateTimer
@export var view_model_container : Node3D
@export var world_model_container : Node3D

var current_view_model : Node3D
var current_world_model : Node3D

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
