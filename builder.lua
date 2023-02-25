local clone = script.Clone

local debris = game:GetService("Debris")

local classes = {}
local oldInstance = Instance

local function find(tbl, val)
	for i, v in tbl do
		if val == v then
			return i
		end
	end
	return false
end

local Instance = {}

function Instance.new(name, parent)
    if not classes[name] then
        classes[name] = oldInstance.new(name)
    end
    local n = clone(classes[name])
    n.Parent = parent
    return n
end

local function updatehook(tbl, callback)
	local prox = newproxy(true)

	local mt = getmetatable(prox)

	mt.__index = tbl

	function mt:__newindex(i, v)
		tbl[i] = v
		callback(i, v)
	end

	function mt:__iter()
		return next, tbl
	end

	function mt:__len()
		return #tbl
	end

	return prox
end

local function selectonly(i, ...)
	return ({...})[i]
end

local function set(obj, i, v)
	obj[i] = v
end

local function isdestroyed(i)
	return not not (selectonly(2, pcall(set, i, "Parent", i)):lower():match("locked"))
end

local eventlisteners = {}

local builder = {}

builder.version = "testa"

warn("Loaded Apache's builder api. Version: " .. builder.version)

builder.datatype = {
	Property = newproxy(),
	IgnoredProperty = newproxy(),
	Connection = newproxy(),
	PropertyConnection = newproxy(),
	EventListener = newproxy(),
	Child = newproxy(),
	Parent = newproxy()
}

function builder.property(index, value)
	if index == "Parent" then
		error("Invalid property index, use `builder.parent` instead.")
	end

	return {
		type = builder.datatype.Property,
		index = index,
		value = value
	}
end

function builder.ignoredproperty(index)
	return {
		type = builder.datatype.IgnoredProperty,
		index = index
	}
end

function builder.connection(signalname, callback)
	return {
		type = builder.datatype.Connection,
		signalname = signalname,
		callback = callback
	}
end

function builder.propertyconnection(index, callback)
	return {
		type = builder.datatype.PropertyConnection,
		index = index,
		callback = callback
	}
end

function builder.eventlistener(event, callback)
	return {
		type = builder.datatype.EventListener,
		event = event,
		callback = callback
	}
end

function builder.sendevent(event, ...)
	for _, e in eventlisteners do
		if e.event == event then
			task.defer(e.callback, ...)
		end
	end
end

function builder.parent(obj)
	return {
		type = builder.datatype.Parent,
		obj = obj
	}
end

function builder.new(class, datatbl)
	local obj; obj = {
		type = builder.datatype.Child,
		properties = {},
		ignoredproperties = {},
		vars = {},
		connections = {},
		propertyconnections = {},
		children = {},
		realconnections = {}
	}

	function obj:instance()
		while not obj.currentinstance or isdestroyed(obj.currentinstance) do
			task.wait()
		end
		return obj.currentinstance
	end

	local function connect(signal, callback)
		local c = signal:Connect(callback)
		table.insert(obj.realconnections, c)
		return c
	end

	local function disconnect(connection)
		connection:Disconnect()
		local idx = find(obj.realconnections, connection)
		if idx then
			table.remove(obj.realconnections, idx)
		end
	end

	for _, data in datatbl do
		if data.type == builder.datatype.Property then
			obj.properties[data.index] = data.value
		elseif data.type == builder.datatype.IgnoredProperty then
			obj.ignoredproperties[data.index] = true
		elseif data.type == builder.datatype.Connection then
			table.insert(obj.connections, data)
		elseif data.type == builder.datatype.PropertyConnection then
			table.insert(obj.propertyconnections, data)
		elseif data.type == builder.datatype.EventListener then
			table.insert(eventlisteners, data)
		elseif data.type == builder.datatype.Child then
			table.insert(obj.children, data)
			if data.parent then
				data.parent.obj = obj
			else
				data.parent = {obj = obj}
			end
			task.spawn(function()
				data:instance().Parent = obj:instance()
			end)
		elseif data.type == builder.datatype.Parent then
			obj.parent = data
		end
	end

	obj.properties = updatehook(setmetatable(obj.properties, {
		__index = function(self, i)
			return obj:instance()[i]
		end
	}), function(i, v)
		pcall(function()
			obj:instance()[i] = v
		end)
	end)

	function obj.destroy()
		for _, c in obj.realconnections do
			disconnect(c)
		end
		debris:AddItem(obj.currentinstance, 0)
	end

	function obj.fullremove()
		for _, c in obj.realconnections do
			disconnect(c)
		end
		for _, c in obj.children do
			c.fullremove()
		end
		obj.destroy()
		if obj.parent and not (type(obj.parent.obj) == "userdata" and obj.parent.obj.ClassName) then
			local idx = find(obj.parent.obj.children, obj)
			if idx then
				table.remove(obj.parent.obj.children, idx)
			end
		end
		for i in obj do
			obj[i] = nil
		end
	end

	function obj.create()
		if obj.currentinstance and not isdestroyed(obj.currentinstance) then
			obj.destroy()
		end

		local i = Instance.new(class)

		obj.currentinstance = i

		for idx, v in obj.properties do
			pcall(set, i, idx, v)
		end

		for _, pc in obj.propertyconnections do
			connect(i:GetPropertyChangedSignal(pc.index), pc.callback)
		end

		for _, c in obj.connections do
			connect(i[c.signalname], c.callback)
		end

		local ch; ch = connect(i.Changed, function(p)
			if not obj.create then
				disconnect(ch)
				return
			end
			if p == "Parent" or obj.ignoredproperties[p] then
				return
			end

			local s, err = pcall(function()
				local baseprop = obj.properties[p] or classes[class][p]
				i[p] = baseprop
			end)
			if not s then
				warn("Error: ", tostring(err))
			end
		end)

		local parent
		if obj.parent and obj.parent.obj then
			if type(obj.parent.obj) == "userdata" and obj.parent.obj.ClassName then
				parent = obj.parent.obj
			else
				parent = obj.parent.obj:instance()
			end
		end

		local ac; ac = connect(i.AncestryChanged, function()
			if not obj.create or type(obj.create) ~= "function" then
				disconnect(ac)
				return
			end
			if i.Parent ~= parent then
				task.defer(obj.create)
			end
		end)

		i.Parent = parent
	end

	obj.create()

	return obj
end

builder.Instance = Instance

return builder
