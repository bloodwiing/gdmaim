extends RefCounted


const _Logger := preload("../../logger.gd")
const _Settings := preload("../../settings.gd")
const SymbolTable := preload("../symbol_table.gd")
const PropertyTree := preload("property_tree.gd")
const BlockReader := preload("../block_reader.gd")

var path : String

var _source_data : String
var _data : String
var _seed : int

var _property_tree : PropertyTree

var _ext_scenes : Dictionary
var _ext_resources_by_uid : Dictionary  # optimisation
var _sub_resources_by_id : Dictionary  # collision check

var _scene_data : PropertyTree.SceneData

var _imported_ext_resources_by_uid : Dictionary
var _imported_sub_resources_by_id : Dictionary  # collision check
var _ext_resources_count : int = 0
var _sub_resources_count : int = 0

var _imported_ext_resources_code : String = ""
var _imported_sub_resources_code : String = ""


func _init(path : String) -> void:
	self.path = path
	_seed = hash(str(_Settings.current.symbol_seed if !_Settings.current.symbol_dynamic_seed else int(Time.get_unix_time_from_system())))


func _parse_property(token : String) -> PropertyTree.ResourceProperty:
	var ref_id : String
	
	if token.begins_with('ExtResource("'):
		ref_id = _get_string_value(token)
		var prop := PropertyTree.ResourcePropertyExtRef.new(ref_id)
		prop.ext_res = weakref(_scene_data.get_ext_resource(ref_id))
		return prop
	
	elif token.begins_with('SubResource("'):
		ref_id = _get_string_value(token)
		var prop := PropertyTree.ResourcePropertySubRef.new(ref_id)
		prop.sub_res = weakref(_scene_data.get_sub_resource(ref_id))
		return prop
	
	elif token.begins_with('Array[') or token.begins_with('['):
		var type = null
		var list_start := 0
		if token.begins_with('Array['):
			var end : int = token.find(']')
			type = _parse_property(token.substr(6, end-6))  # Array[ ... ]
			list_start = token.find('[', end)
		var list_end : int = token.rfind(']')
		
		var prop := PropertyTree.ResourcePropertyArray.new()
		prop.type = type
		
		var list_blocks : BlockReader = BlockReader.new(token.substr(list_start+1, list_end-list_start-1), ', ', false)
		
		var block_idx : int = 0
		while block_idx < list_blocks.size():
			prop.add_item(_parse_property(list_blocks.get_block(block_idx)))
			block_idx += 1
		
		return prop
	
	elif token.begins_with('Dictionary[') or token.begins_with('{'):
		var key_type = null
		var value_type = null
		var dict_start := 0
		if token.begins_with('Dictionary['):
			var end : int = token.find(']')
			var middle : int = token.find(',')
			key_type = _parse_property(token.substr(11, middle-11))  # Dictionary[ ... ,
			value_type = _parse_property(token.substr(middle+2, end-middle-2))  # , ... ]
			dict_start = token.find('{', end)
		var dict_end : int = token.rfind('}')
		
		var prop := PropertyTree.ResourcePropertyDictionary.new()
		prop.key_type = key_type
		prop.value_type = value_type
		
		var dict_blocks : BlockReader = BlockReader.new(token.substr(dict_start+2, dict_end-dict_start-3), ',\n', false)
		
		var block_idx : int = 0
		while block_idx < dict_blocks.size():
			var split : PackedStringArray = dict_blocks.get_block(block_idx).split(': ', true, 1)
			block_idx += 1
			if split.size() < 2: continue
			prop.add_item(_parse_property(split[0]), _parse_property(split[1]))
		
		return prop
	
	else:
		return PropertyTree.ResourceProperty.new(token)


func parse(source_data : String, property_tree : PropertyTree) -> void:
	_source_data = source_data
	_property_tree = property_tree
	_ext_resources_by_uid.clear()
	_sub_resources_by_id.clear()
	_ext_scenes.clear()
	
	_scene_data = property_tree.get_scene(path)
	
	var blocks : BlockReader = BlockReader.new(_source_data, '\n', true)
	var i : int = 0
	while i < blocks.size():
		var line : String = blocks.get_block(i)
		
		if line.begins_with("[ext_resource"):
			var tokens : PackedStringArray = line.split(" ", false)
			
			var resource_path : String
			var resource_id : String
			var resource_uid : String
			var resource_type : String
			
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				var token_j : int = token_i
				if token.begins_with('path="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					resource_path = _get_string_value(token)
					if resource_path.is_empty(): continue
				elif token.begins_with('id="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					resource_id = _get_string_value(token)
					if resource_id.is_empty(): continue
				elif token.begins_with('uid="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					resource_uid = _get_string_value(token)
					if resource_uid.is_empty(): continue
				elif token.begins_with('type="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					resource_type = _get_string_value(token)
					if resource_type.is_empty(): continue
			
			if not resource_path.is_empty() and not resource_id.is_empty() and resource_type == 'PackedScene':
				_ext_scenes[resource_id] = resource_path
				_Logger.write(str(i+1) + " detected scene import " + resource_path + ' as "' + resource_id + '"')
			
			_Logger.write(str(i+1) + ' [ExtResource type="' + resource_type + '" id="' + resource_id + '"]')
			
			_scene_data.add_ext_resource(resource_path, resource_uid, resource_type, resource_id)
			_ext_resources_by_uid[resource_uid] = _scene_data.get_ext_resource(resource_id)
			
			i += 1
		
		elif line.begins_with("[sub_resource"):
			var tokens : PackedStringArray = line.split(" ", false)
			
			var resource_id : String
			var resource_type : String
			
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				var token_j : int = token_i
				if token.begins_with('id="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					resource_id = _get_string_value(token)
					if resource_id.is_empty(): continue
				elif token.begins_with('type="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					resource_type = _get_string_value(token)
					if resource_type.is_empty(): continue
			
			_scene_data.add_sub_resource(resource_type, resource_id)
			_sub_resources_by_id[resource_id] = _scene_data.get_sub_resource(resource_id)
			
			var j : int = i + 1
			
			while j < blocks.size():
				if blocks.get_block(j).begins_with('['):
					break
				
				line = blocks.get_block(j)
				j += 1
				
				tokens = line.split(" = ", false, 1)
				if tokens.size() == 2:
					_scene_data.add_sub_property(resource_id, tokens[0], _parse_property(tokens[1]))
			
			var sub : PropertyTree.SubResource = _scene_data.get_sub_resource(resource_id)
			
			_Logger.write(str(i+1) + ' [SubResource type="' + resource_type + '" id="' + resource_id + '"] with ' + str(len(sub.get_properties())) + ' properties')
			
			i = j
		
		elif line.begins_with("[node"):
			var tokens : PackedStringArray = line.split(" ", false)
			
			var node_name : String = ""
			var node_parent : String = ""
			var node_instance : String = ""
			
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				var token_j : int = token_i
				if token.begins_with('name="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					node_name = _get_string_value(token)
					if node_name.is_empty(): continue
				
				elif token.begins_with('parent="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1;
					node_parent = _get_string_value(token)
					if node_parent.is_empty(): continue
				
				elif token.begins_with('instance=ExtResource("'):
					while !token.ends_with(')') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1;
					node_instance = _get_string_value(token)
					if node_instance.is_empty(): continue
			
			if node_parent.is_empty(): node_name = '.'
			elif node_parent != '.': node_parent = './' + node_parent
			
			var node_path : String = node_parent+'/'+node_name
			if node_parent.is_empty():
				node_path = node_name
			
			var j : int = i + 1
			
			while j < blocks.size():
				if blocks.get_block(j).begins_with('['):
					break
				
				line = blocks.get_block(j)
				j += 1
				
				tokens = line.split(" = ", false, 1)
				if tokens.size() == 2:
					_scene_data.add_property(node_path, tokens[0], _parse_property(tokens[1]))
			
			if node_instance.is_empty():
				var tree_parent : String = ""
				for root in _scene_data.get_dependent_roots():
					if node_path.begins_with(root):
						tree_parent = root
						break
				
				if !tree_parent.is_empty():
					_scene_data.add_dependent_node(tree_parent, node_path)
					_Logger.write(str(i+1) + " processed edited node " + node_path + " of " + _scene_data.get_dependency(tree_parent))
				
				else:
					_Logger.write(str(i+1) + " processed node " + node_path)
			else:
				var node_instantiates_scene : String = _ext_scenes[node_instance]
				_scene_data.add_dependency(node_path, node_instantiates_scene)
				_Logger.write(str(i+1) + " processed instantiated scene root node " + node_path + " as " + node_instantiates_scene)
			
			i = j
		
		else:
			i += 1


func run(symbol_table : SymbolTable) -> bool:
	_data = ""
	
	_imported_ext_resources_by_uid.clear()
	_imported_sub_resources_by_id.clear()
	_imported_ext_resources_code = ""
	_imported_sub_resources_code = ""
	
	_ext_resources_count = _scene_data.get_ext_resource_count()
	_sub_resources_count = _scene_data.get_sub_resource_count()
	
	var last_ext_resource_pos : int = -1
	var last_sub_resource_pos : int = -1
	
	var blocks : BlockReader = BlockReader.new(_source_data, '\n', true)
	var head_line = blocks.get_block(0) if !blocks.is_empty() else ""
	
	var logger_i_offset : int = 0
	
	var i : int = 1
	while i < blocks.size():
		var line : String = blocks.get_block(i)
		if line.begins_with("\""):
			_data += line + "\n"
			i += 1
			continue
		
		if line.begins_with('[connection signal="') or line.begins_with('[node name="'):
			var node_paths : bool = false
			var tokens : PackedStringArray = line.split(" ", false)
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				if token.begins_with('signal="') or token.begins_with('method="') or token.begins_with('node_paths=PackedStringArray("') or node_paths:
					node_paths = (token.begins_with("node_paths") or node_paths) and token[-1] == ","
					
					var token_j : int = token_i
					if token.begins_with('signal="') or token.begins_with('method="'):
						while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					if token.begins_with('node_paths=PackedStringArray("'):
						while !token.ends_with(')') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					var name : String = _get_string_value(token)
					if name.is_empty(): continue
					
					var new_symbol : SymbolTable.Symbol = symbol_table.find_global_symbol(name)
					if new_symbol:
						line = _replace_first(line, name, str(new_symbol.name))
						_Logger.write(str(i+1+logger_i_offset) + " found symbol '" + name + "' = " + str(new_symbol.name))
		
		elif line.begins_with("[sub_resource"):
			last_sub_resource_pos = _data.length()-1
		
		_data += line + "\n"
		i += 1
		
		if line.begins_with("[ext_resource"):
			last_ext_resource_pos = _data.length()
		
		if line.begins_with("[node") or line.begins_with("[sub_resource") or line.begins_with("[resource"):
			var node_name : String
			var node_parent : String
			
			var tokens : PackedStringArray = line.split(" ", false)
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				
				var token_j : int = token_i
				
				if token.begins_with('name="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					node_name = _get_string_value(token)
					if node_name.is_empty(): continue
				elif token.begins_with('parent="'):
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1;
					node_parent = _get_string_value(token)
					if node_parent.is_empty(): continue
				
				token_i += 1
			
			if node_parent.is_empty(): node_name = '.'
			elif node_parent != '.': node_parent = './' + node_parent
			
			var node_path : String = node_parent+'/'+node_name
			if node_parent.is_empty():
				node_path = node_name
			
			var is_edited : bool = !line.contains("type=") and line.begins_with("[node")
			
			var tmp_lines : String
			var has_script : bool = line.contains("instance=") or line.contains('type="Animation"')
			var j : int = i
			var script_i : int = i-1
			var overwritten_keys : Dictionary = {}  # bootleg set
			while j < blocks.size():
				if blocks.get_block(j).begins_with("["):
					break
				
				tmp_lines += blocks.get_block(j) + "\n"
				
				tokens = blocks.get_block(j).split(" = ", false, 1)
				if tokens.size() == 2:
					if tokens[0] == "script":
						has_script = true
						script_i = j
						_Logger.write(str(i+1+logger_i_offset) + " found script " + line + " " + tokens[1])
					overwritten_keys[tokens[0]] = null
				
				j += 1
			
			# Rewrite export vars from instantiated scenes to the parent scenes
			if is_edited and _Settings.current.strip_editor_annotations:
				var merge_props : Dictionary = recursive_property_inject(node_path, _scene_data)
				for key in merge_props.keys():
					if overwritten_keys.has(key): continue
					var prop : PropertyTree.ResourceProperty = merge_props[key]
					var value : String = import_property(prop)
					
					j += 1
					
					logger_i_offset = 0
					if !_imported_ext_resources_code.is_empty():
						logger_i_offset += _imported_ext_resources_code.count('\n')
					if !_imported_sub_resources_code.is_empty():
						logger_i_offset += _imported_sub_resources_code.count('\n')
					
					blocks.insert_block(script_i+1, key+" = "+value)
			
			if !has_script:
				_data += tmp_lines
				i = j
			else:
				j = mini(j, blocks.size())
				
				while i < j:
					line = blocks.get_block(i)
					tokens = line.split(" = ", false, 1)
					if tokens.size() == 2:
						if tokens[1].begins_with("NodePath(") and tokens[1].contains(":"):
							var node_path_ref : String = _read_string(tokens[1])
							var properties : PackedStringArray = node_path_ref.split(":", false)
							var new_path : String = properties[0]
							for property in properties.slice(1):
								var new_symbol : SymbolTable.Symbol = symbol_table.find_global_symbol(property)
								new_path += ":" + (str(new_symbol.name) if new_symbol else property)
							tokens[1] = 'NodePath("' + new_path + '")'
							line = tokens[0] + " = " + tokens[1]
							if node_path_ref != new_path:
								_Logger.write(str(i+1+logger_i_offset) + " found node path '" + node_path_ref + "' = " + new_path)
						
						var new_symbol : SymbolTable.Symbol = symbol_table.find_global_symbol(tokens[0])
						if new_symbol:
							line = str(new_symbol.name) + " = " + tokens[1]
							_Logger.write(str(i+1+logger_i_offset) + " found export var '" + tokens[0] + "' = " + str(new_symbol.name))
					elif line.begins_with('"method":'):
						var method : String = _read_string(line.trim_prefix('"method":'))
						var new_symbol : SymbolTable.Symbol = symbol_table.find_global_symbol(method)
						if new_symbol:
							line = '"method": &"' + str(new_symbol.name) + '"'
							_Logger.write(str(i+1+logger_i_offset) + " found method '" + method + "' = " + str(new_symbol.name))
					
					_data += line + "\n"
					i += 1
	
	if !_imported_sub_resources_code.is_empty():
		if last_sub_resource_pos == -1:
			if _scene_data.get_ext_resource_count() == 0:
				last_sub_resource_pos = 1
			else:
				last_sub_resource_pos = last_ext_resource_pos
		_data = _data.insert(last_sub_resource_pos, _imported_sub_resources_code)
	if !_imported_ext_resources_code.is_empty():
		if last_ext_resource_pos == -1:
			last_ext_resource_pos = 1
		_data = _data.insert(last_ext_resource_pos, _imported_ext_resources_code)
	
	if !_imported_sub_resources_code.is_empty() or !_imported_ext_resources_code.is_empty():
		if head_line.contains("load_steps="):
			var head_parts : PackedStringArray = head_line.split(" ", false)
			head_line = head_parts[0]
			var part_i : int = 1
			while part_i < head_parts.size():
				var part : String = head_parts[part_i]
				part_i += 1
				
				if part.begins_with("load_steps="):
					head_line += " load_steps=" + str(_ext_resources_count + _sub_resources_count + 1)
				else:
					head_line += " "+part
		
		else:
			var head_slice : PackedStringArray = head_line.split(" ", false, 1)
			head_line = head_slice[0] + " load_steps=" + str(_ext_resources_count + _sub_resources_count + 1) + " " + head_slice[1]
	
	_data = head_line + '\n' + _data
	_data = _data.strip_edges(false, true) + "\n"
	
	return true


func recursive_property_inject(node_path : String, scene_data : PropertyTree.SceneData) -> Dictionary:
	# Rewrite export vars from instantiated scenes to the parent scenes
	if !scene_data.has_dependency(node_path):
		return {}
	
	var result : Dictionary = {}
	
	var inst_scene_path_root : String = scene_data.get_dependent_root(node_path)
	var inst_scene : String = scene_data.get_dependency(node_path)
	var inst_scene_relative_path : String = node_path.substr(inst_scene_path_root.length()+1)
	
	if inst_scene_relative_path.is_empty():
		inst_scene_relative_path = '.'
	else:
		inst_scene_relative_path = './' + inst_scene_relative_path
	
	var ext_scene_data : PropertyTree.SceneData = _property_tree.get_scene(inst_scene)
	
	for key in ext_scene_data.get_properties(inst_scene_relative_path):
		result[key] = ext_scene_data.get_property(inst_scene_relative_path, key)
	
	result.merge(recursive_property_inject(inst_scene_relative_path, ext_scene_data), false)
	
	return result


func import_property(property : PropertyTree.ResourceProperty) -> String:
	if property is PropertyTree.ResourcePropertyExtRef:
		var prop_ext_resource : PropertyTree.ExtResource = property.ext_res.get_ref() as PropertyTree.ExtResource
		var old_id : String = prop_ext_resource.id.to_string()
		
		# External references can be reused and optimised, check for it
		if _ext_resources_by_uid.has(prop_ext_resource.uid):
			_Logger.write('Reused ExtResource "' + old_id + '" as existing "' + _ext_resources_by_uid[prop_ext_resource.uid].id.to_string() + '"')
			return _ext_resources_by_uid[prop_ext_resource.uid].to_ref_string()
		elif _imported_ext_resources_by_uid.has(prop_ext_resource.uid):
			_Logger.write('Reused ExtResource "' + old_id + '" as existing "' + _imported_ext_resources_by_uid[prop_ext_resource.uid].id.to_string() + '" (already imported)')
			return _imported_ext_resources_by_uid[prop_ext_resource.uid].to_ref_string()
		
		# If not, import it. Follow ID schema
		else:
			prop_ext_resource = prop_ext_resource.duplicate()  # Create a copy
			_ext_resources_count += 1  # Increment resource counter name
			prop_ext_resource.id.set_name(str(_ext_resources_count))  # Update copy's name
			_imported_ext_resources_by_uid[prop_ext_resource.uid] = prop_ext_resource  # Save the copy for reuse if possible
			_imported_ext_resources_code += prop_ext_resource.to_string()+'\n'  # Add the copied resource for insertion into the scene
			_Logger.write('Imported ExtResource "' + old_id + '" under "' + _imported_ext_resources_by_uid[prop_ext_resource.uid].id.to_string() + '"')
			return prop_ext_resource.to_ref_string()
	
	elif property is PropertyTree.ResourcePropertySubRef:
		# These would be harder to optimise so just copy over willy-nilly
		var prop_sub_resource : PropertyTree.SubResource = property.sub_res.get_ref() as PropertyTree.SubResource
		var old_id : String = prop_sub_resource.id.to_string()
		prop_sub_resource = prop_sub_resource.duplicate()  # Create a copy
		_sub_resources_count += 1  # Increment counter just for load_steps
		
		# There is an ID conflict! Resolve
		if _sub_resources_by_id.has(old_id) or _imported_sub_resources_by_id.has(old_id):
			var conflict_sub : PropertyTree.SubResource
			
			if _sub_resources_by_id.has(old_id):
				conflict_sub = _sub_resources_by_id[old_id] as PropertyTree.SubResource
			else:
				conflict_sub = _imported_sub_resources_by_id[old_id] as PropertyTree.SubResource
			
			# The conflict is to the same SubResource, easy reuse
			if conflict_sub.same_ref(prop_sub_resource):
				_Logger.write('Reused SubResource "' + old_id + '" (possibly already imported)')
				return prop_sub_resource.to_ref_string()
			
			# The conflict is to a different SubResource, but fundamentally the same content
			# The ID could be mismatched
			# NOTE: this might cause issues since we expect SubResources to be independently unique despite being the same
			#elif _imported_sub_resources_by_hash.has(prop_sub_resource.get_hash()):
				#var similar_sub : PropertyTree.SubResource = _imported_sub_resources_by_hash[prop_sub_resource.get_hash()] as PropertyTree.SubResource
				#if similar_sub.equal(prop_sub_resource):
					#_Logger.write('Reused SubResource "' + old_id + '" as "' + similar_sub.id.to_string() + '" (possibly already imported)')
					#return similar_sub.to_ref_string()
			
			# Generate new hash name
			else:
				var random := RandomNumberGenerator.new()
				random.seed = prop_sub_resource.get_hash() + prop_sub_resource.get_properties().size() + _seed
				var random_letters := "0123456789abcdefghijklmnopqrstuvxyz"
				var new_hash : String = ""
				for _i in range(5):
					new_hash += random_letters[random.randi_range(0, random_letters.length()-1)]
				prop_sub_resource.id.set_hash(new_hash)
				_Logger.write('Imported SubResource "' + old_id + '" as "' + prop_sub_resource.id.to_string() + '"')
		
		# No ID issues with importing
		else:
			_Logger.write('Imported SubResource "' + prop_sub_resource.id.to_string() + '"')
		
		_imported_sub_resources_by_id[prop_sub_resource.id.to_string()] = prop_sub_resource
		var sub_res_code = prop_sub_resource.to_string()+'\n'  # Add the copied resource for insertion into the scene
		
		for sub_prop_key in prop_sub_resource.get_properties():
			var sub_prop : PropertyTree.ResourceProperty = prop_sub_resource.get_property(sub_prop_key)
			var sub_prop_val : String = import_property(sub_prop)
			sub_res_code += sub_prop_key+' = '+sub_prop_val+'\n'
		
		_imported_sub_resources_code += '\n'+sub_res_code
		
		return prop_sub_resource.to_ref_string()
	
	elif property is PropertyTree.ResourcePropertyArray:
		# Handle and check the type and items
		var array_type := ""
		if property.type != null:
			array_type = import_property(property.type)
		
		var result = "["
		
		if array_type != "":
			result = "Array["+array_type+"](["
		
		if !property.is_empty():
			result += import_property(property.get_item(0))
			var item_idx := 1
			while item_idx < property.size():
				result += ', '+import_property(property.get_item(item_idx))
				item_idx += 1
		
		result += "]"
		if array_type != "":
			result += ")"
		
		return result
	
	elif property is PropertyTree.ResourcePropertyDictionary:
		# Handle and check the type and items
		var dict_key_type := ""
		var dict_value_type := ""
		if property.key_type != null:
			dict_key_type = import_property(property.key_type)
		if property.value_type != null:
			dict_value_type = import_property(property.value_type)
		
		var result = "["
		
		if dict_value_type != "":
			result = "Dictionary["+dict_key_type+", "+dict_value_type+"]({"
		
		if !property.is_empty():
			var keys : Array = property.keys()
			result += '\n'+import_property(keys[0])+': '+import_property(property.get_item(keys[0]))
			var key_idx := 1
			while key_idx < keys.size():
				var key = keys[key_idx]
				result += ',\n'+import_property(key)+': '+import_property(property.get_item(key))
				key_idx += 1
			result += '\n'
		
		result += "}"
		if dict_value_type != "":
			result += ")"
		
		return result
	
	else:
		# Any other property is just a plain value
		return property.make_string()


func get_dependencies(source_data : String) -> Array[String]:
	var dependencies = []
	
	var lines : PackedStringArray = source_data.split("\n")
	var i : int = 0
	while i < lines.size():
		var line : String = lines[i]
		
		if line.begins_with('[ext_resource') and line.contains('type="PackedScene"'):
			var tokens : PackedStringArray = line.split(" ", false)
			var token_i : int = 0
			while token_i < tokens.size():
				var token : String = tokens[token_i]
				token_i += 1
				
				if token.begins_with('uid="'):
					var token_j : int = token_i
					
					while !token.ends_with('"') and token_j < tokens.size(): token += ' ' + tokens[token_j]; token_j += 1
					var uid : String = _get_string_value(token)
					if uid.is_empty(): continue
					
					dependencies.append(uid)
	
	return dependencies


func get_uid(source_data : String) -> String:
	# The First UID seems to be the resource's UID
	#if source_data.begins_with("[gd_scene") or source_data.begins_with("[gd_resource"):
	var tokens : PackedStringArray = source_data.split(" ", false)
	for token in tokens:
		if token.begins_with('uid="'):
			var uid : String = _get_string_value(token)
			if uid.is_empty(): continue
			
			return uid
	
	return ""


func _get_string_value(token : String) -> String:
	var start : int = token.find('"')
	var end : int = token.find('"', start + 1)
	if end == -1:
		return ""
	
	return token.substr(start + 1, end - (start + 1))


func get_source_data() -> String:
	return _source_data


func get_data() -> String:
	return _data


func set_data(custom : String) -> void:
	_data = custom


func _replace_first(str : String, replace : String, with : String) -> String:
	var idx : int = str.find(replace)
	if idx == -1:
		return str
	elif idx == 0:
		return with + str.substr(idx + replace.length())
	else:
		return str.substr(0, idx) + with + str.substr(idx + replace.length())


func _read_string(input : String) -> String:
	var out : String
	var str_end : String
	for char in input:
		if char == "'" or char == '"':
			if str_end:
				return out
			str_end = char
		elif str_end:
			out += char
	return out
