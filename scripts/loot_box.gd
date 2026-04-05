class_name LootBox
extends RigidBody3D

enum LootType {
	AMMO,
	GUN,
	HEALTH,
}

@export var loot_type: LootType = LootType.AMMO
@export var interaction_distance: float = 3.5
@export var pushable: bool = true
@export var bullet_impulse_strength: float = 5.0
@export var player_push_impulse_strength: float = 12.0
@export var settle_and_lock_after_seconds: float = -1.0
@export var despawn_y_threshold: float = -50.0
@export var open_sound_max_distance: float = 32.0
@export var open_sound_occluded_reduction_db: float = -10.0

var loot_id: int = -1
var _consumed: bool = false
var _remaining_settle_lock_time: float = -1.0
var _contained_weapon_path: String = ""
var _local_player_cache: Node3D
var _next_preview_visibility_update_ms: int = 0

@onready var _gun_preview_label: Label3D = get_node_or_null("GunPreview") as Label3D
@onready var _open_sound_player: AudioStreamPlayer3D = get_node_or_null("OpenSoundPlayer") as AudioStreamPlayer3D

const GROUND_CHECK_DISTANCE := 1.5
const INTERACTION_VERTICAL_TOLERANCE := 2.8

func setup_loot_box(new_loot_id: int, authority_id: int) -> void:
	loot_id = new_loot_id
	set_multiplayer_authority(authority_id)

func set_despawn_y_threshold(y_threshold: float) -> void:
	despawn_y_threshold = y_threshold

func set_contained_weapon_path(weapon_resource_path: String) -> void:
	_contained_weapon_path = weapon_resource_path
	_update_gun_preview_label()

func _ready() -> void:
	add_to_group("loot_boxes")
	_remaining_settle_lock_time = settle_and_lock_after_seconds
	_update_gun_preview_label()

func _process(_delta: float) -> void:
	if loot_type != LootType.GUN or _gun_preview_label == null:
		return

	if Time.get_ticks_msec() < _next_preview_visibility_update_ms:
		return
	_next_preview_visibility_update_ms = Time.get_ticks_msec() + 120

	var local_player := _get_local_authority_player()
	if local_player == null:
		_gun_preview_label.visible = false
		return

	_gun_preview_label.visible = _is_player_in_interaction_range(local_player)

func _get_local_authority_player() -> Node3D:
	if _local_player_cache != null and is_instance_valid(_local_player_cache):
		if _local_player_cache.has_method("is_multiplayer_authority") and _local_player_cache.is_multiplayer_authority():
			return _local_player_cache

	var world := get_tree().current_scene
	if world == null:
		return null
	var players := world.get_node_or_null("Players")
	if players == null:
		return null

	for child in players.get_children():
		if child is Node3D and child.has_method("is_multiplayer_authority") and child.is_multiplayer_authority():
			_local_player_cache = child as Node3D
			return _local_player_cache
	return null

func _is_player_in_interaction_range(player_node: Node3D) -> bool:
	var delta := global_position - player_node.global_position
	if abs(delta.y) > INTERACTION_VERTICAL_TOLERANCE:
		return false
	return Vector2(delta.x, delta.z).length() <= interaction_distance

func _weapon_display_name_from_path(weapon_resource_path: String) -> String:
	if weapon_resource_path == "":
		return "Gun"

	var resource := load(weapon_resource_path)
	if resource != null and resource is Resource:
		var resource_name := str((resource as Resource).resource_name)
		if resource_name != "":
			return resource_name

	var file_name := weapon_resource_path.get_file().get_basename().replace("_", " ")
	if file_name == "":
		return "Gun"
	return file_name.capitalize()

func _update_gun_preview_label() -> void:
	if _gun_preview_label == null:
		return
	if loot_type != LootType.GUN:
		_gun_preview_label.visible = false
		return

	_gun_preview_label.text = _weapon_display_name_from_path(_contained_weapon_path)
	_gun_preview_label.visible = false

func _physics_process(delta: float) -> void:
	if not _is_host_authority():
		return
	if _consumed:
		return

	if global_position.y <= despawn_y_threshold:
		_request_world_despawn()
		return

	if _remaining_settle_lock_time <= 0.0 or freeze:
		return

	_remaining_settle_lock_time = max(_remaining_settle_lock_time - delta, 0.0)
	if _remaining_settle_lock_time == 0.0 and (sleeping or _is_on_ground()):
		_lock_box_in_place()

func _request_world_despawn() -> void:
	_consumed = true
	var world := get_tree().current_scene
	if world != null and world.has_method("despawn_loot_box"):
		world.call("despawn_loot_box", loot_id)

func _lock_box_in_place() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true

func _is_on_ground() -> bool:
	var world_3d := get_viewport().world_3d
	if world_3d == null:
		return false

	var query := PhysicsRayQueryParameters3D.create(global_position, global_position - Vector3.UP * GROUND_CHECK_DISTANCE)
	query.exclude = [self]
	var hit := world_3d.direct_space_state.intersect_ray(query)
	return not hit.is_empty()

func _is_host_authority() -> bool:
	return multiplayer.get_unique_id() == get_multiplayer_authority()

func _get_player_node_for_peer(peer_id: int) -> Node3D:
	var world := get_tree().current_scene
	if world == null:
		return null
	var players := world.get_node_or_null("Players")
	if players == null:
		return null
	return players.get_node_or_null(str(peer_id)) as Node3D

func _peer_can_interact(peer_id: int) -> bool:
	var player_node := _get_player_node_for_peer(peer_id)
	if player_node == null:
		return false
	return _is_player_in_interaction_range(player_node)

@rpc("authority", "call_local", "reliable")
func sync_open_sound(sound_origin: Vector3) -> void:
	_play_open_sound_local(sound_origin)

func _play_open_sound_local(sound_origin: Vector3) -> void:
	if _open_sound_player == null or _open_sound_player.stream == null:
		return

	var transient_player := _open_sound_player.duplicate() as AudioStreamPlayer3D
	if transient_player == null:
		return

	var world_root: Node = get_tree().current_scene
	if world_root == null:
		world_root = get_tree().root
	world_root.add_child(transient_player)

	var volume_db := _open_sound_player.volume_db
	if _is_open_sound_occluded_from_listener(sound_origin):
		volume_db += open_sound_occluded_reduction_db

	transient_player.global_position = sound_origin
	transient_player.max_distance = open_sound_max_distance
	transient_player.volume_db = volume_db
	transient_player.finished.connect(Callable(transient_player, "queue_free"), CONNECT_ONE_SHOT)
	transient_player.play()

func _is_open_sound_occluded_from_listener(sound_origin: Vector3) -> bool:
	var listener_camera := get_viewport().get_camera_3d()
	if listener_camera == null:
		return false

	var world_3d := get_world_3d()
	if world_3d == null:
		return false

	var exclude: Array = [self]
	var listener_player := listener_camera.get_parent()
	if listener_player and listener_player.get_parent() and listener_player.get_parent() is CollisionObject3D:
		exclude.append(listener_player.get_parent())

	var query := PhysicsRayQueryParameters3D.create(listener_camera.global_position, sound_origin)
	query.exclude = exclude
	var hit := world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false

	var collider = hit.get("collider")
	return collider != self

func interact_from_peer(peer_id: int) -> void:
	if not _is_host_authority() or _consumed:
		return
	if not _peer_can_interact(peer_id):
		return
	_consumed = true
	var world := get_tree().current_scene
	if world != null and world.has_method("consume_loot_box"):
		world.consume_loot_box(loot_id, peer_id, int(loot_type))

@rpc("any_peer", "call_remote", "reliable")
func request_interact() -> void:
	if not _is_host_authority() or _consumed:
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	interact_from_peer(sender_id)

func apply_bullet_impulse(hit_position: Vector3, bullet_direction: Vector3, strength_scale: float = 1.0) -> void:
	if not pushable or freeze:
		return
	if bullet_direction.is_zero_approx():
		return
	var impulse_strength: float = bullet_impulse_strength * max(strength_scale, 0.0)
	if impulse_strength <= 0.0:
		return
	var impulse: Vector3 = bullet_direction.normalized() * (impulse_strength / max(mass, 0.001))
	apply_impulse(impulse, hit_position - global_position)

@rpc("any_peer", "call_remote", "unreliable")
func request_bullet_impulse(hit_position: Vector3, bullet_direction: Vector3, strength_scale: float = 1.0) -> void:
	if not _is_host_authority():
		return
	apply_bullet_impulse(hit_position, bullet_direction, strength_scale)
