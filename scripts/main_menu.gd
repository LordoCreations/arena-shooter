extends Node
var popup_template_scene := preload("res://scenes/ui/menu_popup_template.tscn")
const LOBBY_NAME := "3DShooter"
const LOBBY_NAME_KEY := "name"
const LOBBY_MODE_KEY := "mode"
const LOBBY_GAME_KEY := "game_key"
const LOBBY_GAME_VALUE := "arena_shooter"
const LOBBY_RESULT_LIMIT := 100

# --- Menu ---
@onready var main_menu = $CanvasLayer/MainMenu
@onready var address = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/Address
@onready var username = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/Username

# --- Steam ---
@onready var steam_menu := $CanvasLayer/SteamHUD
@onready var steam_lobbies := $CanvasLayer/SteamHUD/MarginContainer/Options/Lobbies/VBoxContainer

var _steam_error_popup
var _visible_lobbies: Array = []
var _using_fallback_lobby_filter: bool = false

func _ready() -> void:
	main_menu.show()
	steam_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _show_steam_menu() -> void:
	main_menu.hide()
	steam_menu.show()

func _show_main_menu() -> void:
	steam_menu.hide()
	main_menu.show()

func _connect_lobby_signals() -> void:
	var match_list_signal = Steam.lobby_match_list
	if not match_list_signal.is_connected(Callable(self, "_on_lobby_match_list")):
		match_list_signal.connect(Callable(self, "_on_lobby_match_list"))

	var lobby_data_signal = Steam.lobby_data_update
	if not lobby_data_signal.is_connected(Callable(self, "_on_lobby_data_update")):
		lobby_data_signal.connect(Callable(self, "_on_lobby_data_update"))

func _store_username() -> void:
	MultiplayerManager.player_username = username.text

func _start_game() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _on_host_button_pressed() -> void:
	_store_username()
	MultiplayerManager.pending_network_type = MultiplayerManager.NETWORK_TYPE.ENET
	MultiplayerManager.pending_action = "host"
	MultiplayerManager.pending_address = ""
	MultiplayerManager.pending_lobby_id = 0
	_start_game()

func _on_join_button_pressed() -> void:
	var address_to_join = address.text
	if len(address_to_join) == 0:
		address_to_join = "localhost"
	_store_username()
	MultiplayerManager.pending_network_type = MultiplayerManager.NETWORK_TYPE.ENET
	MultiplayerManager.pending_action = "join"
	MultiplayerManager.pending_address = address_to_join
	MultiplayerManager.pending_lobby_id = 0
	_start_game()

func join_lobby(lobby_id = 0) -> void:
	_store_username()
	MultiplayerManager.pending_network_type = MultiplayerManager.NETWORK_TYPE.STEAM
	MultiplayerManager.pending_action = "join"
	MultiplayerManager.pending_lobby_id = lobby_id
	MultiplayerManager.pending_address = ""
	_start_game()

func _on_join_steam_pressed() -> void:
	_show_steam_menu()
	MultiplayerManager.pending_network_type = MultiplayerManager.NETWORK_TYPE.STEAM
	if not SteamManager.initialize_steam():
		_show_main_menu()
		_show_steam_error_dialog()
		return
	_connect_lobby_signals()
	_on_list_lobbies_pressed()

func _on_steam_back_pressed() -> void:
	_clear_lobby_buttons()
	_visible_lobbies.clear()
	_show_main_menu()

func _on_list_lobbies_pressed() -> void:
	if MultiplayerManager.pending_network_type != MultiplayerManager.NETWORK_TYPE.STEAM:
		_on_join_steam_pressed()
		return
	_request_lobby_list(false)

func _request_lobby_list(use_fallback_filter: bool) -> void:
	_using_fallback_lobby_filter = use_fallback_filter
	Steam.addRequestLobbyListResultCountFilter(LOBBY_RESULT_LIMIT)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	if use_fallback_filter:
		Steam.addRequestLobbyListStringFilter(LOBBY_NAME_KEY, LOBBY_NAME, Steam.LOBBY_COMPARISON_EQUAL)
	else:
		Steam.addRequestLobbyListStringFilter(LOBBY_GAME_KEY, LOBBY_GAME_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func _on_host_p_2p_game_pressed() -> void:
	_store_username()
	MultiplayerManager.pending_network_type = MultiplayerManager.NETWORK_TYPE.STEAM
	MultiplayerManager.pending_action = "host"
	MultiplayerManager.pending_address = ""
	MultiplayerManager.pending_lobby_id = 0
	if not SteamManager.initialize_steam():
		_show_steam_error_dialog()
		return
	_start_game()

func _on_lobby_match_list(lobbies: Array, _lobby_count: int = -1) -> void:
	if lobbies.is_empty() and not _using_fallback_lobby_filter:
		_request_lobby_list(true)
		return

	_visible_lobbies.clear()
	for lobby_id in lobbies:
		var parsed_lobby_id := int(lobby_id)
		_visible_lobbies.append(parsed_lobby_id)
		Steam.requestLobbyData(parsed_lobby_id)
	_render_lobby_list()

func _on_lobby_data_update(success: int, lobby_id: int, _member_id: int) -> void:
	if success == 0:
		return
	var parsed_lobby_id := int(lobby_id)
	if _visible_lobbies.has(parsed_lobby_id):
		_render_lobby_list()

func _render_lobby_list() -> void:
	_clear_lobby_buttons()

	if _visible_lobbies.is_empty():
		var no_lobbies_label := Label.new()
		no_lobbies_label.text = "No Steam lobbies found."
		no_lobbies_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_lobbies_label.add_theme_font_size_override("font_size", 20)
		steam_lobbies.add_child(no_lobbies_label)
		return

	for lobby_id in _visible_lobbies:
		steam_lobbies.add_child(_create_lobby_button(int(lobby_id)))

func _create_lobby_button(lobby_id: int) -> Button:
	var lobby_name: String = Steam.getLobbyData(lobby_id, LOBBY_NAME_KEY)
	var lobby_mode: String = Steam.getLobbyData(lobby_id, LOBBY_MODE_KEY)
	var member_count: int = Steam.getNumLobbyMembers(lobby_id)
	var owner_id: int = int(Steam.getLobbyOwner(lobby_id))
	var owner_name := ""
	if owner_id != 0 and Steam.has_method("getFriendPersonaName"):
		owner_name = Steam.getFriendPersonaName(owner_id)

	if lobby_name == "":
		if owner_name != "":
			lobby_name = "%s's Lobby" % owner_name
		else:
			lobby_name = "Arena Shooter Lobby"
	if lobby_mode == "":
		lobby_mode = "Co-op"

	var lobby_summary := "%s | %s | %s player(s)" % [lobby_name, lobby_mode, member_count]
	if owner_name != "":
		lobby_summary = "%s | Host: %s" % [lobby_summary, owner_name]

	var lobby_button: Button = Button.new()
	lobby_button.set_text(lobby_summary)
	lobby_button.tooltip_text = "Lobby ID: %s" % lobby_id
	lobby_button.custom_minimum_size = Vector2(0, 42)
	lobby_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_button.clip_text = true
	lobby_button.add_theme_font_size_override("font_size", 20)
	lobby_button.set_name("lobby_%s" % lobby_id)
	lobby_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	lobby_button.connect("pressed", Callable(self, "join_lobby").bind(lobby_id))
	return lobby_button

func _clear_lobby_buttons() -> void:
	for lobby_child in steam_lobbies.get_children():
		lobby_child.queue_free()

func _show_steam_error_dialog() -> void:
	var popup = _ensure_steam_error_popup()
	popup.open_popup("Steam Error", "Failed to connect to Steam. Please make sure the Steam app is running on your computer and try again.", "Back to Menu")

func _ensure_steam_error_popup():
	if is_instance_valid(_steam_error_popup):
		return _steam_error_popup

	_steam_error_popup = popup_template_scene.instantiate()
	var popup_parent = get_node_or_null("CanvasLayer")
	if popup_parent:
		popup_parent.add_child(_steam_error_popup)
	else:
		add_child(_steam_error_popup)
	if not _steam_error_popup.confirmed.is_connected(Callable(self, "_on_steam_error_dismissed")):
		_steam_error_popup.confirmed.connect(Callable(self, "_on_steam_error_dismissed"))
	return _steam_error_popup

func _on_steam_error_dismissed() -> void:
	if is_instance_valid(_steam_error_popup):
		_steam_error_popup.close_popup()
	_show_main_menu()

func _on_quit_game_pressed() -> void:
	get_tree().quit()
