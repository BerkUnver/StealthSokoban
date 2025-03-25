# Gameplay
- In-game debug camera
- A way to place the in-level camera
- Enemy despawners
- Get mutual annihilations to work when enemies pass each other
- Checkpoints that save the level state up until that point
- Enemies should fall when a block pushes them to be midair
- Enemy spawner pre-warming (run n enemy ticks before starting the level)
- Z-fighting between doors and blocks
- Visibility when in doors
- Get enemies to move with blocks if they're standing on them and the block is pushed
- Get the player to die when a mutual annihilation occurs on the player position


# Editor
- Undo / Redo
- An actual dragging widget
- Finish IMGUI (crank session for this?)
- Bulk selection


# Refactors
- Put sound on a separate thread
- Switch to using the Jai standard allocator
- Move the Editor struct into the level struct


# Platform
- Fullscreen
