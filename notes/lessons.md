Things that I am learning as I make this game

# Things that you "have to implement in order to make a game" but not actually
- Undo/redo. I succeeded on this front.
- Font stuff. If your artstyle permits, you should absolutely use bitmap fonts.
- Fullscreen. Maybe you should just support fullscreen and that's it.
- I suspect DLL hotloading is more hassle than it's worth.
- I suspect the Jonathan Blow thing of using a frame arena and a general-purpose allocator is better than using memory arenas for specific purposes. This is because your lifetimes may change throughout development, and even change in specific game modes. This includes things that get allocated once per-entity in game mode but can get reallocated in the editor if you change some aspect about them. (Block filled array, for example).
