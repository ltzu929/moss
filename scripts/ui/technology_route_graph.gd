@tool
class_name TechnologyRouteGraph
extends Control

@export var route: TechNodeData.Route = TechNodeData.Route.MANAGED:
	set(value):
		route = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	visibility_changed.connect(queue_redraw)
	set_process(Engine.is_editor_hint())
	call_deferred("queue_redraw")


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var cards: Dictionary = {}
	for candidate in get_parent().find_children("*", "Button", true, false):
		if not candidate.is_in_group("technology_node_cards"):
			continue
		var node_data: TechNodeData = candidate.get("node_data")
		if node_data != null and node_data.route == route:
			cards[node_data.node_id] = candidate

	for node_id in cards:
		var card: Control = cards[node_id]
		var node_data: TechNodeData = card.get("node_data")
		for prerequisite_id in node_data.prerequisite_ids:
			var prerequisite: Control = cards.get(prerequisite_id)
			if prerequisite == null:
				continue
			var start: Vector2 = prerequisite.global_position - global_position + Vector2(prerequisite.size.x, prerequisite.size.y * 0.5)
			var finish: Vector2 = card.global_position - global_position + Vector2(0.0, card.size.y * 0.5)
			var bend_x: float = lerpf(start.x, finish.x, 0.5)
			var color := Color(0.28, 0.62, 0.68, 0.46)
			draw_polyline(
				PackedVector2Array([
					start,
					Vector2(bend_x, start.y),
					Vector2(bend_x, finish.y),
					finish,
				]),
				color,
				2.0,
				true
			)
