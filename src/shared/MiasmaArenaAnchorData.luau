-- Arena-local positions of every named Miasma encounter anchor, DERIVED from
-- MiasmaArenaLayout (the one placement source). Keeping gameplay anchors in Rojo-owned
-- source makes cloned dungeon realms deterministic and avoids hand-authored Studio
-- instances being removed on the next sync.
--
-- The graybox-era anchors (gate interact points at radius ~190, clog sockets, water release
-- points, radius-149 sack hooks) were retired in the 2026-09-25 player-scale layout pass;
-- the old values survive only in ServerStorage.MiasmaArenaBackups.
local Layout = require(script.Parent:WaitForChild("MiasmaArenaLayout"))

return table.freeze(Layout.Anchors())
