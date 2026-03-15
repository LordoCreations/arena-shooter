extends Node

const SERVER_PORT = 9999
var SERVER_IP = "127.0.0.1"

var multiplayer_scene = preload("res://player.tscn")
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
