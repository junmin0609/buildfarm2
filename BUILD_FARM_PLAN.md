# BuildFarm Game Design Plan

## 0. Core Identity

BuildFarm is a 2D farming + building + factory automation game made with Godot.

The target balance is:

- Building : Farming : Factory = roughly 1 : 1 : 1
- No one system should completely dominate the others.
- Farming produces resources.
- Factory systems automate, process, store, and sell those resources.
- Building connects the systems through layout, logistics, expansion, and later decoration.

The game should gradually shift the player's role:

Manual labor
→ Farm operator
→ Production designer
→ Factory manager
→ Multi-region logistics manager
→ Market operator

Core automation principle:

> Automate repetitive labor, but leave important decisions to the player.

Automation should always create new decisions, bottlenecks, and expansion goals instead of removing gameplay.

---

# 1. Main World Structure

The world is divided into:

- Main Plaza
- Player-owned lands
- Special unlockable regions such as Sky Island

## Main Plaza

The Main Plaza is the central system hub.

Possible facilities:

- Seed shop
- General shop
- Blacksmith
- Chef / recipe shop
- Construction-related shop
- NPCs
- Quest and event systems
- Region transport
- Other future facilities

The plaza should look like a small town center with room to grow.

## Player-owned Land

Player-owned land is where the player can:

- Farm
- Build
- Automate
- Store items
- Process goods
- Generate power
- Decorate later

The starting farm should feel like abandoned land that the player gradually develops.

---

# 2. Starting Farm Condition

The starting land should not be a finished farm.

It contains:

- Weeds
- Small rocks
- Branches
- Stumps
- Large rocks
- Other natural obstacles

Approximate initial distribution:

- Immediately usable land: ~30%
- Land clearable with basic tools: ~50%
- Land blocked by stronger obstacles: ~20%

The farm should not be surrounded by a permanent fence.

Fences can later become player-placeable construction/decor items.

---

# 3. Region Expansion Philosophy

The player begins with one region and can unlock two additional major player-owned regions in the initial design.

Initial regions:

1. Starting Farm
2. Riverside Region
3. Mountain Region

Each region has advantages, but should never hard-force a specific playstyle.

Design principle:

> Regions suggest efficient strategies, but do not dictate them.

Regional bonuses should generally remain around 10–20%.

---

# 4. Starting Farm Characteristics

Balanced region.

- No major specialization bonus
- Best accessibility
- Contains player's house
- Good for mixed farming and factory development
- Main early-game base

---

# 5. Riverside Region Characteristics

Theme:

- Water
- Irrigation
- Agriculture
- Greenhouse use
- Water resources

Possible advantages:

- Better irrigation efficiency
- Reduced sprinkler water consumption
- Better water-facility efficiency
- Greenhouse-related bonuses
- Minor bonuses to water-demanding crops
- Unique resources such as clay or aquatic plants

Possible tradeoff:

- River and wetland shapes reduce some large rectangular building space

The player may still build factories here freely.

---

# 6. Mountain Region Characteristics

Theme:

- Ore
- Stone
- Power
- Industry

Possible advantages:

- Better ore/stone yield
- Generator output bonus
- Heavy-industry advantages
- Easier access to industrial materials
- Unique rare minerals

Possible tradeoff:

- Less flat land
- Large farm layouts may take more planning

The player may still farm here freely.

---

# 7. Region Unlock Method

Do not use a rigid farm/factory level.

Regions unlock through actual development conditions plus resource payment.

## Riverside Unlock Direction

Requirements should prove the player has experienced basic automation.

Suggested conditions:

- 2+ sprinklers installed
- 1+ auto harvester installed
- 1+ warehouse installed
- 1+ low-tier processor installed
- 1+ generator installed
- Meaningful conveyor usage
- At least one processed product successfully produced

Additional payment:

- Money
- Wood
- Stone
- Iron

Exact numbers later.

## Mountain Unlock Direction

Suggested conditions:

- Riverside unlocked
- 2+ warehouses operating
- 1+ mid-tier processor
- Multiple auto harvesters
- At least one complete conveyor-based production line
- 2–3 different processed products produced
- Meaningful power infrastructure
- Meaningful cumulative crop or processed-goods production

Additional payment:

- More money
- Iron
- Stone
- Wood
- Processed goods

Exact numbers later.

---

# 8. Region Unlock Presentation

Locked land is shown with:

- Crossed chains
- Central lock

Unlock animation:

- Chains loosen
- Chains fall away
- Lock opens
- Region becomes accessible

---

# 9. Farming Interaction Range

Farming actions work within 2 tiles in front of the player.

Applies to:

- Hoe
- Seed planting
- Watering
- Crop removal
- Harvesting

---

# 10. Farming Area Rules

Farming is allowed only on unlocked player-owned land.

The player decides freely where fields are created.

There is no fixed mandatory rectangular farm plot.

---

# 11. Tilled Soil

Basic farming flow:

Normal ground
→ Hoe
→ Tilled soil
→ Optional fertilizer
→ Seed
→ Water
→ Daily growth
→ Mature crop
→ Harvest

Tilled soil should visually connect to nearby tilled tiles.

Empty tilled soil can also be watered.

Watered soil becomes visually darker.

---

# 12. Tilled Soil Persistence

Harvesting does not immediately revert soil.

When season changes:

- Empty
- Dry

tilled tiles have a chance to revert to normal ground.

Initial target:

- Around 35%

Wet empty tilled soil remains tilled.

---

# 13. Watering Can

Watering can has finite water.

Initial example:

Basic watering can:

- Capacity: around 12 uses
- 1 watering action = 1 water

Exact balance later.

---

# 14. Well System

A well exists near the farm.

The player refills the watering can there.

The well should be convenient enough that early watering does not become excessive walking.

Long-term progression:

Well
→ Pump
→ Water tank
→ Automated irrigation network

---

# 15. Crop Growth Rule

Crops grow only if watered that day.

Water received:
→ Growth progress +1

No water:
→ No growth that day

Missing water does not kill the crop.

Growth resumes normally after future watering.

---

# 16. Rain

On rainy days:

- Outdoor tilled soil becomes watered
- Outdoor crops satisfy the water condition automatically

Greenhouse crops are unaffected by rain.

---

# 17. Crop Growth Stages

Actual growth days and visual stages are separate.

Typical visual stages:

- Seed
- Sprout
- Growing
- Mature

Multiple days can share one visual stage.

---

# 18. Harvesting

Mature crops are harvested by mouse click.

No harvest tool required.

Harvested items go directly into inventory.

If inventory is full:

- Harvest fails
- Crop remains
- Show "Inventory is full"

Items should never disappear due to lack of storage.

---

# 19. Crop Information

Clicking a growing crop shows compact info near the cursor.

Example:

Tomato  
Growing  
4 / 6 days  
Water today: Yes  
2 days until harvest

If not watered:

Water today: No  
Will not grow today

If mature:

Hover:
Tomato  
Ready to harvest

Click:
Harvest immediately

---

# 20. Interaction Priority

When multiple things overlap:

Crop
→ Facility
→ Dropped item
→ Ground

Crop interaction has priority.

---

# 21. Crop Collision

Crops do not block player movement.

---

# 22. Single-Harvest and Regrowing Crops

## Single-Harvest

Mature
→ Harvest
→ Crop disappears
→ Replant

## Regrowing

Mature
→ Harvest
→ Plant remains
→ Regrowth period
→ Harvest again

Example:

Tomato:
- First growth: 6 days
- Regrowth: 3 days

---

# 23. Crop Yield

Some crops always give one item.

Others give random amounts.

Examples:

- Carrot: 1
- Potato: 1–3
- Tomato: 1–3
- Blueberry: multiple

---

# 24. Crop Quality

Qualities:

- Bronze
- Silver
- Gold

Base sale multipliers:

- Bronze ×1.0
- Silver ×1.25
- Gold ×1.6

Exact balance later.

---

# 25. Fertilizer System

Fertilizer changes quality probabilities.

Basic tiers:

- Basic Fertilizer
- Advanced Fertilizer
- Premium Fertilizer

Initial probability concept:

No fertilizer:
- Bronze 80%
- Silver 18%
- Gold 2%

Basic:
- Bronze 60%
- Silver 35%
- Gold 5%

Advanced:
- Bronze 35%
- Silver 50%
- Gold 15%

Premium:
- Bronze 15%
- Silver 45%
- Gold 40%

Exact numbers can be tuned later.

---

# 26. Fertilizer Application

Order:

Till
→ Fertilize
→ Plant

Single-harvest crop:
- Fertilizer ends after harvest

Regrowing crop:
- Fertilizer remains while the plant remains alive

Fertilizer ends when the plant is removed or withers.

---

# 27. Fertilizer Acquisition

Fertilizer is available from shops with unlimited stock.

It can also be produced later using:

- Weeds
- Crop scraps
- Organic farm byproducts

---

# 28. Compost System

Possible inputs:

- Weeds
- Crop scraps
- Low-value produce
- Other organic byproducts

Compost bin:
Input
→ Day-based waiting period
→ Basic fertilizer

Agricultural processes like composting should generally use day-based timing rather than factory-style seconds.

---

# 29. Crop Removal

Wrongly planted or withered crops can be removed using:

- Hoe
- Pickaxe

Seed is not returned.

Underlying tilled soil remains.

---

# 30. Seasons

Each season lasts 28 days.

Order:

Spring
→ Summer
→ Autumn
→ Winter
→ Spring

1 year = 112 days.

---

# 31. Seasonal Roles

## Spring

- Learn farming
- Build initial capital
- Fast/simple crops

## Summer

- Expand farm scale
- Regrowing crops
- Highest rain frequency
- Mid-summer monsoon feeling

## Autumn

- Highest-profit season
- Harvest season
- Prepare money/resources for winter
- Golden Pumpkin

## Winter

- No outdoor farming
- Greenhouse farming only
- Processing
- Automation maintenance
- Tool upgrades
- Next-year preparation
- Frost Flower

---

# 32. Weather

Initial weather:

- Sunny
- Cloudy
- Rain
- Snow in winter

No next-day forecast.

The player discovers the day's weather in the morning.

Weather stays fixed for the whole day.

---

# 33. Summer Rain Pattern

Possible structure:

- Early summer: moderate rain
- Mid-summer: high rain / monsoon
- Late summer: lower rain

Exact probabilities later.

---

# 34. Season Change Crop Rules

Each crop has allowed seasons.

When a new season is unsupported:

- Crop immediately withers
- Stops growing
- Cannot be harvested
- Cannot recover with water
- Must be removed

Multi-season crops survive if the next season is valid.

Example:

Corn:
- Summer + Autumn
- Survives Summer → Autumn
- Withers Autumn → Winter

---

# 35. Winter and Greenhouse

Outdoor farming is disabled in winter.

Greenhouse:

- Ignores season restrictions
- Ignores weather
- Allows crops from any season
- Supports automation

Preparing a greenhouse before the first winter should become an important autumn objective.

---

# 36. Spring Crops

## Carrot
- Growth: 3 days
- Regrow: No
- Yield: 1
- Seed: 20G
- Bronze: 35G
- Silver: 44G
- Gold: 56G
- Role: beginner crop

## Potato
- Growth: 5 days
- Regrow: No
- Yield: 1–3
- Seed: 45G
- Bronze: 30G each
- Silver: 38G
- Gold: 48G
- Role: multi-yield crop

## Strawberry
- Growth: 7 days
- Regrow: every 3 days
- Yield: 1–3
- Seed: 120G
- Bronze: 45G
- Silver: 56G
- Gold: 72G
- Role: regrowing crop introduction

## Cabbage
- Growth: 8 days
- Regrow: No
- Yield: 1
- Seed: 70G
- Bronze: 125G
- Silver: 156G
- Gold: 200G
- Role: slower high-value spring crop

## Wheat
- Growth: 4 days
- Regrow: No
- Yield: 1
- Seed: 25G
- Bronze: 35G
- Silver: 44G
- Gold: 56G
- Seasons: Spring + Summer
- Role: processing material

---

# 37. Summer Crops

## Tomato
- First growth: 6 days
- Regrow: every 3 days
- Yield: 1–3
- Seed: 90G
- Bronze: 38G
- Silver: 48G
- Gold: 61G

## Blueberry
- First growth: 8 days
- Regrow: every 4 days
- Yield: 2–4
- Seed: 140G
- Bronze: 32G
- Silver: 40G
- Gold: 51G

## Corn
- First growth: 9 days
- Regrow: every 4 days
- Yield: 1–2
- Seed: 110G
- Bronze: ~60G
- Seasons: Summer + Autumn

## Watermelon
- First growth: 10 days
- Regrow: every 5 days
- Yield: 1
- Seed: 120G
- Bronze: 110G
- Silver: 138G
- Gold: 176G

## Wheat
Same as spring.

---

# 38. Autumn Crops

Autumn should be the most profitable season.

## Sweet Potato
- Growth: 5 days
- Regrow: No
- Yield: 1–3
- Seed: 65G
- Bronze: 50G each

## Eggplant
- First growth: 6 days
- Regrow: every 3 days
- Yield: 1–2
- Seed: 100G
- Bronze: 60G each

## Pumpkin
- Growth: 10 days
- Regrow: No
- Yield: 1
- Seed: 140G
- Bronze: 300G
- Silver: 375G
- Gold: 480G

## Radish
- Growth: 4 days
- Regrow: No
- Yield: 1
- Seed: 35G
- Bronze: 60G

## Corn
Continues from summer.

---

# 39. Golden Pumpkin

Autumn special crop.

Not sold by default from the beginning.

Possible unlock conditions later:

- Harvest milestone
- Quest
- Town development
- Special project

Basic concept:

- Autumn only
- Growth: around 12 days
- No regrowth
- Yield: 1
- Very expensive seed
- Very high sale value

## Overgrowth

At maturity, the player may leave it growing.

Example:

Mature:
- Ready to harvest

+1 day:
- +15% value

+2 days:
- +35%

+3 days:
- Fully overgrown
- +60%

Beyond:
- Rotten Golden Pumpkin
- Major value loss

The model should visually become larger and more golden as it overgrows.

---

# 40. Winter Crops

General greenhouse crop candidates:

- Spinach
- Broccoli
- Sugar beet

Other seasonal crops may also be grown in greenhouse.

---

# 41. Frost Flower

Winter special crop.

Only one major winter special crop initially.

Concept:

- Greenhouse only
- Growth: around 10 days
- No regrowth
- Yield: 1
- Seed: around 220G

Example sale values:

- Bronze: 420G
- Silver: 525G
- Gold: 672G

Visual:

- Pale blue
- White
- Ice-crystal-like petals
- Slight sparkle when mature

Possible processing chain:

Frost Flower
→ Frost Crystal
→ Frost Essence

---

# 42. Tools

Basic tools:

- Hoe
- Watering Can
- Axe
- Pickaxe

Construction uses building mode.

---

# 43. Blacksmith

Located in Main Plaza.

Used for tool upgrades.

Tool upgrades should directly improve usability.

## Hoe
- Increased tilling area

## Watering Can
- Larger capacity
- Larger watering area

## Axe
- Faster clearing
- Can clear larger stumps/trees

## Pickaxe
- Faster rock removal
- Can break larger rocks/ores

Upgrade costs:

- Money + resources

Initial direction:
- Upgrade completes immediately

---

# 44. Inventory

Slot-based inventory.

Initial concept:
- About 27 slots

## Hotbar
- 9 slots
- Bottom center

Inventory items can be dragged to the hotbar and back.

---

# 45. Item Tooltip

Do not use a permanent lower description panel.

Hovering an item shows a compact tooltip diagonally near the cursor.

If off-screen, flip to another side.

Hide tooltip while dragging.

---

# 46. Resource Clearing

Starting land materials:

Weed
→ Plant fiber / organic material

Rock
→ Stone

Branch / stump
→ Wood

These resources can feed:

- Fertilizer
- Compost
- Facilities
- Buildings
- Tool upgrades
- Power systems later

---

# 47. Obstacle Tiers

Tool upgrades unlock stronger obstacles.

Example:

Basic Pickaxe
→ Small rock

Improved Pickaxe
→ Large rock

High-tier Pickaxe
→ Special mineral obstacle

Same logic for axe/stumps.

---

# 48. Building-Farming-Factory Balance

Target:

Building : Farming : Factory ≈ 1 : 1 : 1

Building is not just decoration.

Building gameplay includes:

- Spatial planning
- Production layout
- Logistics routes
- Expansion
- Facility arrangement
- Later decoration

Detailed decoration systems can be designed later.

---

# 49. Building Mode

Building mode shows the grid.

Time stops during:

- Placement
- Move mode
- Demolition mode

Main modes:

- Place
- Move
- Demolish

---

# 50. Buildable Areas

Construction only on unlocked player-owned land.

---

# 51. Facility Sizes

Grid-snapped sizes may include:

- 1×1
- 2×2
- 3×3
- 3×4
- 4×4
- 4×5
- 5×5

Examples:

- Conveyor: 1×1
- Splitter: 1×1
- Small machine: 2×2
- Processor: 3×3
- Warehouse: 4×4
- Large generator: 5×5

---

# 52. Placement Rules

Cannot overlap facilities.

Placement fails if:

- Another facility occupies the area
- Region is locked
- Outside map bounds
- Special blocked terrain
- Large uncleared obstacle

Preview should clearly show valid/invalid placement.

---

# 53. Building on Tilled Soil

Facilities may be placed regardless of tilled status.

When built:
- Underlying area becomes building ground

When removed:
- Area returns to normal ground

---

# 54. Building Rotation

Rectangular buildings and directional facilities rotate in 90° steps.

Example:

3×4
→ rotate
→ 4×3

Input/output ports rotate with the building.

Suggested key:
- R

---

# 55. Facility Input/Output Ports

Processors, warehouses, and automation facilities can have input/output ports.

Ports are shown clearly in building mode.

They can be hidden during normal gameplay.

---

# 56. Conveyor System

Conveyors are ground-level logistics.

They do not block player movement.

They carry:

- Crops
- Materials
- Processed goods
- Other production items

---

# 57. Conveyor Placement

Click-and-drag placement.

Flow:

Select conveyor
→ Click start tile
→ Drag path
→ Confirm

Consumed pieces = tiles placed.

---

# 58. Conveyor Pathing

Paths snap to the grid.

Should support:

- Straight lines
- Corners
- Connected paths

Corner graphics should update automatically.

Advanced bend-direction controls can be added later if needed.

---

# 59. Conveyor Placement Preview

While dragging show:

- Planned length
- Required conveyors
- Current owned amount

If path exceeds inventory, excess section becomes invalid.

---

# 60. Conveyor Speed and Throughput

Exact belt speed is not fixed yet.

Keep it data-driven for later balancing.

Splitter initial rough idea:

- around 3 items per second

This is not final and should be easy to tune.

---

# 61. Conveyor Bottlenecks

If storage or processor input is blocked:

- Items do not disappear
- Items back up visibly on belts
- Production line can eventually stall

The player should visually recognize bottlenecks.

---

# 62. Conveyor Routing Facilities

Possible later logistics components:

- Splitter
- Merger
- Item filter
- Balanced distributor

Example:

Tomato → left
Eggplant → right

Detailed logistics behavior can be expanded later.

---

# 63. Moving Facilities

Move mode:

- No extra cost
- No material consumption
- Facility retains its identity/state
- Move succeeds only if new position is valid

Facility rearrangement should be experimentation-friendly.

---

# 64. Demolition

Demolition returns 100% of construction materials/items.

Conveyor demolition:
- Returns each conveyor piece

If a facility contains items:
- Return items to player inventory
- If inventory lacks space, demolition is blocked

No item should be deleted.

---

# 65. Area Demolition

For conveyors and repeated structures:

- Click = remove one
- Drag = remove selected range

All removed pieces are returned.

---

# 66. Auto Harvester

Auto harvester does not teleport crops directly into storage.

It outputs harvested items through an output port.

Example:

Crop field
→ Auto Harvester
→ Conveyor
→ Warehouse

---

# 67. Warehouse System

Warehouses are real physical storage facilities.

Rules:

- Each warehouse has limited capacity
- Capacity can be upgraded to a degree
- A single warehouse cannot become infinite
- Large production eventually requires multiple warehouses
- Warehouses are not automatically merged into one global inventory
- Physical logistics matters

Possible scale examples later:

- Small
- Medium
- Large

Exact capacities later.

---

# 68. Warehouse Filters

Warehouses can restrict accepted items.

Possible modes:

- Specific items
- Crops only
- Seeds only
- Materials only
- Processed goods only

This supports organized production lines.

---

# 69. Warehouse Bottleneck Role

When market prices are low:

Production
→ Warehouse
→ Wait for better price

But limited capacity forces choices:

- Build more storage
- Process items
- Sell early
- Reduce production

This is an intended management pressure.

---

# 70. Processing System

Avoid creating dozens of unique machine types.

Use universal processors with tiers:

- Low-tier Processor
- Mid-tier Processor
- Top-tier Processor

Tier differences:

Low-tier:
- Slow
- Low throughput
- Small internal buffers
- Basic recipes

Mid-tier:
- Faster
- Larger throughput
- Larger buffers
- Mid-tier recipes

Top-tier:
- Very fast
- High-volume
- Advanced recipes
- Special crop processing

Exact timing and throughput later.

---

# 71. Recipe System Direction

Recipes must be learned.

Main direction:

- Purchased from Chef / recipe shop
- Feels like learning from a chef
- Purchased once = permanently unlocked

Recipes should not all be available immediately.

Possible unlock factors:

- Season
- Quest
- Town development
- Crop discovery
- Region unlock
- Sky Island unlock

Detailed recipe-shop design is postponed for later.

---

# 72. Processing Chains

Processing should support multi-step chains.

Examples:

Wheat
→ Flour
→ Dough
→ Bread

Tomato
→ Tomato Puree
→ Tomato Sauce
→ Bottled Sauce

Frost Flower
→ Frost Crystal
→ Frost Essence

Multi-step chains are important because they justify:

- Multiple processors
- Warehouses
- Conveyor routing
- Splitters
- Power expansion

---

# 73. Initial Processing Recipe Set

Initial target:
- At least 20 recipes
- Preferably around 25–26

Current draft set:

1. Wheat ×2 → Flour ×1
2. Flour ×2 → Dough ×1
3. Dough ×1 → Bread ×1
4. Sugar Beet ×2 → Sugar ×1
5. Strawberry ×3 + Sugar ×1 → Strawberry Jam ×1
6. Blueberry ×3 + Sugar ×1 → Blueberry Jam ×1
7. Watermelon ×1 → Watermelon Juice ×2
8. Strawberry/Blueberry ×2 + Sugar ×1 → Fruit Syrup ×1
9. Fruit Syrup ×2 + Gold-quality Fruit ×1 → Premium Jam ×1
10. Tomato ×3 → Tomato Puree ×1
11. Tomato Puree ×2 → Tomato Sauce ×1
12. Tomato Sauce ×2 → Bottled Sauce ×1
13. Potato ×3 → Potato Starch ×1
14. Potato ×2 → Potato Snack ×1
15. Sweet Potato ×2 → Dried Sweet Potato ×1
16. Dried Sweet Potato ×2 + Sugar ×1 → Sweet Potato Dessert ×1
17. Corn ×2 → Corn Flour ×1
18. Corn Flour ×2 + Dough ×1 → Corn Bread ×1
19. Cabbage ×2 → Pickled Cabbage ×1
20. Pickled Cabbage ×1 + Eggplant ×1 + Radish ×1 → Vegetable Pickle Set ×1
21. Pumpkin ×1 → Pumpkin Puree ×2
22. Pumpkin Puree ×2 + Dough ×1 + Sugar ×1 → Pumpkin Pie ×1
23. Golden Pumpkin ×1 → Golden Concentrate ×1
24. Golden Concentrate ×1 + Dough ×1 + Sugar ×2 → Golden Dessert ×1
25. Frost Flower ×2 → Frost Crystal ×1
26. Frost Crystal ×2 → Frost Essence ×1

Detailed pricing, processing speed, and exact quality handling will be balanced later.

---

# 74. Processing Quality Handling

Do not allow quality management to explode into excessive item variants.

General direction:

- Ingredient quality should influence final product value or final product quality
- Exact formula to be decided later
- Avoid making logistics unnecessarily complicated

Detailed quality formula is postponed.

---

# 75. Power System

Automation facilities consume power.

Do not require individual wires/poles.

Each unlocked region has its own independent regional power grid.

Example:

Starting Farm:
Generation 120
Consumption 95

Riverside:
Generation 40
Consumption 38

Mountain:
Generation 200
Consumption 150

Each region must build its own generators.

---

# 76. Power Shortage

For the initial system:

If regional consumption > regional generation:

→ All automation in that region stops

This includes conveyors.

When power becomes sufficient again:

→ Systems resume automatically

No restart button required.

Later advanced feature:
- Power priority settings

Example:
1. Sprinklers
2. Auto harvesters
3. Processors
4. Shipping

---

# 77. Generators

Possible progression:

- Small Generator
- Medium Generator
- Large Generator

Later power options:

- Biomass
- Solar
- Wind
- Advanced power

Biomass is especially important for the farming theme.

Possible inputs:

- Weeds
- Crop scraps
- Processing byproducts

→ Biofuel
→ Electricity

Exact fuel design later.

---

# 78. Inter-Region Logistics

Within one region:

- Conveyor
- Warehouse
- Processor

Between regions:

- Cargo Teleporter

Overall management:

- Logistics Pad

This separation is intentional.

---

# 79. Logistics Pad

A logistics pad allows the player to inspect all owned regions.

Possible information:

Starting Farm:
- Warehouse usage
- Power generation/consumption
- Teleport queue

Riverside:
- Warehouse usage
- Power
- Teleport status

Mountain:
- Warehouse usage
- Power
- Teleport queue

Initial pad:
- View information

Later upgrades:
- Remote filter settings
- Remote logistics control

---

# 80. Cargo Teleporter

Used to move items between separated regions.

Rules:

- Sending and receiving regions both need teleport facilities
- Teleporter has throughput limits
- Teleporter consumes power
- Overloaded teleporter creates a queue
- Item filters can be configured

Example:

Mountain → Starting Farm

Allowed:
- Iron Ore
- Stone
- Rare Mineral

Starting Farm → Mountain

Allowed:
- Food
- Processed materials
- Conveyor parts

Exact throughput later.

---

# 81. Cargo Teleporter Progression

Early teleporter:
- 1-to-1 connection

Advanced teleporter:
- More flexible regional connections
- Higher throughput
- Better filters

This should prevent instant global inventory behavior.

---

# 82. Economy Core

Money should primarily be reinvested into:

- Seeds
- Tool upgrades
- Buildings
- Warehouses
- Conveyors
- Processors
- Generators
- Automation facilities
- Greenhouses
- Region expansion
- Later decoration

Economic progression:

Farm
→ Sell
→ Buy automation
→ Produce more
→ Process
→ Store
→ Sell strategically
→ Expand

---

# 83. Standard Shipping Bin

A normal shipping bin exists on the farm.

Rules:

- Player puts items in during the day
- Items can be taken back before the day ends
- At day end, contents are sold at stable base prices
- Quality multipliers apply

Standard shipping is the safe, stable selling method.

---

# 84. Sky Island Market

Late-game market unlocked through a project/quest.

It is not simply a higher-paying shop.

Core idea:

- Production ability
- Storage ability
- Selling timing

all matter.

Sky market prices fluctuate.

---

# 85. Sky Market Prices

Prices update once per day.

Day begins
→ Today's prices are determined
→ Prices remain fixed for that day
→ New prices next day

No intraday stock-style fluctuations.

No next-day price forecast.

---

# 86. Market Volatility

Different item types can have different volatility.

General crops:
- More stable

Processed goods:
- More volatile

Special crops:
- Highly volatile

Example concept:

Carrot:
- Relatively stable

Golden Pumpkin:
- May move dramatically

---

# 87. Market Categories

Market movement should not be purely random per item.

Possible categories:

- Vegetables
- Fruits
- Grains
- Processed goods
- Special crops

Example daily/temporary trends:

- Vegetable demand rising
- Grain oversupply
- Processed-goods boom

---

# 88. Market Events

Occasional events:

Sky Food Festival:
- Fruit/vegetable prices rise

Grain Harvest Boom:
- Grain prices fall

Luxury Food Trend:
- Processed goods rise

Events should not happen too frequently.

---

# 89. Sky Island Unlock

Possible project:

Restore old airship station

Possible requirements:

- Money
- Wood
- Metal
- Specific processed goods

Completion:
→ Airship available
→ Sky Island accessible
→ Sky Market unlocked

Exact requirements later.

---

# 90. Early Sky Market Use

Initially, player must physically travel:

Farm
→ Main Plaza
→ Airship
→ Sky Island
→ Market

Do not give remote selling immediately.

---

# 91. Remote Market Price Checking

Later unlock:

Market Terminal

Installed at home or farm.

Allows:
- Check current Sky Market prices remotely

Initially:
- View only
- Cannot sell remotely yet

---

# 92. Remote Shipping

Later unlock:

Sky Market Shipping Box

Player places goods inside and sends them remotely.

Possible fee:

- Direct Sky Island sale: 100%
- Remote shipping: ~95%

Exact fee later.

---

# 93. Automatic Selling

Very late automation.

Example:

Tomato:
- Minimum sell price: 55G
- Maximum amount: 500
- Auto-sell: ON

If current price < 55G:
→ Hold

If price ≥ 55G:
→ Sell automatically

This is advanced late-game automation.

---

# 94. Time System

Day starts at:

- 07:00

One active day lasts about:

- 15 real minutes

One minute before forced day end:
- Show warning

Time should stop while:

- Shop UI is open
- Building mode is open
- Move mode is open
- Demolition mode is open

Time does NOT stop while:
- Inventory is open

---

# 95. Day End

Day ends when:

- 15 active real-time minutes pass
- Player chooses to end the day at home

When 14 minutes of active day time have passed:

- Warn player that 1 minute remains

Paused-time situations do not consume this countdown.

---

# 96. Forced Return

If the 15-minute active day ends:

- No penalty
- No money loss
- No item loss
- Day simply ends

Then:
- Night processing
- Next day begins at 07:00
- Player wakes at home

---

# 97. Overnight Production

After day end, factory systems process 5 hours worth of production.

During overnight production, all relevant automation may operate:

- Generators
- Conveyors
- Processors
- Warehouses
- Cargo teleporters
- Automatic farm facilities

If blocked:

- No raw material → line stops
- Not enough power → regional automation stops
- Output/storage full → that production path stops
- Items never disappear

---

# 98. Overnight Production Summary

Next morning, show a compact summary.

Example:

Overnight Production

Flour +24
Bread +10
Tomato Sauce +17

Keep it concise.

---

# 99. Sale Income Summary

When player ends the day manually or is forcibly returned home:

Show sale income summary only.

Example:

Today's Sales

Standard Shipping +2,400G
Sky Market +3,100G

Total +5,500G

Do not mix detailed production info into this summary.

---

# 100. Daily Weather Application

At 07:00:

- Today's weather applies
- If rainy, all outdoor tilled soil starts the day watered

No mid-day weather switching for initial design.

---

# 101. Shops

Base stock:

- Seeds: unlimited
- Fertilizer: unlimited
- Facilities/equipment: unlimited
- Special/rare items: generally no quantity cap

One rotating daily special item.

Examples:

- Discount fertilizer bundle
- Discount conveyor bundle
- Building-material bundle
- Seasonal deal

The special item is limited by day, not by quantity.

---

# 102. Save System

Recommended final behavior:

At day transition:

Day-end processing
→ Next day 07:00
→ Auto-save

Also support manual save.

Manual save:
- Save current state
- Loading manual save resumes from saved position/state

Day transitions:
- Always start at home at 07:00

---

# 103. Natural Resource Regrowth

Small resources may regenerate slowly.

Possible daily low-chance regrowth:

- Weeds
- Branches
- Small rocks

Season changes may spawn slightly more.

Do NOT spawn on:

- Buildings
- Conveyors
- Active fields
- Occupied production areas

Large rocks/stumps should not automatically respawn.

---

# 104. Mature Crop Persistence

Normal mature crops do not rot simply because they were not harvested.

They remain mature until harvested.

Exception:
- Special rules such as Golden Pumpkin overgrowth/rot

---

# 105. Item Safety Rule

Items should never be silently deleted because of:

- Full inventory
- Full warehouse
- Blocked conveyor
- Facility demolition
- Power shortage

If an action cannot safely preserve items:
- Block the action
- Keep items where they are
- Show a clear message

---

# 106. Facility Move/Demolition State

Move mode:
- Facility retains internal items and state

Demolition:
- Return facility materials/items
- Return internal items to player inventory
- If inventory lacks space, block demolition

Conveyor demolition:
- Return conveyor item
- If an item is sitting on the conveyor, safely return it
- If no inventory space, block demolition

---

# 107. Core Design Rules

1. Farming, building, and factory play should remain roughly equally important.
2. Automation removes repetition, not decision-making.
3. Automation should be visible and physically represented.
4. Logistics and storage matter.
5. Regions offer advantages, not restrictions.
6. Do not use rigid farm/factory level numbers as the main progression system.
7. Region expansion should reflect real player development.
8. Power should be regional, not globally shared.
9. Internal-region logistics use conveyors.
10. Inter-region logistics use cargo teleporters.
11. Storage is physical and limited.
12. Items never disappear because a system is blocked.
13. Building experimentation should not be harshly punished.
14. Exact numbers for throughput, prices, power, and costs should remain easy to rebalance.
15. Important long-term systems should be modular rather than concentrated in one giant script.

---

# 108. Visual Direction

Overall mood:

- Warm
- Comfortable
- Rounded
- Cute 2D farming game
- Soft colors
- Avoid harsh/default-development visuals
- Warm greens, beige, light brown, wood tones
- UI should feel soft and natural
- Font should be readable and fit the farming mood

Pixel art is fine, but shapes and palette should remain soft rather than rigid.

---

# 109. Technical Structure Principle

Keep systems modular.

Conceptual separation should include areas such as:

- Player
- Farming
- Crop
- Inventory
- Item
- Time
- Weather
- Economy
- Shop
- Building
- Conveyor
- Processing
- Storage
- Power
- Automation
- Region
- Logistics
- Market
- Save
- World

Exact file names and folder structure may be chosen based on the actual project.

Avoid one giant script containing unrelated systems.

---

# 110. Features Intentionally Postponed for Later Design

These are intentionally not fully specified yet:

- Detailed Chef / Recipe Shop interaction
- Exact processed-item quality formula
- Detailed NPC relationship system
- Detailed quest structure
- Collection / encyclopedia system
- Decoration/furniture system
- Fine-grained building aesthetics
- Exact facility throughput
- Exact conveyor speed
- Exact power numbers
- Exact warehouse capacities
- Exact upgrade costs
- Exact region unlock costs
- Exact market volatility formulas
- Detailed Sky Market event list
- Advanced power priority system
- Detailed greenhouse construction requirements
- Exact Golden Pumpkin unlock condition
- Exact Frost Flower unlock condition
- Fine economic balancing
- Additional future regions
- Additional future crops/recipes
- Town growth details

---

# 111. Claude Code Working Rule

This document is the primary game-design reference.

When working with Claude Code:

1. Read this file first.
2. Inspect the current project before changing code.
3. Work on only the requested system or milestone.
4. Do not attempt to implement the entire design at once.
5. Preserve existing working systems whenever possible.
6. If implementation conflicts with this plan, prefer the design intent but avoid unnecessary rewrites.
7. Keep data-driven values easy to balance later.
8. Keep systems modular and extensible.
9. Avoid hardcoding balance values when they are likely to change.
10. Build playable milestones step by step.

Suggested prompt style:

"Read BUILD_FARM_PLAN.md and inspect the current project first.
For this task, work only on [SYSTEM NAME].
Preserve unrelated working systems and structure the implementation so later systems can extend it."
