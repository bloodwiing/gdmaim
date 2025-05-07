extends RefCounted


var _text : String

var _list : Array[String]


func _init(text : String, delim : String = '\n', include_empty : bool = true) -> void:
	_text = text
	_prepare(delim, include_empty)


func _find_pos_int(what : String, from : int = 0) -> int:
	var temp : int = _text.find(what, from)
	if temp == -1:
		return 2147483647
	return temp

func _prepare(delim : String, include_empty : bool) -> void:
	_list.clear()
	
	var appended_idx : int = 0
	var processed_idx : int = 0
	
	var quote_mode : String = ""
	var bracket_counter : int = 0
	
	var sq_open_idx : int = _find_pos_int('[', processed_idx)
	var br_open_idx : int = _find_pos_int('{', processed_idx)
	var pr_open_idx : int = _find_pos_int('(', processed_idx)
	
	var sq_close_idx : int = _find_pos_int(']', processed_idx)
	var br_close_idx : int = _find_pos_int('}', processed_idx)
	var pr_close_idx : int = _find_pos_int(')', processed_idx)
	
	var qq_idx : int = _find_pos_int('"', processed_idx)
	var q_idx : int = _find_pos_int("'", processed_idx)
	var bslash_idx : int = _find_pos_int('\\', processed_idx)
	
	var delim_idx : int = _find_pos_int(delim, processed_idx)
	
	while processed_idx < _text.length():
		var bracket_open : Array[int] = [sq_open_idx, br_open_idx, pr_open_idx]
		var bracket_close : Array[int] = [sq_close_idx, br_close_idx, pr_close_idx]
		
		var bracket_open_idx : int = bracket_open.min() as int
		var bracket_close_idx : int = bracket_close.min() as int
		var bracket_idx : int = mini(bracket_close_idx, bracket_open_idx)
		
		var first_symbol_idx : int = min(bracket_idx, qq_idx, q_idx, bslash_idx, delim_idx) as int
		
		if delim_idx == first_symbol_idx:
			if bracket_counter == 0 and quote_mode == "":
				# A free delim (default: line feed)
				if include_empty or delim_idx-appended_idx > 0:
					var to_append : String = _text.substr(appended_idx, delim_idx-appended_idx)
					if include_empty or !to_append.is_empty():
						_list.append(to_append)
				appended_idx = delim_idx+delim.length()
			processed_idx = delim_idx+delim.length()
			delim_idx = _find_pos_int(delim, processed_idx)
		
		elif bslash_idx == first_symbol_idx:
			if quote_mode != "":
				# Escape slash sequence in strings, just skip the next symbol
				processed_idx = bslash_idx+2
			else:
				processed_idx = bslash_idx+1
			bslash_idx = _find_pos_int('\\', processed_idx)
		
		elif q_idx == first_symbol_idx or qq_idx == first_symbol_idx:
			# String quote
			var quote = '"' if qq_idx < q_idx else "'"
			if quote_mode == "":
				quote_mode = quote
			elif quote == quote_mode:
				quote_mode = ""
			
			if quote == '"':
				processed_idx = qq_idx+1
				qq_idx = _find_pos_int('"', processed_idx)
			else:
				processed_idx = q_idx+1
				q_idx = _find_pos_int("'", processed_idx)
		
		elif bracket_open_idx == first_symbol_idx:
			# Bracket opened
			var opener : int = bracket_open.find(bracket_open_idx)
			processed_idx = bracket_open_idx+1
			match opener:
				0:  # []
					sq_open_idx = _find_pos_int('[', processed_idx)
				1:  # {}
					br_open_idx = _find_pos_int('{', processed_idx)
				2:  # ()
					pr_open_idx = _find_pos_int('(', processed_idx)
			bracket_counter += 1
		
		elif bracket_close_idx == first_symbol_idx:
			# Bracket closed
			var closer : int = bracket_close.find(bracket_close_idx)
			processed_idx = bracket_close_idx+1
			match closer:
				0:  # []
					sq_close_idx = _find_pos_int(']', processed_idx)
				1:  # {}
					br_close_idx = _find_pos_int('}', processed_idx)
				2:  # ()
					pr_close_idx = _find_pos_int(')', processed_idx)
			bracket_counter -= 1
	
	if appended_idx < _text.length():
		_list.append(_text.substr(appended_idx))


func get_block(index : int) -> String:
	return _list[index]


func insert_block(index : int, value : String) -> void:
	_list.insert(index, value)


func size() -> int:
	return _list.size()


func is_empty() -> bool:
	return _list.is_empty()


func to_packed_string_array() -> PackedStringArray:
	return PackedStringArray(_list)
