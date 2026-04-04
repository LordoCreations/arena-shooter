extends Node

signal username_changed(peer_id: int, username: String)

enum NETWORK_TYPE {ENET, STEAM}

const USERNAME_MAX_LENGTH := 50
const DEFAULT_USERNAME_PREFIX := "Player"
const DEFAULT_RANDOM_MIN := 100
const DEFAULT_RANDOM_MAX := 999
const DEFAULT_MOUSE_SENSITIVITY_MULTIPLIER := 4.0
const MIN_MOUSE_SENSITIVITY_MULTIPLIER := 0.1
const MAX_MOUSE_SENSITIVITY_MULTIPLIER := 20.0

var host_mode_enabled = false
var multiplayer_mode_enabled = false
var respawn_point = Vector3(0, 20, 0)

var pending_action: String = ""
var pending_address: String = ""
var pending_lobby_id: int = 0
var pending_network_type: NETWORK_TYPE = NETWORK_TYPE.ENET

var player_username: String = ""
var controls_enabled: bool = true
var player_usernames: Dictionary = {}
var _local_default_username: String = ""
var user_mouse_sensitivity: float = DEFAULT_MOUSE_SENSITIVITY_MULTIPLIER


func _get_or_create_local_default_username() -> String:
	if not _local_default_username.is_empty():
		return _local_default_username

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var suffix: int = rng.randi_range(DEFAULT_RANDOM_MIN, DEFAULT_RANDOM_MAX)
	_local_default_username = "%s%d" % [DEFAULT_USERNAME_PREFIX, suffix]
	return _local_default_username


func sanitize_username(raw_username: String, fallback_peer_id: int = -1) -> String:
	var cleaned := raw_username.strip_edges()
	if cleaned.length() > USERNAME_MAX_LENGTH:
		cleaned = cleaned.substr(0, USERNAME_MAX_LENGTH)
	if cleaned.is_empty() and fallback_peer_id < 0:
		pass

	return cleaned


func set_local_preferred_username(raw_username: String, fallback_peer_id: int = -1) -> String:
	player_username = sanitize_username(raw_username, fallback_peer_id)
	return player_username


func set_mouse_sensitivity_multiplier(raw_value: float) -> float:
	user_mouse_sensitivity = clampf(raw_value, MIN_MOUSE_SENSITIVITY_MULTIPLIER, MAX_MOUSE_SENSITIVITY_MULTIPLIER)
	return user_mouse_sensitivity


func get_mouse_sensitivity_multiplier() -> float:
	return user_mouse_sensitivity


func set_local_username_and_broadcast(raw_username: String, peer_id: int = -1) -> String:
	if peer_id <= 0 and multiplayer.multiplayer_peer != null:
		peer_id = multiplayer.get_unique_id()

	player_username = sanitize_username(raw_username, peer_id)
	if player_username.is_empty() and peer_id > 0:
		player_username = _get_or_create_local_default_username()
	register_local_peer_username(peer_id)
	return player_username


func get_display_name(peer_id: int) -> String:
	if player_usernames.has(peer_id):
		var synced_name := str(player_usernames[peer_id]).strip_edges()
		if not synced_name.is_empty():
			return synced_name
	return "%s%s" % [DEFAULT_USERNAME_PREFIX, str(peer_id)]


func clear_peer_username(peer_id: int) -> void:
	if not player_usernames.has(peer_id):
		return
	player_usernames.erase(peer_id)
	username_changed.emit(peer_id, "")


func register_local_peer_username(peer_id: int = -1) -> void:
	if peer_id <= 0 and multiplayer.multiplayer_peer != null:
		peer_id = multiplayer.get_unique_id()

	if player_username.is_empty() and peer_id > 0:
		player_username = _get_or_create_local_default_username()

	player_username = sanitize_username(player_username, peer_id)
	if peer_id <= 0:
		return

	if multiplayer.multiplayer_peer == null:
		_set_peer_username_local(peer_id, player_username)
		return

	if multiplayer.is_server():
		_sync_peer_username.rpc(peer_id, player_username)
	else:
		_submit_peer_username.rpc_id(1, peer_id, player_username)


func sync_all_usernames_to_peer(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if multiplayer.multiplayer_peer == null:
		return
	if not multiplayer.is_server():
		return

	for known_peer_id in player_usernames.keys():
		_sync_peer_username.rpc_id(peer_id, int(known_peer_id), str(player_usernames[known_peer_id]))


func _set_peer_username_local(peer_id: int, username_value: String) -> void:
	var cleaned := sanitize_username(username_value, peer_id)
	if cleaned.is_empty():
		cleaned = "%s%d" % [DEFAULT_USERNAME_PREFIX, peer_id]
	player_usernames[peer_id] = cleaned
	username_changed.emit(peer_id, cleaned)


@rpc("any_peer", "call_remote", "reliable")
func _submit_peer_username(peer_id: int, requested_username: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id > 0 and sender_id != peer_id:
		peer_id = sender_id

	var cleaned := sanitize_username(requested_username, peer_id)
	_sync_peer_username.rpc(peer_id, cleaned)


@rpc("any_peer", "call_local", "reliable")
func _sync_peer_username(peer_id: int, synced_username: String) -> void:
	_set_peer_username_local(peer_id, synced_username)
