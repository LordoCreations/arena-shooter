extends Node

const LOBBY_NAME = "3DShooter"
const LOBBY_MODE = "CoOP"

var multiplayer_scene = preload("res://scenes/player.tscn")
var multiplayer_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
var _hosted_lobby_id = 0
var _current_lobby_id = 0

# References based on your Scene Tree image
@export var _players_spawn_node: Node
@onready var notifications = get_node_or_null("../../CanvasLayer/Notifications")

func _ready():
	Steam.connect("lobby_created", _on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	
	# Optional: Notify system is ready
	notifications.notify("System Ready. Steam initialized.", false)

func become_host():
	notifications.notify("Starting host...", true)
	
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, SteamManager.lobby_max)

	multiplayer.peer_connected.connect(_add_player_to_game)
	multiplayer.peer_disconnected.connect(_del_player)

	if not OS.has_feature("dedicated_server"):
		_add_player_to_game(1)

func _on_lobby_created(connect_status: int, lobby_id):
	if connect_status == Steam.RESULT_OK:
		notifications.notify("Lobby Created! ID: %s" % lobby_id, true)
		
		_hosted_lobby_id = lobby_id
		_current_lobby_id = lobby_id

		multiplayer_peer.host_with_lobby(lobby_id)
		multiplayer.multiplayer_peer = multiplayer_peer
		
		Steam.setLobbyJoinable(_hosted_lobby_id, true)
		Steam.setLobbyData(_hosted_lobby_id, "name", LOBBY_NAME)
		Steam.setLobbyData(_hosted_lobby_id, "mode", LOBBY_MODE)
	else:
		notifications.notify("Failed to create lobby! Status: %s" % connect_status, true)

func join_as_client(lobby_id):
	notifications.notify("Attempting to join lobby: %s" % lobby_id, false)
	Steam.joinLobby(lobby_id)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, _response: int) -> void:
	_current_lobby_id = lobby_id
	if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
		# Use notify instead of print, but maybe keep it subtle since it's an internal check
		notifications.notify("You are the owner, bypassing client connection.", false)
		return
		
	notifications.notify("Successfully joined lobby: %s" % lobby_id, true)
	multiplayer_peer.connect_to_lobby(lobby_id)
	multiplayer.multiplayer_peer = multiplayer_peer

func list_lobbies():
	notifications.notify("Requesting lobby list...", false)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("name", "3DShooter", Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func get_lobby_display() -> String:
	if _current_lobby_id == 0:
		return ""
	return str(_current_lobby_id)

func is_host() -> bool:
	if _current_lobby_id == 0:
		return false
	return Steam.getLobbyOwner(_current_lobby_id) == Steam.getSteamID()

func get_lobby_members() -> Array:
	var members: Array = []
	if _current_lobby_id == 0:
		return members
	if Steam.has_method("getNumLobbyMembers") and Steam.has_method("getLobbyMemberByIndex"):
		var count = Steam.getNumLobbyMembers(_current_lobby_id)
		for i in count:
			var steam_id = Steam.getLobbyMemberByIndex(_current_lobby_id, i)
			var name := ""
			if Steam.has_method("getFriendPersonaName"):
				name = Steam.getFriendPersonaName(steam_id)
			if name == "":
				name = "Steam %s" % steam_id
			var can_kick = is_host() and steam_id != Steam.getSteamID()
			members.append({
				"id": steam_id,
				"id_type": "steam",
				"name": name,
				"can_kick": can_kick,
				"can_transfer": can_kick and Steam.has_method("setLobbyOwner"),
			})
		return members
		
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

func kick_member(member_id, id_type: String = "peer") -> void:
	if not is_host():
		if notifications:
			notifications.notify("Only the host can kick players.", true)
		return
	if id_type == "steam":
		if notifications:
			notifications.notify("Kicking via Steam lobby: use multiplayer disconnect.", true)
	multiplayer_peer.disconnect_peer(member_id)

func transfer_lobby_ownership(member_id, id_type: String = "peer") -> void:
	if not is_host():
		if notifications:
			notifications.notify("Only the host can transfer ownership.", true)
		return
	if id_type == "steam" and Steam.has_method("setLobbyOwner"):
		Steam.setLobbyOwner(_current_lobby_id, member_id)
	elif notifications:
		notifications.notify("Lobby ownership transfer is unavailable.", true)

func _add_player_to_game(id: int):
	notifications.notify("Player %s joined the game!" % id, true)
	
	var player_to_add = multiplayer_scene.instantiate()
	player_to_add.hide()
	player_to_add.player_id = id
	player_to_add.name = str(id)
	
	if _players_spawn_node:
		_players_spawn_node.add_child(player_to_add, true)
	else:
		notifications.notify("Error: Spawn node not set!", true)
	
func _del_player(id: int):
	notifications.notify("Player %s left the game." % id, true)
	
	if not _players_spawn_node or not _players_spawn_node.has_node(str(id)):
		return
		
	_players_spawn_node.get_node(str(id)).queue_free()
