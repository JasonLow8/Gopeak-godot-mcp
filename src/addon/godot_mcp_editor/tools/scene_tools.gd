@tool
extends Node
class_name MCPSceneTools

var _editor_plugin: EditorPlugin = null

func set_editor_plugin(plugin: EditorPlugin) -> void:
	_editor_plugin = plugin


func _refresh_and_reload(scene_path: String) -> void:
	MCPSceneUtils.refresh_and_reload(_editor_plugin, scene_path)


func _refresh_filesystem() -> void:
	MCPSceneUtils._refresh_filesystem(_editor_plugin)


func _reload_scene_in_editor(scene_path: String) -> void:
	MCPSceneUtils._reload_scene_in_editor(_editor_plugin, scene_path)


func _ensure_res_path(path: String) -> String:
	return MCPSceneUtils.ensure_res_path(path)


func _to_scene_res_path(project_path: String, scene_path: String) -> String:
	return MCPSceneUtils.to_scene_res_path(project_path, scene_path)


func _load_scene(scene_path: String) -> Array:
	return MCPSceneUtils.load_scene(scene_path)


func _save_scene(scene_root: Node, scene_path: String) -> Dictionary:
	return MCPSceneUtils.save_scene(scene_root, scene_path, _editor_plugin)


func _find_node(root: Node, path: String) -> Node:
	return MCPSceneUtils.find_node(root, path)


func _parse_value(value, expected_type: int = TYPE_NIL):
	return MCPSceneUtils.parse_value(value, expected_type)


func _get_property_type(node: Node, prop_name: String) -> int:
	return MCPSceneUtils.get_property_type(node, prop_name)


func _serialize_value(value) -> Variant:
	return MCPSceneUtils.serialize_value(value)


func _set_node_properties(node: Node, properties: Dictionary) -> void:
	MCPSceneUtils.set_node_properties(node, properties)


func _parse_properties_arg(raw_properties) -> Dictionary:
	return MCPSceneUtils.parse_properties_arg(raw_properties)


func _ensure_parent_dir_for_scene(scene_path: String) -> void:
	MCPSceneUtils.ensure_parent_dir_for_scene(scene_path)


func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	MCPSceneUtils.set_owner_recursive(node, scene_owner)


func _build_node_tree(node: Node, include_properties: bool, depth: int, current_depth: int, node_path: String) -> Dictionary:
	var data := {
		"name": str(node.name),
		"type": node.get_class(),
		"path": node_path,
		"children": []
	}

	if include_properties:
		var props := {}
		for p in node.get_property_list():
			if not (p.get("usage", 0) & PROPERTY_USAGE_STORAGE):
				continue
			var pn := str(p.get("name", ""))
			if pn.is_empty():
				continue
			props[pn] = _serialize_value(node.get(pn))
		data["properties"] = props

	if depth >= 0 and current_depth >= depth:
		return data

	for child in node.get_children():
		if child is Node:
			var child_node := child as Node
			var child_path := str(child_node.name) if node_path == "." else node_path + "/" + str(child_node.name)
			data["children"].append(_build_node_tree(child_node, include_properties, depth, current_depth + 1, child_path))

	return data


func _collect_nodes_recursive(node: Node, path: String, out_nodes: Array) -> void:
	out_nodes.append({"path": path, "node": node})
	for child in node.get_children():
		if child is Node:
			var child_node := child as Node
			var child_path := str(child_node.name) if path == "." else path + "/" + str(child_node.name)
			_collect_nodes_recursive(child_node, child_path, out_nodes)


func create_scene(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var root_node_type := str(args.get("rootNodeType", "Node"))
	var script_path := str(args.get("scriptPath", ""))

	if scene_path == "res://":
		return {"ok": false, "error": "Missing scenePath"}
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"
	if not ClassDB.class_exists(root_node_type):
		return {"ok": false, "error": "Invalid rootNodeType: " + root_node_type}

	_ensure_parent_dir_for_scene(scene_path)

	var root := ClassDB.instantiate(root_node_type) as Node
	if not root:
		return {"ok": false, "error": "Failed to instantiate root node: " + root_node_type}
	root.name = scene_path.get_file().get_basename()

	if not script_path.is_empty():
		var full_script_path := _to_scene_res_path(project_path, script_path)
		var script = load(full_script_path)
		if not script:
			root.queue_free()
			return {"ok": false, "error": "Failed to load script: " + full_script_path}
		root.set_script(script)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {"ok": true, "scenePath": scene_path, "rootNodeType": root_node_type}


func list_scene_nodes(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var depth := int(args.get("depth", -1))
	var include_properties := bool(args.get("includeProperties", false))

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var tree := _build_node_tree(root, include_properties, depth, 0, ".")
	root.queue_free()
	return {"ok": true, "tree": tree}


func add_node(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var node_type := str(args.get("nodeType", ""))
	var node_name := str(args.get("nodeName", ""))
	var parent_node_path := str(args.get("parentNodePath", "."))
	var properties := _parse_properties_arg(args.get("properties", {}))

	if node_type.is_empty() or node_name.is_empty():
		return {"ok": false, "error": "Missing nodeType or nodeName"}
	if not ClassDB.class_exists(node_type):
		return {"ok": false, "error": "Invalid nodeType: " + node_type}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var parent := _find_node(root, parent_node_path)
	if not parent:
		root.queue_free()
		return {"ok": false, "error": "Parent node not found: " + parent_node_path}

	var new_node := ClassDB.instantiate(node_type) as Node
	if not new_node:
		root.queue_free()
		return {"ok": false, "error": "Failed to instantiate nodeType: " + node_type}

	new_node.name = node_name
	_set_node_properties(new_node, properties)
	parent.add_child(new_node)
	_set_owner_recursive(new_node, root)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {"ok": true, "nodeName": node_name, "nodeType": node_type}


func delete_node(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var node_path := str(args.get("nodePath", ""))

	if node_path.is_empty() or node_path == ".":
		return {"ok": false, "error": "Cannot delete root node"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var node := _find_node(root, node_path)
	if not node:
		root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}

	var parent := node.get_parent()
	if not parent:
		root.queue_free()
		return {"ok": false, "error": "Cannot delete root node"}

	parent.remove_child(node)
	node.queue_free()

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {"ok": true, "deletedNodePath": node_path}


func duplicate_node(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var node_path := str(args.get("nodePath", ""))
	var new_name := str(args.get("newName", ""))
	var parent_path := str(args.get("parentPath", ""))

	if node_path.is_empty() or new_name.is_empty():
		return {"ok": false, "error": "Missing nodePath or newName"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var source := _find_node(root, node_path)
	if not source:
		root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}

	var target_parent: Node = source.get_parent()
	if not parent_path.is_empty():
		target_parent = _find_node(root, parent_path)
	if not target_parent:
		root.queue_free()
		return {"ok": false, "error": "Parent not found: " + parent_path}

	var duplicated_node := source.duplicate() as Node
	if not duplicated_node:
		root.queue_free()
		return {"ok": false, "error": "Failed to duplicate node: " + node_path}

	duplicated_node.name = new_name
	target_parent.add_child(duplicated_node)
	_set_owner_recursive(duplicated_node, root)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {"ok": true, "nodePath": node_path, "newName": new_name}


func reparent_node(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var node_path := str(args.get("nodePath", ""))
	var new_parent_path := str(args.get("newParentPath", ""))

	if node_path.is_empty() or node_path == ".":
		return {"ok": false, "error": "Cannot reparent root node"}
	if new_parent_path.is_empty():
		return {"ok": false, "error": "Missing newParentPath"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var node := _find_node(root, node_path)
	var new_parent := _find_node(root, new_parent_path)
	if not node:
		root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}
	if not new_parent:
		root.queue_free()
		return {"ok": false, "error": "New parent not found: " + new_parent_path}

	var old_parent := node.get_parent()
	if not old_parent:
		root.queue_free()
		return {"ok": false, "error": "Cannot reparent root node"}

	old_parent.remove_child(node)
	new_parent.add_child(node)
	_set_owner_recursive(node, root)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {"ok": true, "nodePath": node_path, "newParentPath": new_parent_path}


func set_node_properties(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var node_path := str(args.get("nodePath", "."))
	var properties := _parse_properties_arg(args.get("properties", {}))

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var node := _find_node(root, node_path)
	if not node:
		root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}

	_set_node_properties(node, properties)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {"ok": true, "nodePath": node_path}


func get_node_properties(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var node_path := str(args.get("nodePath", "."))
	var include_defaults := bool(args.get("includeDefaults", false))

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var node := _find_node(root, node_path)
	if not node:
		root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}

	var defaults: Node = null
	if not include_defaults and ClassDB.class_exists(node.get_class()):
		defaults = ClassDB.instantiate(node.get_class()) as Node

	var props := {}
	for p in node.get_property_list():
		var usage := int(p.get("usage", 0))
		if not (usage & PROPERTY_USAGE_STORAGE):
			continue
		var prop_name := str(p.get("name", ""))
		if prop_name.is_empty():
			continue
		var current_val = node.get(prop_name)
		if not include_defaults and defaults:
			var default_val = defaults.get(prop_name)
			if current_val == default_val:
				continue
		props[prop_name] = _serialize_value(current_val)

	if defaults:
		defaults.queue_free()
	root.queue_free()
	return {"ok": true, "nodePath": node_path, "properties": props}


func load_sprite(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var node_path := str(args.get("nodePath", "."))
	var texture_path := _to_scene_res_path(project_path, str(args.get("texturePath", "")))

	if texture_path == "res://":
		return {"ok": false, "error": "Missing texturePath"}

	var texture = load(texture_path)
	if not texture or not (texture is Texture2D):
		return {"ok": false, "error": "Failed to load texture: " + texture_path}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var node := _find_node(root, node_path)
	if not node:
		root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}

	if node is Sprite2D:
		(node as Sprite2D).texture = texture as Texture2D
	elif node is Sprite3D:
		(node as Sprite3D).texture = texture as Texture2D
	else:
		root.queue_free()
		return {"ok": false, "error": "Node is not Sprite2D or Sprite3D: " + node_path}

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {"ok": true, "nodePath": node_path, "texturePath": texture_path}


func save_scene(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var new_path_raw := str(args.get("newPath", ""))
	var target_path := scene_path
	if not new_path_raw.is_empty():
		target_path = _to_scene_res_path(project_path, new_path_raw)

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	_ensure_parent_dir_for_scene(target_path)
	var root := result[0] as Node
	var err := _save_scene(root, target_path)
	if not err.is_empty():
		return err

	return {"ok": true, "scenePath": scene_path, "savedPath": target_path}


func connect_signal(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var source_node_path := str(args.get("sourceNodePath", ""))
	var signal_name := str(args.get("signalName", ""))
	var target_node_path := str(args.get("targetNodePath", ""))
	var method_name := str(args.get("methodName", ""))
	var flags := int(args.get("flags", 0))

	if source_node_path.is_empty() or signal_name.is_empty() or target_node_path.is_empty() or method_name.is_empty():
		return {"ok": false, "error": "Missing required signal connection arguments"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var source := _find_node(root, source_node_path)
	var target := _find_node(root, target_node_path)
	if not source:
		root.queue_free()
		return {"ok": false, "error": "Source node not found: " + source_node_path}
	if not target:
		root.queue_free()
		return {"ok": false, "error": "Target node not found: " + target_node_path}
	if not source.has_signal(signal_name):
		root.queue_free()
		return {"ok": false, "error": "Signal not found on source: " + signal_name}

	var callable := Callable(target, method_name)
	if not source.is_connected(signal_name, callable):
		var connect_result := source.connect(signal_name, callable, flags)
		if connect_result != OK:
			root.queue_free()
			return {"ok": false, "error": "Failed to connect signal: " + str(connect_result)}

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		"ok": true,
		"sourceNodePath": source_node_path,
		"signalName": signal_name,
		"targetNodePath": target_node_path,
		"methodName": method_name,
		"flags": flags
	}


func disconnect_signal(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var source_node_path := str(args.get("sourceNodePath", ""))
	var signal_name := str(args.get("signalName", ""))
	var target_node_path := str(args.get("targetNodePath", ""))
	var method_name := str(args.get("methodName", ""))

	if source_node_path.is_empty() or signal_name.is_empty() or target_node_path.is_empty() or method_name.is_empty():
		return {"ok": false, "error": "Missing required signal disconnection arguments"}

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var source := _find_node(root, source_node_path)
	var target := _find_node(root, target_node_path)
	if not source:
		root.queue_free()
		return {"ok": false, "error": "Source node not found: " + source_node_path}
	if not target:
		root.queue_free()
		return {"ok": false, "error": "Target node not found: " + target_node_path}

	var callable := Callable(target, method_name)
	if source.is_connected(signal_name, callable):
		source.disconnect(signal_name, callable)

	var err := _save_scene(root, scene_path)
	if not err.is_empty():
		return err

	return {
		"ok": true,
		"sourceNodePath": source_node_path,
		"signalName": signal_name,
		"targetNodePath": target_node_path,
		"methodName": method_name
	}


func list_connections(args: Dictionary) -> Dictionary:
	var project_path := str(args.get("projectPath", ""))
	var scene_path := _to_scene_res_path(project_path, str(args.get("scenePath", "")))
	var filter_path := str(args.get("nodePath", ""))

	var result := _load_scene(scene_path)
	if not result[1].is_empty():
		return result[1]

	var root := result[0] as Node
	var nodes: Array = []
	_collect_nodes_recursive(root, ".", nodes)

	var connections: Array = []
	for entry in nodes:
		var path := str(entry["path"])
		if not filter_path.is_empty() and filter_path != path:
			continue
		var node := entry["node"] as Node
		for signal_info in node.get_signal_list():
			var signal_name := str(signal_info.get("name", ""))
			if signal_name.is_empty():
				continue
			for conn in node.get_signal_connection_list(signal_name):
				var callable: Callable = conn.get("callable", Callable())
				var target_obj: Object = callable.get_object()
				var target_path := ""
				if target_obj and target_obj is Node:
					target_path = str(root.get_path_to(target_obj as Node))
				connections.append({
					"sourceNodePath": path,
					"signalName": signal_name,
					"targetNodePath": target_path,
					"methodName": str(callable.get_method()),
					"flags": int(conn.get("flags", 0))
				})

	root.queue_free()
	return {"ok": true, "connections": connections}


# =============================================================================
# move_node — reorder a node among its siblings (sibling index change)
# =============================================================================
func move_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get("scenePath", "")))
	var node_path: String = str(args.get("nodePath", ""))
	var new_index: int = int(args.get("newIndex", 0))

	if scene_path.strip_edges() == "res://":
		return {"ok": false, "error": "Missing scenePath"}
	if node_path.is_empty():
		return {"ok": false, "error": "Missing nodePath"}

	var loaded := _load_scene(scene_path)
	if not loaded[1].is_empty():
		return loaded[1]

	var scene_root: Node = loaded[0]
	var node := _find_node(scene_root, node_path)
	if not node:
		scene_root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}

	var parent := node.get_parent()
	if not parent:
		scene_root.queue_free()
		return {"ok": false, "error": "Node has no parent: " + node_path}

	var siblings := parent.get_children()
	var current_index := siblings.find(node)
	if current_index < 0:
		scene_root.queue_free()
		return {"ok": false, "error": "Node not found among parent's children"}

	var clamped_index := clampi(new_index, 0, siblings.size() - 1)
	if current_index == clamped_index:
		scene_root.queue_free()
		return {"ok": true, "nodePath": node_path, "index": current_index, "moved": false}

	parent.move_child(node, clamped_index)

	var save_err := _save_scene(scene_root, scene_path)
	if not save_err.is_empty():
		return save_err

	return {"ok": true, "nodePath": node_path, "oldIndex": current_index, "newIndex": clamped_index, "moved": true}


# =============================================================================
# rename_node — rename a node in the scene tree
# =============================================================================
func rename_node(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get("scenePath", "")))
	var node_path: String = str(args.get("nodePath", ""))
	var new_name: String = str(args.get("newName", ""))

	if scene_path.strip_edges() == "res://":
		return {"ok": false, "error": "Missing scenePath"}
	if node_path.is_empty():
		return {"ok": false, "error": "Missing nodePath"}
	if new_name.strip_edges().is_empty():
		return {"ok": false, "error": "Missing newName"}

	var loaded := _load_scene(scene_path)
	if not loaded[1].is_empty():
		return loaded[1]

	var scene_root: Node = loaded[0]
	var node := _find_node(scene_root, node_path)
	if not node:
		scene_root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}

	var old_name := node.name
	node.name = new_name.strip_edges()

	var save_err := _save_scene(scene_root, scene_path)
	if not save_err.is_empty():
		return save_err

	return {"ok": true, "nodePath": node_path, "oldName": old_name, "newName": node.name}


# =============================================================================
# set_anchor_preset — set Control node anchor preset
# =============================================================================
func set_anchor_preset(args: Dictionary) -> Dictionary:
	var scene_path: String = _ensure_res_path(str(args.get("scenePath", "")))
	var node_path: String = str(args.get("nodePath", ""))
	var anchor_preset_name: String = str(args.get("anchorPreset", "FullRect"))
	var keep_margins: bool = bool(args.get("keepMargins", false))

	if scene_path.strip_edges() == "res://":
		return {"ok": false, "error": "Missing scenePath"}
	if node_path.is_empty():
		return {"ok": false, "error": "Missing nodePath"}

	var loaded := _load_scene(scene_path)
	if not loaded[1].is_empty():
		return loaded[1]

	var scene_root: Node = loaded[0]
	var node := _find_node(scene_root, node_path)
	if not node:
		scene_root.queue_free()
		return {"ok": false, "error": "Node not found: " + node_path}

	if not node is Control:
		scene_root.queue_free()
		return {"ok": false, "error": "Node is not a Control: " + node_path}

	var preset_map := {
		"None": Control.PRESET_NONE,
		"FullRect": Control.PRESET_FULL_RECT,
		"CenterLeft": Control.PRESET_CENTER_LEFT,
		"CenterTop": Control.PRESET_CENTER_TOP,
		"CenterRight": Control.PRESET_CENTER_RIGHT,
		"CenterBottom": Control.PRESET_CENTER_BOTTOM,
		"Center": Control.PRESET_CENTER,
		"LeftTop": Control.PRESET_LEFT_TOP,
		"LeftCenter": Control.PRESET_LEFT_CENTER,
		"LeftBottom": Control.PRESET_LEFT_BOTTOM,
		"RightTop": Control.PRESET_RIGHT_TOP,
		"RightCenter": Control.PRESET_RIGHT_CENTER,
		"RightBottom": Control.PRESET_RIGHT_BOTTOM,
		"TopCenter": Control.PRESET_TOP_CENTER,
		"BottomCenter": Control.PRESET_BOTTOM_CENTER,
	}

	if not preset_map.has(anchor_preset_name):
		scene_root.queue_free()
		return {"ok": false, "error": "Unknown anchorPreset: " + anchor_preset_name}
	node.set_anchors_preset(preset_map[anchor_preset_name] as int, keep_margins)

	var save_err := _save_scene(scene_root, scene_path)
	if not save_err.is_empty():
		return save_err

	return {"ok": true, "nodePath": node_path, "anchorPreset": anchor_preset_name, "keepMargins": keep_margins}


# =============================================================================
# read_resource — read a resource file and return its properties
# =============================================================================
func read_resource(args: Dictionary) -> Dictionary:
	var resource_path: String = _ensure_res_path(str(args.get("resourcePath", "")))

	if resource_path.strip_edges() == "res://" or resource_path.strip_edges().is_empty():
		return {"ok": false, "error": "Missing resourcePath"}

	if not FileAccess.file_exists(resource_path):
		return {"ok": false, "error": "Resource not found: " + resource_path}

	var resource: Resource = load(resource_path)

	if not resource:
		return {"ok": false, "error": "Failed to load resource: " + resource_path}

	var properties: Dictionary = {}
	for prop in resource.get_property_list():
		var name := str(prop.get("name", ""))
		if name.is_empty() or name.begins_with("Object"):
			continue
		var value = resource.get(name)
		properties[name] = _serialize_value(value)

	return {
		"ok": true,
		"resourcePath": resource_path,
		"type": resource.get_class(),
		"properties": properties,
	}


# =============================================================================
# edit_resource — update properties on a resource file
# =============================================================================
func edit_resource(args: Dictionary) -> Dictionary:
	var resource_path: String = _ensure_res_path(str(args.get("resourcePath", "")))
	var properties: Dictionary = args.get("properties", {})

	if resource_path.strip_edges() == "res://" or resource_path.strip_edges().is_empty():
		return {"ok": false, "error": "Missing resourcePath"}
	if properties.is_empty():
		return {"ok": false, "error": "Missing properties"}

	if not FileAccess.file_exists(resource_path):
		return {"ok": false, "error": "Resource not found: " + resource_path}

	var resource: Resource = load(resource_path)
	if not resource:
		return {"ok": false, "error": "Failed to load resource: " + resource_path}

	for key in properties:
		var prop_name := str(key)
		var raw_value = properties.get(key)
		var parsed_value = _parse_value(raw_value)
		resource.set(prop_name, parsed_value)

	var save_err := ResourceSaver.save(resource)
	if save_err != OK:
		return {"ok": false, "error": "Failed to save resource: " + resource_path}

	_refresh_filesystem()

	return {"ok": true, "resourcePath": resource_path, "updated": properties.keys().size()}


# =============================================================================
# execute_editor_script — run arbitrary GDScript in the editor context
# =============================================================================
func execute_editor_script(args: Dictionary) -> Dictionary:
	var script_code: String = str(args.get("scriptCode", ""))

	if script_code.strip_edges().is_empty():
		return {"ok": false, "error": "Missing scriptCode"}

	if not _editor_plugin:
		return {"ok": false, "error": "Editor plugin not available (execute_editor_script requires editor context)"}

	var ei := _editor_plugin.get_editor_interface()
	var edited_scene := ei.get_edited_scene_root()
	if not edited_scene:
		return {"ok": false, "error": "No scene open in the editor"}

	var script := GDScript.new()
	script.source_code = script_code

	var result := {"ok": true, "output": ""}
	var output_lines: Array = []

	var ctx := {
		"scene_root": edited_scene,
		"editor_interface": ei,
		"output": output_lines,
	}

	script.reload()

	var instance: Object = script.new()
	if not instance:
		return {"ok": false, "error": "Script instantiation failed"}

	if instance.has_method("_execute"):
		var exec_result = instance.call("_execute", ctx)
		if exec_result is Dictionary and exec_result.has("error"):
			result["ok"] = false
			result["error"] = exec_result.get("error")

	for line in output_lines:
		result["output"] += str(line) + "\n"

	if instance is Node:
		instance.queue_free()
	elif not instance is RefCounted:
		instance.free()

	return result


# =============================================================================
# clear_output — clear the Output dock (no-op unless editor available)
# =============================================================================
func clear_output(args: Dictionary) -> Dictionary:
	return {"ok": true, "message": "Output cleared (no-op in headless mode)"}


# =============================================================================
# reload_plugin — reload the MCP editor plugin
# =============================================================================
func reload_plugin(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {"ok": false, "error": "Editor plugin not available"}
	_editor_plugin.get_editor_interface().get_resource_filesystem().scan()
	return {"ok": true, "message": "Plugin reload triggered"}


# =============================================================================
# reload_project — re-scan the project filesystem and reload all scenes
# =============================================================================
func reload_project(args: Dictionary) -> Dictionary:
	if not _editor_plugin:
		return {"ok": false, "error": "Editor plugin not available"}
	var ei := _editor_plugin.get_editor_interface()
	ei.get_resource_filesystem().scan()
	var edited_root := ei.get_edited_scene_root()
	if edited_root and not edited_root.scene_file_path.is_empty():
		ei.reload_scene_from_path(edited_root.scene_file_path)
	return {"ok": true, "message": "Project reload triggered"}
