extends Node3D

@onready var camera_arm = get_parent().get_parent().get_node("SpringArm3D")
@onready var camera = camera_arm.get_node("Camera3D")
@onready var equipment_pivot = get_parent()
@onready var aim_ray = camera.get_node("Convergence") 

@export var ads_lerp_speed: float = 8.0 # Slower looks more "physical"
@export var hip_position: Vector3 = Vector3(0.5, -0.3, -0.4)
@export var sight_offset: Vector3 = Vector3(0, -0.35 , -1.2)

# --- Spline / Avoidance Settings ---
@export var shoulder_outset: float = 0.8 # How far out the gun swings to avoid the body
@export var vertical_swing: float = 0.2 # How much it dips/rises during the swap

# --- Convergence Settings ---
@export var default_convergence_dist: float = 50.0 
@export var rotation_speed: float = 20.0     

var is_ads: bool = false
var lerp_weight: float = 0.0

func _ready():
	if not is_multiplayer_authority(): return
	camera_arm.aim_toggled.connect(_on_aim_toggled)
	aim_ray.add_exception(get_parent().get_parent()) 

func _on_aim_toggled(is_aiming: bool) -> void:
	is_ads = is_aiming

func _process(delta: float) -> void:
	if not is_multiplayer_authority(): return

	# --- 1. RAYCAST ALIGNMENT (Convergence) ---
	var screen_center = get_viewport().get_visible_rect().size / 2
	var ray_origin = camera.project_ray_origin(screen_center)
	var ray_direction = camera.project_ray_normal(screen_center)
	var ray_end = ray_origin + (ray_direction * default_convergence_dist)

	aim_ray.global_transform.origin = ray_origin
	aim_ray.target_position = aim_ray.to_local(ray_end)
	aim_ray.force_raycast_update()

	# --- 2. THE SPLINE (Bézier Avoidance) ---
	var target_weight = 1.0 if is_ads else 0.0
	lerp_weight = move_toward(lerp_weight, target_weight, ads_lerp_speed * delta)

	# A. Start Point (Hip)
	var p0 = equipment_pivot.global_transform.translated_local(hip_position).origin
	# B. End Point (ADS - Predicts where camera is)
	var p2 = camera.global_transform.translated_local(sight_offset).origin
	
	# C. Control Point (The "Shoulder" point to curve around)
	# We take the midpoint and push it "Right" and "Forward" to clear the chest
	var midpoint = p0.lerp(p2, 0.5)
	var shoulder_dir = camera.global_transform.basis.x # Right
	var forward_dir = camera.global_transform.basis.z # Back/Forward
	
	var p1 = midpoint + (shoulder_dir * shoulder_outset) - (forward_dir * 0.2)
	p1.y += vertical_swing # Slight dip or lift

	# D. Calculate Quadratic Bézier
	# Formula: (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
	var t = lerp_weight
	var final_origin = (pow(1-t, 2) * p0) + (2 * (1-t) * t * p1) + (pow(t, 2) * p2)

	# --- 3. FINAL TRANSFORM ---
	# Use the camera's basis as the foundation for rotation
	var target_point = aim_ray.get_collision_point() if aim_ray.is_colliding() else ray_end
	
	global_transform.origin = final_origin
	
	# Smoothly point the gun at the target
	var look_trans = global_transform.looking_at(target_point, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(look_trans.basis, rotation_speed * delta)
