-- Normalized time, independent of frame rate. Presentation only.
local Motion = {}

function Motion.Progress(t, startTime, endTime)
	return math.clamp((t - startTime) / (endTime - startTime), 0, 1)
end

function Motion.Out(t)
	return 1 - (1 - math.clamp(t, 0, 1)) ^ 3
end

function Motion.State(kind, t)
	t = math.clamp(t, 0, 1)
	if kind == "Execute" then
		return { close = Motion.Progress(t, 0, 0.28) ^ 2,
			burst = Motion.Out(Motion.Progress(t, 0.28, 1)), fade = Motion.Progress(t, 0.48, 1) }
	elseif kind == "Shatter" then
		return { crack = Motion.Progress(t, 0, 0.28),
			burst = Motion.Out(Motion.Progress(t, 0.28, 1)), fade = Motion.Progress(t, 0.40, 1) }
	elseif kind == "Crushing" then
		return { compress = Motion.Out(Motion.Progress(t, 0, 0.25)),
			burst = Motion.Out(Motion.Progress(t, 0.34, 1)), fade = Motion.Progress(t, 0.45, 1) }
	elseif kind == "Piercing" then
		return { thrust = Motion.Out(Motion.Progress(t, 0, 0.45)),
			burst = Motion.Out(Motion.Progress(t, 0.20, 1)), fade = Motion.Progress(t, 0.30, 1) }
	end
	return nil
end

return Motion
