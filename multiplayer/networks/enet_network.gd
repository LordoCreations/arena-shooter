extends Node

const SERVER_PORT = 9999
const JOIN_TIMEOUT_SECONDS := 3.0
const AUTO_RETURN_SECONDS := 3.0
var SERVER_IP = "127.0.0.1"

var multiplayer_scene = preload("res://scenes/player.tscn")
var multiplayer_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
@export var _players_spawn_node: Node

@onready var notifications = get_node_or_null("../../CanvasLayer/Notifications")
@onready var _join_timeout_timer: Timer = Timer.new()
@onready var _failure_auto_return_timer: Timer = Timer.new()
@onready var _failure_countdown_timer: Timer = Timer.new()

var _showing_failure_popup: bool = false
var _failure_dialog: AcceptDialog
var _failure_message_base: String = ""
var _failure_seconds_remaining: int = 0

func _ready() -> void:
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
	notifications.notify("Starting host...", false)

	var err := multiplayer_peer.create_server(SERVER_PORT)
	if err != OK:
		if err == ERR_ALREADY_IN_USE:
			_show_failure_popup_and_return("Host Failed", "This address/port is already being used by another lobby.", AUTO_RETURN_SECONDS)
		else:
			_show_failure_popup_and_return("Host Failed", "Could not start host (error %s)." % err, AUTO_RETURN_SECONDS)
		return

	multiplayer.multiplayer_peer = multiplayer_peer
	_connect_multiplayer_signals()

	if not OS.has_feature("dedicated_server"):
		_add_player_to_game(multiplayer.get_unique_id())

	var ip = get_local_ip()
	notifications.notify("Host Active! IP: " + str(ip), true)
	DisplayServer.clipboard_set(ip)

func join_as_client(address_to_join: String) -> void:
	notifications.notify("Attempting to join: " + address_to_join, false)

	SERVER_IP = address_to_join
	var err := multiplayer_peer.create_client(SERVER_IP, SERVER_PORT)
	if err != OK:
		_show_failure_popup_and_return("Join Failed", "Could not start client connection (error %s)." % err, AUTO_RETURN_SECONDS)
		return

	multiplayer.multiplayer_peer = multiplayer_peer
	_connect_multiplayer_signals()
	_join_timeout_timer.start(JOIN_TIMEOUT_SECONDS)

func _on_connected_to_server() -> void:
	_join_timeout_timer.stop()
	_add_player_to_game(multiplayer.get_unique_id())
	notifications.notify("Connected to host.", false)

func _on_connection_failed() -> void:
	_join_timeout_timer.stop()
	_show_failure_popup_and_return("Join Failed", "Failed to connect to the lobby.", AUTO_RETURN_SECONDS)

func _on_server_disconnected() -> void:
	_join_timeout_timer.stop()
	notifications.notify("Disconnected from host.", true)
	_return_to_main_menu()

func _on_join_timeout() -> void:
	if multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		multiplayer_peer.close()
	_show_failure_popup_and_return("Join Timed Out", "No lobby is being hosted at that address.", AUTO_RETURN_SECONDS)

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

	_failure_dialog = AcceptDialog.new()
	_failure_dialog.title = title
	_failure_dialog.dialog_text = message
	_failure_dialog.get_ok_button().text = "Return to Menu"
	_failure_dialog.connect("confirmed", Callable(self, "_on_failure_popup_confirmed"))
	add_child(_failure_dialog)
	_failure_dialog.popup_centered_ratio(0.6)

	if auto_return_seconds > 0.0:
		_failure_message_base = message
		_failure_seconds_remaining = int(ceil(auto_return_seconds))
		_failure_dialog.dialog_text = "%s\n\nReturning to main menu in %ss..." % [_failure_message_base, _failure_seconds_remaining]
		_failure_auto_return_timer.start(auto_return_seconds)
		_failure_countdown_timer.start()

func _on_failure_countdown_tick() -> void:
	if not _showing_failure_popup:
		_failure_countdown_timer.stop()
		return

	_failure_seconds_remaining = max(0, _failure_seconds_remaining - 1)
	if _failure_seconds_remaining <= 0:
		_failure_countdown_timer.stop()
		return

	if is_instance_valid(_failure_dialog):
		_failure_dialog.dialog_text = "%s\n\nReturning to main menu in %ss..." % [_failure_message_base, _failure_seconds_remaining]

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
	_join_timeout_timer.stop()
	_failure_auto_return_timer.stop()
	_failure_countdown_timer.stop()

	if is_instance_valid(_failure_dialog):
		_failure_dialog.queue_free()
		_failure_dialog = null

	MultiplayerManager.pending_action = ""
	MultiplayerManager.pending_address = ""
	MultiplayerManager.pending_lobby_id = 0
	MultiplayerManager.multiplayer_mode_enabled = false
	MultiplayerManager.host_mode_enabled = false
	MultiplayerManager.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _add_player_to_game(id: int) -> void:
	if _players_spawn_node.has_node(str(id)):
		return
	notifications.notify("Player %s joined!" % id, false)

	var player_to_add = multiplayer_scene.instantiate()
	player_to_add.hide()
	player_to_add.player_id = id
	player_to_add.name = str(id)

	_players_spawn_node.add_child(player_to_add, true)

func _del_player(id: int) -> void:
	notifications.notify("Player %s left!" % id, false)
	if not _players_spawn_node.has_node(str(id)):
		return
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
