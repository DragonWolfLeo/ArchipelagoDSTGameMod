name = "Archipelago Randomizer"
version = "1.3.2.3"
description = "Version "..version.."\nThis is an implementation for Archipelago, a multi-game randomizer. To make use of this mod, you would need Archipelago!\n\nhttps://archipelago.gg"
author = "Dragon Wolf Leo"
version_compatible = "1.3"

-- ALSO if I forgot to credit him somewhere, this is built off of Niko's implementation:
-- https://steamcommunity.com/sharedfiles/filedetails/?id=3113451317

api_version = 10

-- Compatible with Don't Starve Together
dst_compatible = true

-- Not compatible with Don't Starve
dont_starve_compatible = false
reign_of_giants_compatible = false
shipwrecked_compatible = false

all_clients_require_mod = true 

icon_atlas = "modicon.xml"
icon = "modicon.tex"

server_filter_tags = {
}

configuration_options =
{
    -- Extra Damage Against Bosses
    {
        name = "extrabossdamage_initial",
        label = "Starting Stacks Damage vs. Bosses",
        options =
        {
            {description = "-20", data = -20 },
            {description = "-19", data = -19 },
            {description = "-18", data = -18 },
            {description = "-17", data = -17 },
            {description = "-16", data = -16 },
            {description = "-15", data = -15 },
            {description = "-14", data = -14 },
            {description = "-13", data = -13 },
            {description = "-12", data = -12 },
            {description = "-11", data = -11 },
            {description = "-10", data = -10 },
            {description = "-9",  data = -9  },
            {description = "-8",  data = -8  },
            {description = "-7",  data = -7  },
            {description = "-6",  data = -6  },
            {description = "-5",  data = -5  },
            {description = "-4",  data = -4  },
            {description = "-3",  data = -3  },
            {description = "-2",  data = -2  },
            {description = "-1",  data = -1  },
            {description = "0",   data = 0   },
            {description = "1",   data = 1   },
            {description = "2",   data = 2   },
            {description = "3",   data = 3   },
            {description = "4",   data = 4   },
            {description = "5",   data = 5   },
            {description = "6",   data = 6   },
            {description = "7",   data = 7   },
            {description = "8",   data = 8   },
            {description = "9",   data = 9   },
            {description = "10",  data = 10  },
            {description = "11",  data = 11  },
            {description = "12",  data = 12  },
            {description = "13",  data = 13  },
            {description = "14",  data = 14  },
            {description = "15",  data = 15  },
            {description = "16",  data = 16  },
            {description = "17",  data = 17  },
            {description = "18",  data = 18  },
            {description = "19",  data = 19  },
            {description = "20",  data = 20  },
        },
        default = 0,
        hover = "Number of stacks of Extra Damage Against Bosses you start with.",
    },
    {
        name = "extrabossdamage_mult",
        label = "Damage vs. Easy Boss Multiplier",
        options =
        {
            {description = "0%",    data = 0.00, hover = "Disable bonus damage against easier bosses"},
            {description = "+10%",  data = 0.10, hover = "Ten stacks result into a multiplier of x2.6"},
            {description = "+15%",  data = 0.15, hover = "Ten stacks result into a multiplier of x4.0"},
            {description = "+20%",  data = 0.20, hover = "Ten stacks result into a multiplier of x6.1"},
            {description = "+25%",  data = 0.25, hover = "Ten stacks result into a multiplier of x9.3"},
            {description = "+30%",  data = 0.30, hover = "Ten stacks result into a multiplier of x13.7"},
            {description = "+40%",  data = 0.40, hover = "Ten stacks result into a multiplier of x28.9"},
            {description = "+50%",  data = 0.50, hover = "Ten stacks result into a multiplier of x57.7"},
            {description = "+60%",  data = 0.60, hover = "Ten stacks result into a multiplier of x110.0"},
            {description = "+70%",  data = 0.70, hover = "Ten stacks result into a multiplier of x201.6"},
            {description = "+80%",  data = 0.80, hover = "Ten stacks result into a multiplier of x357.0"},
            {description = "+90%",  data = 0.90, hover = "Ten stacks result into a multiplier of x613.1"},
            {description = "+100%", data = 1.00, hover = "Ten stacks result into a multiplier of x1024.0"},
        },
        default = 0.10,
        hover = "The damage multipier of each stack of Extra Damage Against Bosses against easier bosses that can be beaten by solo players.",
    },
    {
        name = "extrabossdamage_raid_mult",
        label = "Damage vs. Raid Boss Multiplier",
        options =
        {
            {description = "0%",    data = 0.00, hover = "Disable bonus damage against raid bosses"},
            {description = "+10%",  data = 0.10, hover = "Ten stacks result into a multiplier of x2.6"},
            {description = "+15%",  data = 0.15, hover = "Ten stacks result into a multiplier of x4.0"},
            {description = "+20%",  data = 0.20, hover = "Ten stacks result into a multiplier of x6.1"},
            {description = "+25%",  data = 0.25, hover = "Ten stacks result into a multiplier of x9.3"},
            {description = "+30%",  data = 0.30, hover = "Ten stacks result into a multiplier of x13.7"},
            {description = "+40%",  data = 0.40, hover = "Ten stacks result into a multiplier of x28.9"},
            {description = "+50%",  data = 0.50, hover = "Ten stacks result into a multiplier of x57.7"},
            {description = "+60%",  data = 0.60, hover = "Ten stacks result into a multiplier of x110.0"},
            {description = "+70%",  data = 0.70, hover = "Ten stacks result into a multiplier of x201.6"},
            {description = "+80%",  data = 0.80, hover = "Ten stacks result into a multiplier of x357.0"},
            {description = "+90%",  data = 0.90, hover = "Ten stacks result into a multiplier of x613.1"},
            {description = "+100%", data = 1.00, hover = "Ten stacks result into a multiplier of x1024.0"},
        },
        default = 0.25,
        hover = "The damage multipier of each stack of Extra Damage Against Bosses against harder bosses that are originally designed for multiplayer.",
    },
    -- Damage Bonus
    {
        name = "damagebonus_initial",
        label = "Starting Damage Bonus",
        options =
        {
            {description = "-20", data = -20 },
            {description = "-19", data = -19 },
            {description = "-18", data = -18 },
            {description = "-17", data = -17 },
            {description = "-16", data = -16 },
            {description = "-15", data = -15 },
            {description = "-14", data = -14 },
            {description = "-13", data = -13 },
            {description = "-12", data = -12 },
            {description = "-11", data = -11 },
            {description = "-10", data = -10 },
            {description = "-9",  data = -9  },
            {description = "-8",  data = -8  },
            {description = "-7",  data = -7  },
            {description = "-6",  data = -6  },
            {description = "-5",  data = -5  },
            {description = "-4",  data = -4  },
            {description = "-3",  data = -3  },
            {description = "-2",  data = -2  },
            {description = "-1",  data = -1  },
            {description = "0",   data = 0   },
            {description = "1",   data = 1   },
            {description = "2",   data = 2   },
            {description = "3",   data = 3   },
            {description = "4",   data = 4   },
            {description = "5",   data = 5   },
            {description = "6",   data = 6   },
            {description = "7",   data = 7   },
            {description = "8",   data = 8   },
            {description = "9",   data = 9   },
            {description = "10",  data = 10  },
            {description = "11",  data = 11  },
            {description = "12",  data = 12  },
            {description = "13",  data = 13  },
            {description = "14",  data = 14  },
            {description = "15",  data = 15  },
            {description = "16",  data = 16  },
            {description = "17",  data = 17  },
            {description = "18",  data = 18  },
            {description = "19",  data = 19  },
            {description = "20",  data = 20  },
        },
        default = 0,
        hover = "Number of stacks of Damage Bonus (against all mobs) you start with.",
    },
    {
        name = "damagebonus_mult",
        label = "Damage Bonus Multiplier",
        options =
        {
            {description = "0%",    data = 0.00, hover = "Disable bonus damage"},
            {description = "+10%",  data = 0.10, hover = "Ten stacks result into a multiplier of x2.6"},
            {description = "+15%",  data = 0.15, hover = "Ten stacks result into a multiplier of x4.0"},
            {description = "+20%",  data = 0.20, hover = "Ten stacks result into a multiplier of x6.1"},
            {description = "+25%",  data = 0.25, hover = "Ten stacks result into a multiplier of x9.3"},
            {description = "+30%",  data = 0.30, hover = "Ten stacks result into a multiplier of x13.7"},
            {description = "+40%",  data = 0.40, hover = "Ten stacks result into a multiplier of x28.9"},
            {description = "+50%",  data = 0.50, hover = "Ten stacks result into a multiplier of x57.7"},
            {description = "+60%",  data = 0.60, hover = "Ten stacks result into a multiplier of x110.0"},
            {description = "+70%",  data = 0.70, hover = "Ten stacks result into a multiplier of x201.6"},
            {description = "+80%",  data = 0.80, hover = "Ten stacks result into a multiplier of x357.0"},
            {description = "+90%",  data = 0.90, hover = "Ten stacks result into a multiplier of x613.1"},
            {description = "+100%", data = 1.00, hover = "Ten stacks result into a multiplier of x1024.0"},
        },
        default = 0.10,
        hover = "The damage multipier of each stack of Damage Bonus (against all mobs).",
    },
    {
        name = "craftingmode_override",
        label = "Crafting Mode Override",
        options =
        {
            {description = "No Override",        data = "none",              hover = "Use your YAML's settings."},
            {description = "Vanilla",            data = "vanilla",           hover = "Crafting behavior is vanilla."},
            {description = "Journey",            data = "journey",           hover = "Once you craft an item once, you can craft it again freely."},
            {description = "Free Samples",       data = "freesamples",       hover = "Once you unlock a recipe, you can craft one for free."},
            {description = "Free-Build",         data = "freebuild",         hover = "Once you unlock a recipe, you can always craft it."},
            ---- Not recommended overriding if not in logic
            -- {description = "Locked Ingredients", data = "lockedingredients", hover = "You cannot craft items that use one of your missing items as an ingredient."},
        },
        default = "none",
        hover = "Override Crafting Mode regardless of your YAML settings.",
    },
    {
        name = "deathlink_override",
        label = "Death Link Override",
        options =
        {
            {description = "No Override", data = "none",     hover = "Use your YAML's settings."},
            {description = "Disabled",    data = "disabled", hover = "Death Link is always off."},
            {description = "Enabled",     data = "enabled",  hover = "Death Link is always on."},
        },
        default = "none",
        hover = "Override Death Link regardless of your YAML settings.",
    },
    {
        name = "localdeathlink",
        label = "Local Death Link",
        options =
        {
            {description = "Match Death Link", data = "match",    hover = "Match Archipelago Death Link settings."},
            {description = "Disabled",         data = "disabled", hover = "Local Death Link is always off."},
            {description = "Enabled",          data = "enabled",  hover = "Local Death Link is always on."},
        },
        default = "match",
        hover = "When a player dies, all other players playing on the same world die.",
    },
    {
        name = "trapdecoyname_chance",
        label = "Trap Decoy Name Chance",
        options =
        {
            {description = "0%",   data = 0.00},
            {description = "1%",   data = 0.01},
            {description = "5%",   data = 0.05},
            {description = "10%",  data = 0.10},
            {description = "15%",  data = 0.15},
            {description = "20%",  data = 0.20},
            {description = "25%",  data = 0.25},
            {description = "30%",  data = 0.30},
            {description = "40%",  data = 0.40},
            {description = "50%",  data = 0.50},
            {description = "60%",  data = 0.60},
            {description = "70%",  data = 0.70},
            {description = "80%",  data = 0.80},
            {description = "90%",  data = 0.90},
            {description = "95%",  data = 0.95},
            {description = "99%",  data = 0.99},
            {description = "100%", data = 1.00},
        },
        default = 0.95,
        hover = "At a research station, the chance a trap item will disguise itself as a randomly generated name.",
    },
    {
        name = "receiveofflinetraps",
        label = "Receive Offline Traps",
        options =
        {
            {description = "Disabled", data = false, hover = "Ignore traps received offline, except season traps."},
            {description = "Enabled",  data = true,  hover = "Receive traps received offline upon connecting."},
        },
        default = true,
        hover = "Allow traps (besides season traps) received offline to still have an effect?",
    },
    {
        name = "deathlink_penalty",
        label = "Percentage Health Loss on Death Link",
        options =
        {
            {description = "10%",  data = 0.1},
            {description = "20%",  data = 0.2},
            {description = "30%",  data = 0.3},
            {description = "40%",  data = 0.4},
            {description = "50%",  data = 0.5},
            {description = "60%",  data = 0.6},
            {description = "70%",  data = 0.7},
            {description = "80%",  data = 0.8},
            {description = "90%",  data = 0.9},
            {description = "100%", data = 1.0},
        },
        default = 1.0,
        hover = "Amount of health lost when receiving a Death Link.",
    },
}