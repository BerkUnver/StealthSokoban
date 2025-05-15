Things that I am learning as I make this game

# Things that you "have to implement in order to make a game" but not actually
- Undo/redo. I succeeded on this front.
- Font stuff. If your artstyle permits, you should absolutely use bitmap fonts.
- Fullscreen. Maybe you should just support fullscreen and that's it.
- I suspect DLL hotloading is more hassle than it's worth.
- I suspect the Jonathan Blow thing of using a frame arena and a general-purpose allocator is better than using memory arenas for specific purposes. This is because your lifetimes may change throughout development, and even change in specific game modes. This includes things that get allocated once per-entity in game mode but can get reallocated in the editor if you change some aspect about them. (Block filled array, for example).

# Keeping myself sane
- As I go to work at Thekla, in order to prevent myself from getting systems programmer brain disease, I have to be very careful about how I spend my time. I want to cultivate creative ideas from within myself, and the more time you spend dealing with Windows bullshit and game engine bullshit and the like, the more your brain becomes contorted to thinking in a very constrained way. I see this happen all the time with engine programmer people. I want to have weird, wonderful, and wacky ideas. The worst career thing that could happen is that I become so brain diseased that I can only think in terms of game engines. When you're a game development beginner, when you see this kind of thing you don't think it's real. How could someone become unenthusiastic about design, the core reason you are making games? But I see this ALL THE TIME. I think it is starting to rub off on me, and it NEEDS TO STOP.
- As recent events have shown, I don't think doubletiming between Thekla and another sokoban game is a sustainable thing to do. I want to do a good job at Thekla and set myself up to have very weird and wonderful ideas. I think I've kind of worked myself into a hole where I am right now. As such, I may have to stop working on this game and instead start drawing, hanging out with friends, and playing games way more. I cannot become unenthusiastic about games! I don't know if I can work on this game only kinda sometimes, as that's how things have sputtered out in the past.

# Deadlines
Because I haven't been feeling great, I kind of botched the demo, which is sad. I have two days to brush it up before I give my final presentation. What can I do?
- Fix that movement bug. I don't actually think this is _that_ high-priority.
- Add sfx. This we probably want to do.
- Make more levels. This is also important.
