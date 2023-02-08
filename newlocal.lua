return function(sc)
	local sg = Instance.new("ScreenGui", owner:FindFirstChildWhichIsA("PlayerGui"))
	sg.ResetOnSpawn = false

	local ls = NLS(sc, sg)
	local rm = Instance.new("RemoteEvent", ls)

	return rm, ls
end

