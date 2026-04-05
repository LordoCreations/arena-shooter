extends Node

const LOBBY_MODE = "CoOP"
const LOBBY_GAME_KEY = "game_key"
const LOBBY_GAME_VALUE = "arena_shooter"
const LOBBY_RESULT_LIMIT := 100
const JOIN_TIMEOUT_SECONDS := 3.0
const AUTO_RETURN_SECONDS := 3.0
var popup_template_scene := preload("res://scenes/ui/menu_popup_template.tscn")

var multiplayer_scene = preload("res://scenes/player.tscn")
var multiplayer_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new()
var _hosted_lobby_id = 0
var _current_lobby_id = 0
var _spawn_host_on_lobby_created := false

@export var _players_spawn_node: Node
@onready var notifications = get_node_or_null("../../CanvasLayer/Notifications")
@onready var _join_timeout_timer: Timer = Timer.new()
@onready var _failure_auto_return_timer: Timer = Timer.new()
@onready var _failure_countdown_timer: Timer = Timer.new()

var _showing_failure_popup: bool = false
var _failure_dialog
var _failure_message_base: String = ""
var _failure_seconds_remaining: int = 0

func _ready() -> void:
	Steam.connect("lobby_created", _on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)

	_join_timeout_timer.one_shot = true
	_join_timeout_timer.timeout.connect(_on_join_timeout)
	add_child(_join_timeout_timer)

	_failure_auto_return_timer.one_shot = true
	_failure_auto_return_timer.timeout.connect(_on_failure_popup_auto_return)
	add_child(_failure_auto_return_timer)

	_failure_countdown_timer.one_shot = false
	_failure_countdown_timer.wait_time = 1.0
	_failure_countdown_timer.timeout.connect(_on_failure_countdown_tick)
	add_child(_failure_countdown_timer)

	notifications.notify("System Ready. Steam initialized.", false)

func _connect_multiplayer_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_add_player_to_game):
		multiplayer.peer_connected.connect(_add_player_to_game)
	if not multiplayer.peer_disconnected.is_connected(_del_player):
		multiplayer.peer_disconnected.connect(_del_player)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func become_host() -> void:
	notifications.notify("Starting host...", true)
	if _hosted_lobby_id != 0:
		_show_failure_popup_and_return("Host Failed", "A lobby is already being hosted.", AUTO_RETURN_SECONDS)
		return

	_spawn_host_on_lobby_created = not OS.has_feature("dedicated_server")
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, SteamManager.lobby_max)

func _on_lobby_created(connect_status: int, lobby_id) -> void:
	if connect_status == Steam.RESULT_OK:
		notifications.notify("Lobby Created! ID: %s" % lobby_id, true)

		_hosted_lobby_id = lobby_id
		_current_lobby_id = lobby_id

		multiplayer_peer.host_with_lobby(lobby_id)
		multiplayer.multiplayer_peer = multiplayer_peer
		_connect_multiplayer_signals()
		if _spawn_host_on_lobby_created:
			_add_player_to_game(multiplayer.get_unique_id())

		var lobby_name := MultiplayerManager.sanitize_lobby_name(MultiplayerManager.pending_lobby_name)
		Steam.setLobbyJoinable(_hosted_lobby_id, true)
		Steam.setLobbyData(_hosted_lobby_id, "name", lobby_name)
		Steam.setLobbyData(_hosted_lobby_id, "mode", LOBBY_MODE)
		Steam.setLobbyData(_hosted_lobby_id, LOBBY_GAME_KEY, LOBBY_GAME_VALUE)
		MultiplayerManager.pending_lobby_name = ""
	else:
		_show_failure_popup_and_return("Host Failed", "Failed to create Steam lobby (status %s)." % connect_status, AUTO_RETURN_SECONDS)

func join_as_client(lobby_id):
	notifications.notify("Attempting to join lobby: %s" % lobby_id, false)
	Steam.joinLobby(lobby_id)

func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, _response: int) -> void:
	_current_lobby_id = lobby_id
	if Steam.getLobbyOwner(lobby_id) == Steam.getSteamID():
		notifications.notify("You are the owner, bypassing client connection.", false)
		return

	notifications.notify("Successfully joined lobby: %s" % lobby_id, true)
	multiplayer_peer.connect_to_lobby(lobby_id)
	multiplayer.multiplayer_peer = multiplayer_peer
	_connect_multiplayer_signals()
	_join_timeout_timer.start(JOIN_TIMEOUT_SECONDS)

func _on_connected_to_server() -> void:
	_join_timeout_timer.stop()
	_add_player_to_game(multiplayer.get_unique_id())
	notifications.notify("Connected to host.", false)

func _on_connection_failed() -> void:
	_join_timeout_timer.stop()
	_show_failure_popup_and_return("Join Failed", "Failed to connect to the lobby host.", AUTO_RETURN_SECONDS)

func _on_server_disconnected() -> void:
	_join_timeout_timer.stop()
	if multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	notifications.notify("Host closed the lobby. You were kicked.", true)
	_return_to_main_menu()

func _on_join_timeout() -> void:
	if multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		multiplayer_peer.close()
	_show_failure_popup_and_return("Join Timed Out", "Could not connect to the lobby host.", AUTO_RETURN_SECONDS)

func _show_failure_popup_and_return(title: String, message: String, auto_return_seconds: float = 0.0) -> void:
	if notifications:
		notifications.notify(message, true)
	if _showing_failure_popup:
		return

	_showing_failure_popup = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	MultiplayerManager.controls_enabled = false

	_failure_auto_return_timer.stop()
	_failure_countdown_timer.stop()

	_failure_dialog = _ensure_failure_popup()
	_failure_dialog.open_popup(title, message, "Return to Menu")

	if auto_return_seconds > 0.0:
		_failure_message_base = message
		_failure_seconds_remaining = int(ceil(auto_return_seconds))
		_failure_dialog.set_message_text("%s\n\nReturning to main menu in %ss..." % [_failure_message_base, _failure_seconds_remaining])
		_failure_auto_return_timer.start(auto_return_seconds)
		_failure_countdown_timer.start()

func _ensure_failure_popup():
	if is_instance_valid(_failure_dialog):
		return _failure_dialog

	_failure_dialog = popup_template_scene.instantiate()
	var popup_parent = get_tree().current_scene.get_node_or_null("CanvasLayer")
	if popup_parent:
		popup_parent.add_child(_failure_dialog)
	else:
		add_child(_failure_dialog)

	if not _failure_dialog.confirmed.is_connected(Callable(self, "_on_failure_popup_confirmed")):
		_failure_dialog.confirmed.connect(Callable(self, "_on_failure_popup_confirmed"))
	return _failure_dialog

func _on_failure_countdown_tick() -> void:
	if not _showing_failure_popup:
		_failure_countdown_timer.stop()
		return

	_failure_seconds_remaining = max(0, _failure_seconds_remaining - 1)
	if _failure_seconds_remaining <= 0:
		_failure_countdown_timer.stop()
		return

	if is_instance_valid(_failure_dialog):
		_failure_dialog.set_message_text("%s\n\nReturning to main menu in %ss..." % [_failure_message_base, _failure_seconds_remaining])

func _on_failure_popup_confirmed() -> void:
	_showing_failure_popup = false
	_failure_auto_return_timer.stop()
	_failure_countdown_timer.stop()
	_return_to_main_menu()

func _on_failure_popup_auto_return() -> void:
	if not _showing_failure_popup:
		return
	_showing_failure_popup = false
	_failure_countdown_timer.stop()
	_return_to_main_menu()

func _return_to_main_menu() -> void:
	shutdown_lobby(false)

	MultiplayerManager.pending_action = ""
	MultiplayerManager.pending_address = ""
	MultiplayerManager.pending_lobby_id = 0
	MultiplayerManager.pending_lobby_name = ""
	MultiplayerManager.multiplayer_mode_enabled = false
	MultiplayerManager.host_mode_enabled = false
	MultiplayerManager.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_current_lobby_id = 0
	_hosted_lobby_id = 0
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func shutdown_lobby(_host_shutdown: bool = false) -> void:
	_join_timeout_timer.stop()
	_failure_auto_return_timer.stop()
	_failure_countdown_timer.stop()
	_showing_failure_popup = false

	if is_instance_valid(_failure_dialog):
		_failure_dialog.queue_free()
		_failure_dialog = null

	if _host_shutdown and is_host():
		if _current_lobby_id != 0 and Steam.has_method("setLobbyJoinable"):
			Steam.setLobbyJoinable(_current_lobby_id, false)
		for peer_id in multiplayer.get_peers():
			multiplayer_peer.disconnect_peer(peer_id)

	if multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED:
		multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	multiplayer_peer = SteamMultiplayerPeer.new()

	if _current_lobby_id != 0 and Steam.has_method("leaveLobby"):
		Steam.leaveLobby(_current_lobby_id)

	_current_lobby_id = 0
	_hosted_lobby_id = 0

func list_lobbies() -> void:
	notifications.notify("Requesting lobby list...", false)
	Steam.addRequestLobbyListResultCountFilter(LOBBY_RESULT_LIMIT)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter(LOBBY_GAME_KEY, LOBBY_GAME_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
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
	var local_id = multiplayer.get_unique_id()
	members.append({
		"id": local_id,
		"id_type": "peer",
		"name": MultiplayerManager.get_display_name(local_id),
		"can_kick": false,
		"can_transfer": false,
	})
	for peer_id in multiplayer.get_peers():
		members.append({
			"id": peer_id,
			"id_type": "peer",
			"name": MultiplayerManager.get_display_name(peer_id),
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

func _add_player_to_game(id: int) -> void:
	if _players_spawn_node and _players_spawn_node.has_node(str(id)):
		return

	if id == multiplayer.get_unique_id():
		MultiplayerManager.register_local_peer_username(id)

	var joined_name := MultiplayerManager.get_display_name(id)
	notifications.notify("%s joined the game!" % joined_name, true)

	var player_to_add = multiplayer_scene.instantiate()
	player_to_add.hide()
	player_to_add.player_id = id
	player_to_add.name = str(id)

	if _players_spawn_node:
		_players_spawn_node.add_child(player_to_add, true)
	else:
		notifications.notify("Error: Spawn node not set!", true)

	if multiplayer.is_server() and id != multiplayer.get_unique_id():
		MultiplayerManager.sync_all_usernames_to_peer(id)

func _del_player(id: int) -> void:
	var departed_name := MultiplayerManager.get_display_name(id)
	notifications.notify("%s left the game." % departed_name, true)
	MultiplayerManager.clear_peer_username(id)
	if not _players_spawn_node or not _players_spawn_node.has_node(str(id)):
		return
	_players_spawn_node.get_node(str(id)).queue_free()
