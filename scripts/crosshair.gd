extends Control

@onready var player = $"../../.."

@onready var DOT = $Center/Dot
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
var _show_reload_indicator: bool = false
var _reload_progress: float = 0.0

@export var reload_outer_radius: float = 34.0
@export var reload_thickness: float = 8.0
@export var reload_background_color: Color = Color(1.0, 1.0, 1.0, 0.15)
@export var reload_fill_color: Color = Color(1.0, 1.0, 1.0, 0.8)
@export var reload_start_angle: float = -PI * 0.5
@export var reload_smooth_segments: int = 72

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

func get_pixel_spread() -> float:
	return maxf(0.0, current_spread * get_viewport_rect().size.y)

func reset_spread() -> void:
	is_firing = false
	current_spread = reset_pos
	var pixel_spread := get_pixel_spread()
	RIGHT.position = Vector2(pixel_spread, 0)
	LEFT.position = Vector2(-pixel_spread, 0)
	UP.position = Vector2(0, -pixel_spread)
	DOWN.position = Vector2(0, pixel_spread)

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority(): return
	
	if not is_firing:
		current_spread = lerp(current_spread, reset_pos, reset_speed * delta)

	# Convert percentage to actual pixels
	var pixel_spread = get_pixel_spread()

	# Apply positions
	RIGHT.position = RIGHT.position.lerp(Vector2(pixel_spread, 0), grow_speed * delta)
	LEFT.position = LEFT.position.lerp(Vector2(-pixel_spread, 0), grow_speed * delta)
	UP.position = UP.position.lerp(Vector2(0, -pixel_spread), grow_speed * delta)
	DOWN.position = DOWN.position.lerp(Vector2(0, pixel_spread), grow_speed * delta)

	_update_reload_indicator_state()

func _draw() -> void:
	if not _show_reload_indicator:
		return

	var center = get_viewport_rect().size * 0.5
	var inner_radius = max(reload_outer_radius - reload_thickness, 0.0)

	_draw_ring_segment(center, inner_radius, reload_outer_radius, 0.0, TAU, reload_background_color)

	if _reload_progress <= 0.0:
		return

	var end_angle = reload_start_angle + TAU * _reload_progress
	_draw_ring_segment(center, inner_radius, reload_outer_radius, reload_start_angle, end_angle, reload_fill_color)

func _update_reload_indicator_state() -> void:
	var should_show = false
	var progress = 0.0

	if player and player.has_method("should_show_interact_hold_indicator") and player.call("should_show_interact_hold_indicator"):
		should_show = true
		if player.has_method("get_interact_hold_progress"):
			progress = float(player.call("get_interact_hold_progress"))
	elif player and player.weapon_manager and player.weapon_manager.current_weapon:
		var weapon = player.weapon_manager.current_weapon
		if weapon.is_reloading:
			should_show = true
			progress = weapon.get_reload_progress()

	if should_show != _show_reload_indicator or abs(progress - _reload_progress) > 0.001:
		_show_reload_indicator = should_show
		_reload_progress = progress
		_set_crosshair_parts_visible(not _show_reload_indicator)
		queue_redraw()

func _set_crosshair_parts_visible(v: bool) -> void:
	DOT.visible = v
	RIGHT.visible = v
	LEFT.visible = v
	UP.visible = v
	DOWN.visible = v

func _draw_ring_segment(center: Vector2, inner_r: float, outer_r: float, from_angle: float, to_angle: float, color: Color) -> void:
	if outer_r <= 0.0:
		return
	if to_angle <= from_angle:
		return

	var arc_len = to_angle - from_angle
	var steps = max(3, int(ceil(reload_smooth_segments * (arc_len / TAU))))
	var points := PackedVector2Array()

	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var a = lerp(from_angle, to_angle, t)
		points.push_back(center + Vector2(cos(a), sin(a)) * outer_r)

	for i in range(steps, -1, -1):
		var t = float(i) / float(steps)
		var a = lerp(from_angle, to_angle, t)
		points.push_back(center + Vector2(cos(a), sin(a)) * inner_r)

	draw_colored_polygon(points, color)
