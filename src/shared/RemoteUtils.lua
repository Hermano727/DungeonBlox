--[[
	RemoteUtils
	Small "ensure this Instance exists with the right ClassName, recreate it if
	something else squatted the name" helpers. Several services (PartyService,
	ZoneService, PotionService, ProfileBootstrap, and others) each hand-rolled
	their own copy of this exact pattern; this module gives new/updated services
	a single place to pull it from instead of pasting another copy.

	Opt-in only: existing inline copies elsewhere are left untouched tonight so
	this refactor can't collide with other in-flight work on those files. New
	code (and PartyService/MountService as of this pass) can require this
	instead of redefining the same three helpers yet again.
]]

local RemoteUtils = {}

function RemoteUtils.EnsureFolder(parent, name)
	local inst = parent:FindFirstChild(name)
	if inst and inst:IsA("Folder") then
		return inst
	end
	if inst then
		inst:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function RemoteUtils.EnsureRemoteEvent(parent, name)
	local inst = parent:FindFirstChild(name)
	if inst and inst:IsA("RemoteEvent") then
		return inst
	end
	if inst then
		inst:Destroy()
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
end

function RemoteUtils.EnsureRemoteFunction(parent, name)
	local inst = parent:FindFirstChild(name)
	if inst and inst:IsA("RemoteFunction") then
		return inst
	end
	if inst then
		inst:Destroy()
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = parent
	return rf
end

return RemoteUtils
