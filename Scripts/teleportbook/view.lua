local view = {}

local function vector2(x, y)
	local ok, result = pcall(function() return FVector2D(x, y) end)
	if ok and result then
		return result
	end
	ok, result = pcall(function()
		local instance = FVector2D()
		instance.X = x
		instance.Y = y
		return instance
	end)
	if ok and result then
		return result
	end
	return nil
end

local function valid(value)
	if not value then
		return false
	end
	if type(value.IsValid) == "function" then
		local ok, result = pcall(function()
			return value:IsValid()
		end)
		return ok and result
	end
	return true
end

local function call(surface, method, ...)
	if not valid(surface) or not surface[method] then
		return false
	end
	local arguments = { ... }
	return pcall(function() surface[method](surface, table.unpack(arguments)) end)
end

local function text(surface, canvas, colors, value, x, y, color, scale)
	if canvas then
		local position, text_scale, shadow = vector2(x, y), vector2(scale, scale), vector2(1, 1)
		if position and text_scale and shadow then
			call(
				surface, "K2_DrawText", nil, value, position, text_scale, color, 0,
				colors.shadow, shadow, false, false, false, colors.border
			)
		end
	else
		call(surface, "DrawText", value, color, x, y, nil, scale, false)
	end
end

local function outline(surface, canvas, color, x, y, width, height)
	if canvas then
		local position, size = vector2(x, y), vector2(width, height)
		if position and size then call(surface, "K2_DrawBox", position, size, 2, color) end
	else
		call(surface, "DrawRect", color, x, y, width, 2)
		call(surface, "DrawRect", color, x, y + height - 2, width, 2)
		call(surface, "DrawRect", color, x, y, 2, height)
		call(surface, "DrawRect", color, x + width - 2, y, 2, height)
	end
end

local function contains(mouse_x, mouse_y, button)
	return mouse_x and mouse_y and mouse_x >= button.x and mouse_x <= button.x + button.width
		and mouse_y >= button.y and mouse_y <= button.y + button.height
end

function view.new(colors)
	return setmetatable({ colors = colors, buttons = {} }, { __index = view })
end

function view:draw(surface, width, height, canvas, model, mouse_x, mouse_y)
	self.buttons = {}
	local panel_width, panel_height = math.max(500, width * 0.34), math.max(420, height * 0.46)
	local panel_x, panel_y = (width - panel_width) * 0.5, (height - panel_height) * 0.12
	outline(surface, canvas, self.colors.border, panel_x, panel_y, panel_width, panel_height)
	text(surface, canvas, self.colors, "Teleport Book", panel_x + 18, panel_y + 18, self.colors.title, 1.15)
	text(
		surface, canvas, self.colors, "G Toggle | T Add | Enter Teleport | R Reload",
		panel_x + 18, panel_y + 48, self.colors.muted, 0.85
	)
	text(
		surface, canvas, self.colors, "Current: " .. model.current_location,
		panel_x + 18, panel_y + 74, self.colors.text, 0.9
	)
	text(surface, canvas, self.colors, model.status, panel_x + 18, panel_y + 98, self.colors.muted, 0.8)

	local function button(intent, label, x, y, button_width, index)
		local item = { intent = intent, index = index, x = x, y = y, width = button_width, height = 30 }
		table.insert(self.buttons, item)
		local border = contains(mouse_x, mouse_y, item) and self.colors.title or self.colors.border
		outline(surface, canvas, border, x, y, button_width, item.height)
		text(surface, canvas, self.colors, label, x + 10, y + 7, self.colors.text, 0.85)
	end

	local half = (panel_width - 48) * 0.5
	button("add", "Add Current Position", panel_x + 18, panel_y + 128, half)
	button("reload", "Reload JSON", panel_x + 30 + half, panel_y + 128, half)
	for index, point in ipairs(model.points) do
		local y = panel_y + 174 + (index - 1) * 34
		if y + 30 > panel_y + panel_height then break end
		local prefix = index == model.selected and "> " or "  "
		local label = prefix .. point.name .. " -> " .. string.format(
			"%.0f, %.0f, %.0f", point.x, point.y, point.z
		)
		button("teleport", label, panel_x + 18, y, panel_width - 36, index)
	end
end

function view:hit_test(mouse_x, mouse_y)
	for _, button in ipairs(self.buttons) do
		if contains(mouse_x, mouse_y, button) then return button end
	end
	return nil
end

return view