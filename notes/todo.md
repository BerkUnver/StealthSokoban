# Gameplay
- In-game debug camera
- A way to place the in-level camera
- Get mutual annihilations to work when enemies pass each other
- Checkpoints that save the level state up until that point
- Enemies should fall when a block pushes them to be midair
- Enemy spawner pre-warming (run n enemy ticks before starting the level)
- Z-fighting between doors and blocks
- Visibility when in doors
- Get enemies to move with blocks if they're standing on them and the block is pushed
- Get the player to die when a mutual annihilation occurs on the player position
- Nice effect for mutual annihilations
- Level entrance and exit effects
- Fix mutual annihilation effect working when an enemy walks into a cell the player is already on
- Input hinting for when we need to communicate an input to the player


# Editor
- Undo / Redo
- An actual dragging widget
- Bulk selection
- Entity instantiation popup where you type the name of the entity you want
- Level goto popup where you type the name of the level you want to go to


# Refactors
- Put sound on a separate thread
- Switch to using the Jai standard allocator
- Make a generic texture format that we can just rip into memory efficiently


# Platform
- Fullscreen
- If keys were down and the player alt-tabbed, check their state when the player
alt-tabs back.


# Website
- We need a website for the project requirement




For people in the exhibition to thoroughly understand and enjoy the demo, we need a few things.

- Saving level state with checkpoints. When you die you go back to the last checkpoint.
- Interpolation for player movement
- Better camera controls
- Level entrance and exit
- Some explanation of basic movement. Input hinting in the game?
- Some kind of reaction when you do an invalid move, like pull a block that cannot be pulled. It jiggles a little.
- Better enemy death effect (Enemies don't disappear right away, not just an orange cube).
- Fix z-fighting with doors, have a special inside of doors vfx
- MUSIC. A tastefully-chosen selection of not-well-known classical music is likely the best we can do for now.
- SFX. Walking, pushing, etc.
- Better effect for the edges of the level
- Better meshes for level items

- More introductory levels
- Playtesting!

- Pause menu with options to exit the current level, reset the demo.
- Credits screen???


Now, let's sort these by priority.

# NEED
- ~~Saving level state with checkpoints. When you die you go back to the last checkpoint. <--- DYNAMIC MEMORY ALLOCATION?~~
- ~~Level entrance and exit~~
- Pause menu with options to exit the current level, reset the demo.
- Overworld exits only activate once you have completed the corresponding level
- More introductory levels

# WE SHOULD HAVE
- Better meshes for level items
- SFX. Walking, pushing, etc.
- Playtesting!
- Interpolation for player movement
- Pulling vfx
- Some kind of reaction when you do an invalid move, like pull a block that cannot be pulled. It jiggles a little.
- Multipush
- Pulling from all directions of a block.
- MUSIC. A tastefully-chosen selection of not-well-known classical music is likely the best we can do for now.
- Some explanation of basic movement. Input hinting in the game?

# WOULD BE NICE
- Better enemy death effect (Enemies don't disappear right away, not just an orange cube).
- Better camera controls
- Better effect for the edges of the level
- Fix z-fighting with doors, have better doors vfx
