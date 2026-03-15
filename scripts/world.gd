extends Node

@export var pause: bool = false

# --- Menu ---
@onready var main_menu = $CanvasLayer/MainMenu
@onready var address = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/Address

# --- Steam ---
@onready var steam_menu := $CanvasLayer/SteamHUD 
@onready var steam_lobbies := $CanvasLayer/SteamHUD/MarginContainer/Options/Lobbies/VBoxContainer

func _unhandled_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		pause = !pause
		if pause:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_host_button_pressed() -> void:
	%NetworkManager.active_network_type = %NetworkManager.NETWORK_TYPE.ENET
	%NetworkManager.become_host()
	start_game()


func _on_join_button_pressed() -> void:
	var address_to_join = address.text
	if len(address_to_join) == 0:
		address_to_join = "localhost"
	%NetworkManager.active_network_type = %NetworkManager.NETWORK_TYPE.ENET
	%NetworkManager.join_as_client(0, address_to_join)
	start_game()


func start_game() -> void:
	main_menu.hide()
	steam_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# --- Steam Functionality ---

func join_lobby(lobby_id = 0) -> void:
	%NetworkManager.join_as_client(lobby_id)
	start_game()

func _on_join_steam_pressed() -> void:
	main_menu.hide()
	steam_menu.show()
	%NetworkManager.active_network_type = %NetworkManager.NETWORK_TYPE.STEAM
	SteamManager.initialize_steam()
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	_on_list_lobbies_pressed()


func _on_list_lobbies_pressed() -> void:
	if %NetworkManager.active_network_type != %NetworkManager.NETWORK_TYPE.STEAM:
		_on_join_steam_pressed()
	%NetworkManager.list_lobbies()


func _on_host_p_2p_game_pressed() -> void:
	if %NetworkManager.active_network_type != %NetworkManager.NETWORK_TYPE.STEAM:
		_on_join_steam_pressed()
	%NetworkManager.become_host()
	start_game()


func _on_lobby_match_list(lobbies: Array):
	print("On lobby match list")
	print(lobbies)
	
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
			
			#var fv = FontVariation.new()
			#fv.set_base_font(load("res://assets/fonts/PixelOperator8.ttf"))
			#lobby_button.add_theme_font_override("font", fv)
			lobby_button.set_name("lobby_%s" % lobby)
			lobby_button.alignment = HORIZONTAL_ALIGNMENT_FILL
			lobby_button.connect("pressed", Callable(self, "join_lobby").bind(lobby))

			steam_lobbies.add_child(lobby_button)
