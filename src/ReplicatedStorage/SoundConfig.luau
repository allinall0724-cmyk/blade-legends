--!strict
-- SoundConfig: asset ids for every sound effect / ambience, pulled from the
-- Roblox Toolbox audio search. These are best-effort — Roblox's audio
-- permission system may block some from playing in a given experience; swap any
-- that don't play for owned/approved audio. Missing/blocked audio just stays
-- silent (no errors).

local SoundConfig = {}

-- one-shot SFX
SoundConfig.SFX = {
	swing = 137628815514180,
	hit = 128314503038887,
	equip = 139719503904449,
	caseOpen = 108306323478967,
	portal = 88350532436520,
	ability = 84614228601392,
	kill = 121642440688650,
	rankUp = 3454671965,
	click = 139804904213958,
	explosion = 133721752842563,
	victory = 3454671965,
}

-- looped ambience per zone (volume kept low)
SoundConfig.Ambience = {
	hub = 140736591220630,        -- wind
	casual = 126615573673174,     -- crowd
	ranked = 140736591220630,     -- wind (tense)
	trading = 95419260268767,     -- market-ish crowd
	leaderboard = 9067124098,     -- royal/fanfare bed
	weaponHall = 5799870105,      -- soft wind
}

function SoundConfig.sfxId(name: string): string
	local id = SoundConfig.SFX[name]
	return id and ("rbxassetid://" .. id) or ""
end

function SoundConfig.ambienceId(name: string): string
	local id = SoundConfig.Ambience[name]
	return id and ("rbxassetid://" .. id) or ""
end

return SoundConfig
