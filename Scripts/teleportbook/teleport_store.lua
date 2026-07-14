local store = {}
store.__index = store

local function trim(value)
	return value:match("^%s*(.-)%s*$") or ""
end

local function format_number(value)
	local text = string.format("%.3f", value)
	text = text:gsub("(%..-)0+$", "%1")
	return text:gsub("%.$", "")
end

local function format_coordinates(point)
	return string.format(
		"%s, %s, %s",
		format_number(point.x),
		format_number(point.y),
		format_number(point.z)
	)
end

local function parse_coordinates(value)
	local x, y, z = value:match(
		'^%s*([%+%-]?[%d%.]+)%s*,%s*([%+%-]?[%d%.]+)%s*,%s*([%+%-]?[%d%.]+)%s*$'
	)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not x or not y or not z then
		return nil, "coordinate must use the format x, y, z"
	end
	return x, y, z
end

local function escape_json(value)
	value = value:gsub("\\", "\\\\")
	value = value:gsub('"', '\\"')
	value = value:gsub("\b", "\\b")
	value = value:gsub("\f", "\\f")
	value = value:gsub("\n", "\\n")
	value = value:gsub("\r", "\\r")
	return value:gsub("\t", "\\t")
end

local function parse_json_string(text, position)
	if text:sub(position, position) ~= '"' then
		return nil, nil, "expected JSON string"
	end

	local output = {}
	position = position + 1
	while position <= #text do
		local char = text:sub(position, position)
		if char == '"' then
			return table.concat(output), position + 1
		end
		if char == "\\" then
			local escaped = text:sub(position + 1, position + 1)
			local replacements = {
				['"'] = '"',
				["\\"] = "\\",
				["/"] = "/",
				b = "\b",
				f = "\f",
				n = "\n",
				r = "\r",
				t = "\t",
			}
			if not replacements[escaped] then
				return nil, nil, "unsupported JSON escape sequence"
			end
			table.insert(output, replacements[escaped])
			position = position + 2
		else
			if char:byte() < 32 then
				return nil, nil, "unescaped control character in JSON string"
			end
			table.insert(output, char)
			position = position + 1
		end
	end

	return nil, nil, "unterminated JSON string"
end

local function skip_whitespace(text, position)
	local _, finish = text:find("^%s*", position)
	return (finish or position - 1) + 1
end

local function decode_flat_json(text)
	local position = skip_whitespace(text, 1)
	if text:sub(position, position) ~= "{" then
		return nil, "JSON root must be an object"
	end
	position = skip_whitespace(text, position + 1)
	local result = {
		map = {},
		ordered = {},
	}

	if text:sub(position, position) == "}" then
		return result
	end

	while true do
		local name, next_position, err = parse_json_string(text, position)
		if not name then
			return nil, err
		end
		position = skip_whitespace(text, next_position)
		if text:sub(position, position) ~= ":" then
			return nil, "expected ':' after point name"
		end
		position = skip_whitespace(text, position + 1)

		local coordinates
		coordinates, next_position, err = parse_json_string(text, position)
		if not coordinates then
			return nil, err
		end
		if result.map[name] then
			return nil, "duplicate point name: " .. name
		end
		result.map[name] = coordinates
		table.insert(result.ordered, {
			name = name,
			coordinates = coordinates,
		})

		position = skip_whitespace(text, next_position)
		local separator = text:sub(position, position)
		if separator == "}" then
			return result
		end
		if separator ~= "," then
			return nil, "expected ',' or '}' after coordinates"
		end
		position = skip_whitespace(text, position + 1)
	end
end

function store.new(path)
	return setmetatable({ path = path, points = {}, selected_index = 1 }, store)
end

function store:get_points()
	return self.points
end

function store:get_selected()
	return self.points[self.selected_index]
end

function store:select(index)
	if #self.points == 0 then
		self.selected_index = 1
		return nil
	end
	self.selected_index = math.max(1, math.min(index, #self.points))
	return self:get_selected()
end

function store:move_selection(delta)
	return self:select(self.selected_index + delta)
end

function store:load()
	local file = io.open(self.path, "r")
	if not file then
		local created, create_err = io.open(self.path, "w")
		if not created then
			return nil, "cannot create data file: " .. tostring(create_err)
		end
		created:write("{}\n")
		created:close()
		self.points = {}
		self.selected_index = 1
		return true
	end

	local content = file:read("*a")
	file:close()
	if not content or trim(content) == "" then
		return nil, "data file is empty; expected a JSON object"
	end

	local decoded, decode_err = decode_flat_json(content)
	if not decoded then
		return nil, "invalid teleports.json: " .. decode_err
	end

	local loaded = {}
	for _, entry in ipairs(decoded.ordered) do
		local x, y, z = parse_coordinates(entry.coordinates)
		if not x then
			return nil, string.format("invalid coordinates for '%s': %s", entry.name, y)
		end
		table.insert(loaded, { name = entry.name, x = x, y = y, z = z })
	end

	self.points = loaded
	self:select(self.selected_index)
	return true
end

function store:save()
	local lines = { "{" }
	for index, point in ipairs(self.points) do
		local comma = index < #self.points and "," or ""
		table.insert(
			lines,
			string.format(
				'    "%s": "%s"%s',
				escape_json(point.name),
				escape_json(format_coordinates(point)),
				comma
			)
		)
	end
	table.insert(lines, "}")

	local file, err = io.open(self.path, "w")
	if not file then
		return nil, "cannot write data file: " .. tostring(err)
	end
	local ok, write_err = pcall(function()
		file:write(table.concat(lines, "\n"), "\n")
	end)
	file:close()
	if not ok then
		return nil, "failed to save data file: " .. tostring(write_err)
	end
	return true
end

function store:add_current_location(x, y, z)
	if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
		return nil, "player location is invalid"
	end

	local names = {}
	for _, point in ipairs(self.points) do
		names[point.name] = true
	end
	local suffix = 1
	local name = "Point"
	while names[name] do
		suffix = suffix + 1
		name = string.format("Point %02d", suffix)
	end

	local point = { name = name, x = x, y = y, z = z }
	table.insert(self.points, point)
	self.selected_index = #self.points
	local saved, save_err = self:save()
	if saved then
		return point
	end

	table.remove(self.points, #self.points)
	self:select(self.selected_index)
	return nil, save_err
end

function store.format_coordinates(point)
	return format_coordinates(point)
end

return store