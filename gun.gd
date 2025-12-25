extends Node3D

@onready var camera_arm = get_parent().get_parent().get_node("SpringArm3D")
@onready var camera = camera_arm.get_node("Camera3D")

@export var ads_speed: float = 0.15
@export var hip_position: Vector3 = Vector3(0.5, -0.4, -0.5)
@export var sight_offset: Vector3 = Vector3(0, -0.4, -0.4) # Adjust these!

var is_ads: bool = false

func _ready():
	# Connect to the signal from SpringArm3D
	camera_arm.aim_toggled.connect(_on_aim_toggled)
	position = hip_position

func _on_aim_toggled(is_aiming: bool) -> void:
	is_ads = is_aiming
	
	# If exiting ADS, snap/tween back to hip position
	if not is_aiming:
		var tween = create_tween()
		tween.tween_property(self, "position", hip_position, ads_speed)
		tween.tween_property(self, "rotation", Vector3.ZERO, ads_speed)


func _process(_delta: float) -> void:
	if is_ads:
		# Position the gun relative to the camera's local space
		global_transform = camera.global_transform
		# Shift it forward and down so the sights align with the screen center
		translate_object_local(sight_offset)
