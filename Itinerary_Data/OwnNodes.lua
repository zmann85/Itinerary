-- Itinerary gather data, our own set: herbs and ore veins found in game (gathered, or passed within about 20
-- yards), zone map id -> node -> "x,y;x,y" in % of the zone map. Built by tools/bake_nodes.py.
local ns = ItineraryAPI
if not ns then return end
ns.GATHER_OWN = {
    zones = {
        [1416] = {
            ["Tin Vein"] = "13.87,88.26",
        },
        [1426] = {
            ["Copper Vein"] = "21.27,53.02",
            ["Earthroot"] = "47.56,59.65;39.73,62.57",
            ["Peacebloom"] = "44.33,57.99;48.34,62.53;48.83,58.45;39.07,61.38;31.68,38.65;27.83,42.08;43.41,46.59",
            ["Silverleaf"] = "44.5,56.13;48.91,61.59;39.44,61.96;34.7,36.41",
        },
        [1429] = {
            ["Copper Vein"] = "40.29,77.75;41.72,80.36;41.03,80.27;38.16,81.15;60.49,47.02;75.87,59.78;40.03,79.92;38.56,78.04;60.77,49.5;61.62,53.6",
            ["Earthroot"] = "48.24,50.16",
            ["Peacebloom"] = "38.55,87.13;66.14,63.09",
            ["Silverleaf"] = "55.9,66.9",
        },
        [1438] = {
            ["Peacebloom"] = "64.9,62.27;64.5,54.82",
        },
    },
}
