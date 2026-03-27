extends Node

enum NETWORK_TYPE {ENET, STEAM}

var active_network_type: NETWORK_TYPE = NETWORK_TYPE.ENET
var enet_network_scene := preload("res://multiplayer/networks/enet_network.tscn")
var steam_network_scene := preload("res://multiplayer/networks/steam_network.tscn")
var active_network


@export var _players_spawn_node: Node3D

func _build_multiplayer_network():
	if not active_network:	
		print("Setting active_network")
		
		MultiplayerManager.multiplayer_mode_enabled = true
		
		match active_network_type:
			NETWORK_TYPE.ENET:
				print("Setting network type to ENet")
				_set_active_network(enet_network_scene)
			NETWORK_TYPE.STEAM:
				print("Setting network type to Steam")
				_set_active_network(steam_network_scene)
			_:
				print("No match for network type!")

func _set_active_network(active_network_scene):
	var network_scene_initialized = active_network_scene.instantiate()
	active_network = network_scene_initialized
	active_network._players_spawn_node = _players_spawn_node
	add_child(active_network)

func become_host(is_dedicated_server = false):
	_build_multiplayer_network()
	MultiplayerManager.host_mode_enabled = true if is_dedicated_server == false else false
	active_network.become_host()
	
func join_as_client(lobby_id = 0, address = ""):
	_build_multiplayer_network()
	if active_network_type == NETWORK_TYPE.STEAM:
		active_network.join_as_client(lobby_id)
	else:
		active_network.join_as_client(address)

func list_lobbies():
	_build_multiplayer_network()
	active_network.list_lobbies()

func get_lobby_display() -> String:
	if not active_network:
		return ""
	if active_network.has_method("get_lobby_display"):
		return active_network.get_lobby_display()
	return ""

func is_host() -> bool:
	if not active_network:
		return false
	if active_network.has_method("is_host"):
		return active_network.is_host()
	return MultiplayerManager.host_mode_enabled

func get_lobby_members() -> Array:
	if not active_network:
		return []
	if active_network.has_method("get_lobby_members"):
		return active_network.get_lobby_members()
	return []

func kick_member(member_id, id_type: String = "peer") -> void:
	if active_network and active_network.has_method("kick_member"):
		active_network.kick_member(member_id, id_type)

func transfer_lobby_ownership(member_id, id_type: String = "peer") -> void:
	if active_network and active_network.has_method("transfer_lobby_ownership"):
		active_network.transfer_lobby_ownership(member_id, id_type)

func shutdown_lobby(host_shutdown: bool = false) -> void:
	if active_network and active_network.has_method("shutdown_lobby"):
		active_network.shutdown_lobby(host_shutdown)
	else:
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if is_instance_valid(active_network):
		active_network.queue_free()
	active_network = null
