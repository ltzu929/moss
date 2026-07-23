class_name RegionOrbitalView
extends Control

## MOSS 界面主题工具
const MOSS_THEME := preload("res://scripts/ui/moss_ui_theme.gd")

var _globe_root: Node3D
var _marker: MeshInstance3D
var _focus_label: Label
var _focused_region: String = "全球"
var _target_rotation: Vector3 = Vector3.ZERO
var _region_rotations: Dictionary = {
	"全球": Vector3(-0.12, -0.35, 0.0),
	"北美": Vector3(-0.40, 1.75, 0.0),
	"南美": Vector3(0.25, 1.25, 0.0),
	"欧洲": Vector3(-0.55, -0.20, 0.0),
	"非洲": Vector3(0.05, -0.15, 0.0),
	"亚洲": Vector3(-0.25, -1.55, 0.0),
	"大洋洲": Vector3(0.45, -2.15, 0.0),
}


func _ready() -> void:
	unique_name_in_owner = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_viewport()
	focus_region(_focused_region)
	set_process(true)


func _process(delta: float) -> void:
	if _globe_root == null:
		return

	_globe_root.rotation.x = lerp_angle(
		_globe_root.rotation.x,
		_target_rotation.x,
		clampf(delta * 2.2, 0.0, 1.0)
	)
	_globe_root.rotation.y = lerp_angle(
		_globe_root.rotation.y,
		_target_rotation.y,
		clampf(delta * 2.2, 0.0, 1.0)
	)
	_globe_root.rotate_y(delta * 0.025)


func focus_region(region_name: String) -> void:
	_focused_region = region_name if region_name in _region_rotations else "全球"
	_target_rotation = _region_rotations[_focused_region]

	if _focus_label != null:
		_focus_label.text = "FOCUS / " + _focused_region

	if _marker != null:
		_marker.visible = _focused_region != "全球"


func get_focused_region() -> String:
	return _focused_region


func _build_viewport() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	add_child(container)

	var viewport := SubViewport.new()
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(420, 210)
	container.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)

	_globe_root = Node3D.new()
	world.add_child(_globe_root)

	var globe := MeshInstance3D.new()
	var globe_mesh := SphereMesh.new()
	globe_mesh.radius = 1.0
	globe_mesh.height = 2.0
	globe_mesh.radial_segments = 64
	globe_mesh.rings = 32
	globe.mesh = globe_mesh

	var globe_material := StandardMaterial3D.new()
	globe_material.albedo_color = Color(0.018, 0.09, 0.13, 1.0)
	globe_material.metallic = 0.35
	globe_material.roughness = 0.58
	globe_material.emission_enabled = true
	globe_material.emission = Color(0.01, 0.09, 0.12, 1.0)
	globe_material.emission_energy_multiplier = 0.55
	globe.material_override = globe_material
	_globe_root.add_child(globe)

	var atmosphere := MeshInstance3D.new()
	atmosphere.mesh = globe_mesh
	atmosphere.scale = Vector3.ONE * 1.025
	var atmosphere_material := StandardMaterial3D.new()
	atmosphere_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	atmosphere_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	atmosphere_material.cull_mode = BaseMaterial3D.CULL_FRONT
	atmosphere_material.albedo_color = Color(0.18, 0.56, 0.66, 0.10)
	atmosphere_material.emission_enabled = true
	atmosphere_material.emission = Color(0.06, 0.30, 0.38, 1.0)
	atmosphere_material.emission_energy_multiplier = 0.35
	atmosphere.material_override = atmosphere_material
	_globe_root.add_child(atmosphere)

	_add_orbit_ring(world, Vector3(75.0, 0.0, 0.0))
	_add_orbit_ring(world, Vector3(64.0, 28.0, 0.0))
	_add_orbit_ring(world, Vector3(110.0, -22.0, 0.0))

	_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.045
	marker_mesh.height = 0.09
	_marker.mesh = marker_mesh
	_marker.position = Vector3(0.0, 0.0, 1.04)
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = MOSS_THEME.ACCENT_GOLD
	marker_material.emission_enabled = true
	marker_material.emission = MOSS_THEME.ACCENT_GOLD
	marker_material.emission_energy_multiplier = 2.0
	_marker.material_override = marker_material
	_globe_root.add_child(_marker)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-24.0, -35.0, 0.0)
	light.light_color = Color(0.58, 0.82, 0.90, 1.0)
	light.light_energy = 1.8
	world.add_child(light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(20.0, 145.0, 0.0)
	rim_light.light_color = Color(0.18, 0.40, 0.55, 1.0)
	rim_light.light_energy = 0.9
	world.add_child(rim_light)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 0.0, 3.25)
	camera.fov = 38.0
	world.add_child(camera)
	camera.look_at(Vector3.ZERO)

	_focus_label = Label.new()
	_focus_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_focus_label.offset_left = 10.0
	_focus_label.offset_top = -28.0
	_focus_label.offset_right = -10.0
	_focus_label.offset_bottom = -6.0
	_focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_focus_label.add_theme_color_override("font_color", MOSS_THEME.TEXT_SECONDARY)
	_focus_label.add_theme_font_size_override("font_size", 12)
	add_child(_focus_label)


func _add_orbit_ring(parent: Node3D, ring_rotation_degrees: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.22
	ring_mesh.outer_radius = 1.228
	ring_mesh.rings = 64
	ring_mesh.ring_segments = 8
	ring.mesh = ring_mesh
	ring.rotation_degrees = ring_rotation_degrees

	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color = Color(0.24, 0.62, 0.70, 0.24)
	ring.material_override = ring_material
	parent.add_child(ring)
