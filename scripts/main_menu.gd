extends Node

# --- Menu ---
@onready var main_menu = $CanvasLayer/MainMenu
@onready var address = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/Address
@onready var username = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/Username

# --- Steam ---
@onready var steam_menu := $CanvasLayer/SteamHUD
@onready var steam_lobbies := $CanvasLayer/SteamHUD/MarginContainer/Options/Lobbies/VBoxContainer

func _ready() -> void:
	main_menu.show()
	steam_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	main_menu.hide()
	steam_menu.show()
	MultiplayerManager.pending_network_type = MultiplayerManager.NETWORK_TYPE.STEAM
	if not SteamManager.initialize_steam():
		main_menu.show()
		steam_menu.hide()
		_show_steam_error_dialog()
		return
	var lobby_signal = Steam.lobby_match_list
	if not lobby_signal.is_connected(Callable(self, "_on_lobby_match_list")):
		lobby_signal.connect(Callable(self, "_on_lobby_match_list"))
	_on_list_lobbies_pressed()

func _on_list_lobbies_pressed() -> void:
	if MultiplayerManager.pending_network_type != MultiplayerManager.NETWORK_TYPE.STEAM:
		_on_join_steam_pressed()
		return
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("name", "3DShooter", Steam.LOBBY_COMPARISON_EQUAL)
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

func _on_lobby_match_list(lobbies: Array):
	for lobby_child in steam_lobbies.get_children():
		lobby_child.queue_free()
		
	for lobby in lobbies:
		var lobby_name: String = Steam.getLobbyData(lobby, "name")
		if lobby_name != "":
			var lobby_mode: String = Steam.getLobbyData(lobby, "mode")
			var lobby_button: Button = Button.new()
			lobby_button.set_text(lobby_name + " | " + lobby_mode)
			lobby_button.set_size(Vector2(100, 30))
			lobby_button.add_theme_font_size_override("font_size", 14)
			lobby_button.set_name("lobby_%s" % lobby)
			lobby_button.alignment = HORIZONTAL_ALIGNMENT_FILL
			lobby_button.connect("pressed", Callable(self, "join_lobby").bind(lobby))
			steam_lobbies.add_child(lobby_button)

func _show_steam_error_dialog() -> void:
	var error_dialog = AcceptDialog.new()
	error_dialog.title = "Steam Error"
	error_dialog.dialog_text = "Failed to connect to Steam. Please make sure the Steam app is running on your computer and try again."
	error_dialog.get_ok_button().text = "Back to Menu"
	error_dialog.connect("confirmed", Callable(self, "_on_steam_error_dismissed"))
	add_child(error_dialog)
	error_dialog.popup_centered_ratio(0.6)

func _on_steam_error_dismissed() -> void:
	main_menu.show()
	steam_menu.hide()

func _on_quit_game_pressed() -> void:
	get_tree().quit()
