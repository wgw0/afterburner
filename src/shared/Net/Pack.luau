--!strict
-- Compact binary packing for high-frequency network state (DEVELOPMENT.md §4.3, NET-03).
-- Missile state: id u16 · position f32×3 · velocity i16×3 (1/30 m/s steps, ±1092 m/s) · flags u8 = 21 bytes.

local Pack = {}

local MISSILE_BYTES = 21
local VELOCITY_SCALE = 30
Pack.MISSILE_BYTES = MISSILE_BYTES
Pack.MAX_PER_PACKET = 40 -- keeps each unreliable packet well under 1 KB

export type MissileSnapshot = {
	id: number,
	position: Vector3, -- studs
	velocity: Vector3, -- real m/s
	burning: boolean,
}

local function toI16(value: number): number
	return math.clamp(math.round(value * VELOCITY_SCALE), -32768, 32767)
end

function Pack.missiles(list: { MissileSnapshot }): buffer
	local b = buffer.create(2 + #list * MISSILE_BYTES)
	buffer.writeu16(b, 0, #list)
	for i, m in list do
		local o = 2 + (i - 1) * MISSILE_BYTES
		buffer.writeu16(b, o, m.id % 65536)
		buffer.writef32(b, o + 2, m.position.X)
		buffer.writef32(b, o + 6, m.position.Y)
		buffer.writef32(b, o + 10, m.position.Z)
		buffer.writei16(b, o + 14, toI16(m.velocity.X))
		buffer.writei16(b, o + 16, toI16(m.velocity.Y))
		buffer.writei16(b, o + 18, toI16(m.velocity.Z))
		buffer.writeu8(b, o + 20, if m.burning then 1 else 0)
	end
	return b
end

-- Returns nil for a malformed buffer.
function Pack.unpackMissiles(b: buffer): { MissileSnapshot }?
	local length = buffer.len(b)
	if length < 2 then
		return nil
	end
	local count = buffer.readu16(b, 0)
	if length ~= 2 + count * MISSILE_BYTES then
		return nil
	end
	local list = table.create(count)
	for i = 1, count do
		local o = 2 + (i - 1) * MISSILE_BYTES
		list[i] = {
			id = buffer.readu16(b, o),
			position = Vector3.new(buffer.readf32(b, o + 2), buffer.readf32(b, o + 6), buffer.readf32(b, o + 10)),
			velocity = Vector3.new(
				buffer.readi16(b, o + 14) / VELOCITY_SCALE,
				buffer.readi16(b, o + 16) / VELOCITY_SCALE,
				buffer.readi16(b, o + 18) / VELOCITY_SCALE
			),
			burning = buffer.readu8(b, o + 20) == 1,
		}
	end
	return list
end

return Pack
