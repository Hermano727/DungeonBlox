--[[
  EquipService (legacy stub)
  Equip/unequip remotes are owned by DungeonBootstrap as RemoteFunctions.
  Keeping this script empty avoids duplicate RemoteEvents under the same names.

  Confirmed dead by this audit (2026-08-21): nothing requires this module and
  it defines no globals other functions call. Left in place, empty, only so
  its filename keeps documenting where equip/unequip actually live now. See
  the header comment at the top of shared/DataSchema.lua for the full map of
  DungeonBlox's two parallel profile systems, of which this stub is a remnant.
]]

print("[EquipService] stub; DungeonBootstrap owns DungeonEquipItem / DungeonUnequipItem")
