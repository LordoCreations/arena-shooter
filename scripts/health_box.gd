class_name HealthBox
extends LootBox

@export var health_texture: Texture2D = preload("res://assets/loot/dungeon_texture.png")
@export var health_tint: Color = Color(1.35, 0.28, 0.28, 0.5)

func _ready() -> void:
	_apply_health_visual_override()
	super._ready()

func _apply_health_visual_override() -> void:
	if health_texture == null:
		return

	var mesh_nodes: Array[Node] = find_children("*", "MeshInstance3D", true, false)
	for mesh_node in mesh_nodes:
		if not (mesh_node is MeshInstance3D):
			continue

		var mesh_instance := mesh_node as MeshInstance3D
		var source_material: Material = mesh_instance.get_active_material(0)
		var override_material: StandardMaterial3D
		if source_material is StandardMaterial3D:
			override_material = (source_material as StandardMaterial3D).duplicate(true)
		else:
			override_material = StandardMaterial3D.new()

		override_material.albedo_texture = health_texture
		override_material.albedo_color = health_tint
		mesh_instance.material_override = override_material
