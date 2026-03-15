extends Control

@onready var player = $"../../.."

@onready var RIGHT = $Center/Right
@onready var LEFT = $Center/Left
@onready var UP = $Center/Up
@onready var DOWN = $Center/Down

# These are now percentages of screen height (e.g., 0.01 = 1% of height)
var grow_increment: float = 0.01 
var grow_multiplier: float = 1.05
var grow_speed: float = 15.0

var reset_pos: float = 0.01
var max_spread: float = 0.08 # Max 8% of screen height
var current_spread: float = 0.01 
var reset_speed: float = 5.0 # Increased for better feel

var is_firing: bool = false

func _ready() -> void:
	if not is_multiplayer_authority():
		hide()
		return
	player.firing.connect(on_fired)

func on_fired(f: bool):
	if not is_multiplayer_authority(): return
	is_firing = f
	
	if f: 
		current_spread = clamp((current_spread + grow_increment) * grow_multiplier, reset_pos, max_spread)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return

	# Get current screen height to calculate pixel offset
	var screen_h = get_viewport_rect().size.y
	
	if not is_firing:
		current_spread = lerp(current_spread, reset_pos, reset_speed * delta)

	# Convert percentage to actual pixels
	var pixel_spread = current_spread * screen_h

	# Apply positions
	RIGHT.position = RIGHT.position.lerp(Vector2(pixel_spread, 0), grow_speed * delta)
	LEFT.position = LEFT.position.lerp(Vector2(-pixel_spread, 0), grow_speed * delta)
	UP.position = UP.position.lerp(Vector2(0, -pixel_spread), grow_speed * delta)
	DOWN.position = DOWN.position.lerp(Vector2(0, pixel_spread), grow_speed * delta)
