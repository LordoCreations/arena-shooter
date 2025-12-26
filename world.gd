extends Node

@export var pause: bool = false

# --- Menu ---
@onready var main_menu = $CanvasLayer/MainMenu
@onready var address_entry = $CanvasLayer/MainMenu/MarginContainer/VBoxContainer/AddressEntry

# --- HUD ---
@onready var hud = $CanvasLayer/HUD
@onready var health_bar = $CanvasLayer/HUD/MarginContainer/HealthBar


# --- Multiplayer ---
const PORT = 9999
var enet_peer = ENetMultiplayerPeer.new()

const Player = preload("res://player.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("quit"):
		pause = !pause
		if pause:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_host_button_pressed() -> void:
	start_game()
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

	add_player(multiplayer.get_unique_id())
	
	upnp_setup()

func _on_join_button_pressed() -> void:
	start_game()
	if len(address_entry.text) > 0:
		enet_peer.create_client(address_entry.text, PORT)
	else:
		enet_peer.create_client("localhost", PORT)

	multiplayer.multiplayer_peer = enet_peer

func add_player(peer_id):
	var player = Player.instantiate()
	player.name = str(peer_id)
	add_child(player)
	if player.is_multiplayer_authority():
		player.health_changed.connect(update_health)

func remove_player(peer_id):
	var player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()

func start_game() -> void:
	main_menu.hide()
	hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func update_health(health: float, maxhealth: float):	
	health_bar.value = 100 * (health / maxhealth)
	print(str(health_bar.value) + " = " + str(health) + "/" +str(maxhealth))


func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node.is_multiplayer_authority():
		node.health_changed.connect(update_health)




# --- Over Internet Multiplayer ---
func upnp_setup() -> void:
	
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	assert(discover_result == UPNP.UPNP_RESULT_SUCCESS, "UPNP Discover Failed! Error %s" % discover_result)
	assert(upnp.get_gateway() and upnp.get_gateway().is_valid_gateway(), "UPNP Invalid Gateway! %s" % upnp.get_device_count())
	
	var map_result = upnp.add_port_mapping(PORT)
	assert(map_result == UPNP.UPNP_RESULT_SUCCESS, "UPNP Port Mapping Failed! Error %s" % map_result)

	print("success! join address %s" % upnp.query_external_address())
