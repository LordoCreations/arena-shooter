extends Node

const SERVER_PORT = 9999
var SERVER_IP = "127.0.0.1"

var multiplayer_scene = preload("res://scenes/player.tscn")
var multiplayer_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
@export var _players_spawn_node: Node

@onready var notifications = get_node_or_null("../../CanvasLayer/Notifications")

func become_host():
	notifications.notify("Starting host...", false)

	multiplayer_peer.create_server(SERVER_PORT)
	multiplayer.multiplayer_peer = multiplayer_peer

	multiplayer.peer_connected.connect(_add_player_to_game)
	multiplayer.peer_disconnected.connect(_del_player)

	if not OS.has_feature("dedicated_server"):
		_add_player_to_game(multiplayer.get_unique_id())

	# make notificatopm stick longer
	var ip = get_local_ip()
	notifications.notify("Host Active! IP: " + str(ip), true)

	# copy IP to clipboard for convenience
	DisplayServer.clipboard_set(ip)

func join_as_client(address_to_join: String):
	notifications.notify("Attempting to join: " + address_to_join, false)

	SERVER_IP = address_to_join
	multiplayer_peer.create_client(SERVER_IP, SERVER_PORT)
	multiplayer.multiplayer_peer = multiplayer_peer

func _add_player_to_game(id: int):
	notifications.notify("Player %s joined!" % id, false)

	var player_to_add = multiplayer_scene.instantiate()
	player_to_add.hide()
	player_to_add.player_id = id
	player_to_add.name = str(id)

	_players_spawn_node.add_child(player_to_add, true)

func _del_player(id: int):
	notifications.notify("Player %s left!" % id, false)
	if not _players_spawn_node.has_node(str(id)): return
	_players_spawn_node.get_node(str(id)).queue_free()

func get_local_ip() -> String:
	var ip_list = IP.get_local_addresses()
	for ip in ip_list:
		if ip.split(".").size() == 4 and not ip.begins_with("127."):
			if ip.begins_with("192.168.") or ip.begins_with("10."):
				return ip
	return "127.0.0.1"

func get_lobby_display() -> String:
	if multiplayer.is_server():
		return "%s:%s" % [get_local_ip(), SERVER_PORT]
	return "%s:%s" % [SERVER_IP, SERVER_PORT]

func is_host() -> bool:
	return multiplayer.is_server()

func get_lobby_members() -> Array:
	var members: Array = []
	var local_id = multiplayer.get_unique_id()
	members.append({
		"id": local_id,
		"id_type": "peer",
		"name": "Player %s" % local_id,
		"can_kick": false,
		"can_transfer": false,
	})
	for peer_id in multiplayer.get_peers():
		members.append({
			"id": peer_id,
			"id_type": "peer",
			"name": "Player %s" % peer_id,
			"can_kick": multiplayer.is_server(),
			"can_transfer": false,
		})
	return members

func kick_member(member_id, _id_type: String = "peer") -> void:
	if not multiplayer.is_server():
		if notifications:
			notifications.notify("Only the host can kick players.", true)
		return
	if member_id == multiplayer.get_unique_id():
		return
	multiplayer_peer.disconnect_peer(member_id)
