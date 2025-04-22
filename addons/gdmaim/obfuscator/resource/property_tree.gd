extends RefCounted


const SymbolTable := preload("../symbol_table.gd")
const Symbol := SymbolTable.Symbol


var _scenes : Dictionary


func save_property(scene : String, node : String, key : String, value : String) -> void:
	if !_scenes.has(scene):
		_scenes[scene] = {}
	
	var _scene : Dictionary = _scenes[scene]
	
	if !_scene.has(node):
		_scene[node] = {}
	
	var _node : Dictionary = _scene[node]
	
	_node[key] = value

func get_property(scene : String, node : String, key : String) -> String:
	return _scenes.get(scene, {}).get(node, {}).get(key, "")

func get_key_list(scene : String, node : String) -> Array:
	return _scenes.get(scene, {}).get(node, {}).keys()
