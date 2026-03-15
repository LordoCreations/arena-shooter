extends Node

enum NETWORK_TYPE {ENET, STEAM}

var host_mode_enabled = false
var multiplayer_mode_enabled = false
var respawn_point = Vector3(0, 20, 0)

var pending_action: String = ""
var pending_address: String = ""
var pending_lobby_id: int = 0
var pending_network_type: NETWORK_TYPE = NETWORK_TYPE.ENET

var player_username: String = ""
var controls_enabled: bool = true
