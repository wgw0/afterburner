--!strict
-- Save schema, migrations, replica and deltas (DAT-02 / DAT-03).

return function(ctx)
	local describe, it, expect = ctx.describe, ctx.it, ctx.expect
	local PlayerData = require(ctx.Shared.PlayerData)
	local Economy = require(ctx.Shared.Config.Economy)

	describe("template", function()
		it("a new account owns the starters, flies the first one and has the starting Credits", function()
			local data = PlayerData.template()
			expect(data.Version).toBe(PlayerData.VERSION)
			expect(data.Credits).toBe(Economy.STARTING_CREDITS)
			for _, id in Economy.STARTERS do
				expect(data.Aircraft[id].Owned).toBe(true)
				expect(data.Aircraft[id].Researched).toBe(true)
			end
			expect(#data.Lineup).toBe(1)
			expect(data.Lineup[1]).toBe(Economy.STARTERS[1])
		end)
	end)

	describe("migrations", function()
		-- After a rollback (REL-04) older code loads saves written by a newer release: it must not
		-- downgrade the version or drop fields it doesn't know, so the newer release reads them back.
		it("a save from a newer release keeps its version and unknown fields", function()
			local data = PlayerData.template()
			data.Version = PlayerData.VERSION + 2
			data.FutureField = { Nested = 7 }
			data.Credits = 99
			local _, applied = PlayerData.migrate(data)
			expect(#applied).toBe(0)
			expect(data.Version).toBe(PlayerData.VERSION + 2)
			expect(data.FutureField.Nested).toBe(7)
			expect(data.Credits).toBe(99)
		end)

		it("a current save passes through unchanged", function()
			local data = PlayerData.template()
			data.Credits = 1234
			local migrated, applied = PlayerData.migrate(data)
			expect(#applied).toBe(0)
			expect(migrated.Credits).toBe(1234)
		end)

		it("runs each step in order up to the target version", function()
			local order = {}
			local fixture = PlayerData.template()
			fixture.Version = 1
			local steps = {
				[2] = function(d)
					table.insert(order, 2)
					d.Renamed = d.Credits
				end,
				[3] = function(d)
					table.insert(order, 3)
					d.Renamed += 1
				end,
			}
			local migrated, applied = PlayerData.migrate(fixture, steps, 3)
			expect(#applied).toBe(2)
			expect(order[1]).toBe(2)
			expect(order[2]).toBe(3)
			expect(migrated.Version).toBe(3)
			expect(migrated.Renamed).toBe(fixture.Credits + 1) -- step 2 copied it, step 3 added 1
		end)

		it("an old save missing fields gets their defaults, and keeps what it had", function()
			local fixture = {
				Version = 1,
				Credits = 999,
				Aircraft = { F5E = PlayerData.newAircraft(true) },
				Lineup = { "F5E" },
			}
			local migrated = PlayerData.migrate(fixture)
			expect(migrated.Credits).toBe(999)
			expect(type(migrated.Flags)).toBe("table")
			expect(type(migrated.Stats.Kills)).toBe("number")
			expect(migrated.Aircraft.MiG21bis ~= nil).toBe(true) -- starters always owned
			expect(migrated.Settings.ControlScheme).toBe("MouseAim")
		end)

		it("a save with no version starts from version 0", function()
			local migrated, applied = PlayerData.migrate({})
			expect(migrated.Version).toBe(PlayerData.VERSION)
			expect(#applied).toBe(PlayerData.VERSION)
		end)

		it("bad settings are replaced by defaults; unknown keys are dropped", function()
			local fixture = PlayerData.template()
			fixture.Settings = { ControlScheme = "Telepathy", FieldOfView = 400, InvertPitch = true, Hack = 1 }
			local migrated = PlayerData.migrate(fixture)
			expect(migrated.Settings.ControlScheme).toBe("MouseAim")
			expect(migrated.Settings.FieldOfView).toBe(70)
			expect(migrated.Settings.InvertPitch).toBe(true)
			expect(migrated.Settings.Hack).toBe(nil)
		end)
	end)

	describe("receipts", function()
		it("keeps only the most recent purchase ids", function()
			local data = PlayerData.template()
			for i = 1, PlayerData.RECEIPT_HISTORY + 25 do
				PlayerData.rememberReceipt(data, `p{i}`)
			end
			expect(#data.ProcessedReceipts).toBe(PlayerData.RECEIPT_HISTORY)
			expect(data.ProcessedReceipts[1]).toBe("p26")
			expect(table.find(data.ProcessedReceipts, `p{PlayerData.RECEIPT_HISTORY + 25}`) ~= nil).toBe(true)
		end)
	end)

	describe("replica and deltas", function()
		it("the replica only carries the client's safe fields", function()
			local replica = PlayerData.replica(PlayerData.template())
			expect(replica.Credits ~= nil).toBe(true)
			expect(replica.ProcessedReceipts).toBe(nil)
			-- Passes is on the client since SHP-03: just which passes you own (already public as player
			-- attributes), needed for the lineup slot count
			expect(replica.Passes ~= nil).toBe(true)
			expect(replica.LevelRewardsClaimed).toBe(nil)
			expect(replica.Version).toBe(nil)
		end)

		it("no change, no delta; a change sends only that field", function()
			local data = PlayerData.template()
			local before = PlayerData.replica(data)
			expect(PlayerData.delta(before, PlayerData.replica(data))).toBe(nil)
			data.Credits += 100
			local delta = PlayerData.delta(before, PlayerData.replica(data)) :: any
			expect(delta.Credits).toBe(data.Credits)
			expect(delta.Aircraft).toBe(nil)
		end)

		it("a nested change (RP on one jet) is caught", function()
			local data = PlayerData.template()
			local before = PlayerData.replica(data)
			data.Aircraft.F5E.RP += 50
			local delta = PlayerData.delta(before, PlayerData.replica(data)) :: any
			expect(delta.Aircraft.F5E.RP).toBe(50)
		end)
	end)
end
