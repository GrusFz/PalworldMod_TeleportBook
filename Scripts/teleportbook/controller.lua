local controller = {}
controller.__index = controller

function controller.new(store, game, config)
	return setmetatable({
		store = store,
		game = game,
		config = config,
		visible = false,
		current_location = nil,
		status = "Ready",
	}, controller)
end

function controller:refresh_location()
	local location, err = self.game.get_location()
	self.current_location = location
	if not location then
		self.status = "Location unavailable: " .. err
	end
	return location
end

function controller:load()
	local ok, err = self.store:load()
	if not ok then
		self.status = err
		return nil
	end
	self.status = string.format("Loaded %d saved point(s)", #self.store:get_points())
	return true
end

function controller:toggle_ui()
	self.visible = not self.visible
	self.game.set_ui_input_enabled(self.visible)
	if self.visible then
		self:refresh_location()
		self.status = string.format("Loaded %d saved point(s)", #self.store:get_points())
		print("[TeleportBook] UI opened\n")
	else
		print("[TeleportBook] UI closed\n")
	end
	return self.visible
end

function controller:add_current_point()
	local location = self:refresh_location()
	if not location then
		return nil
	end
	local point, err = self.store:add_current_location(location.x, location.y, location.z)
	if not point then
		self.status = err
		return nil
	end
	self.status = "Saved " .. point.name
	return point
end

function controller:reload()
	return self:load()
end

function controller:select(index)
	self.store:select(index)
end

function controller:move_selection(delta)
	self.store:move_selection(delta)
end

function controller:teleport_selected()
	local point = self.store:get_selected()
	if not point then
		self.status = "No point selected"
		return nil
	end
	local ok, err = self.game.teleport(point, self.config.teleport_tolerance)
	if not ok then
		self.status = "Teleport failed: " .. err
		return nil
	end
	self:refresh_location()
	self.status = "Teleported to " .. point.name
	return true
end

function controller:get_view_model()
	local current = self.current_location and self.store.format_coordinates(self.current_location) or "Unavailable"
	return {
		visible = self.visible,
		points = self.store:get_points(),
		selected = self.store.selected_index,
		current_location = current,
		status = self.status,
	}
end

return controller