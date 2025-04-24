### Prelude

Right now, I'm not a very good game designer.
I'm also interested in systems programming.
These two combined is usually not a good combination as a single person. Most people like this get a bad rap (think Youtube gamedevs, etc).
How can we safely explore both of these?

We need to have a preliminary prototype in 3.5 months for my Senior Minor Art Project. This potentially also means having a working MacOS port.

This will be my first original game that I'm trying to approach in a more methodical way, given the failure of the Society Saga and its eventual resurrection. I need to be very careful, and make sure I'm not ratholing or not confronting my own fear about parts of the game that are not going well.

### Core Game Idea
I want to make a sokoban game that heavily features 3D movement and puzzles. Blocks will be larger than 1x1, allowing them to interlock and form interesting spatial reasoning puzzles.
Another element I want to feature is a line-of-sight system as well as enemies. You should only be able to see areas where your guy has been, and you can only see enemies around where you are now. Enemies should have very simplistic and predictable movement, as they are part of the puzzles.
I have some ideas about how large blocks and line-of-sight mechanics interact, but not enough to justify them coexisting.
As such, I need to get into a position where I have a working prototype that allows me to mess around with these mechanics and see what kind of level structures naturally arise. This will better inform what else I choose to add.

### First Steps
We need to be AS RESULTS-ORIENTED AS POSSIBLE. What is the BARE MINIMUM we need to have a functioning level editor?
- Simple 3D rendering
- Moving player
- Gameplay: Player can push around blocks. Go to the next level upon getting to the end.
- Editor: Place blocks of arbitrary shapes, move and rotate objects.
- Level serialization: Can be a temporary serialization format for now.

- After this is done, we add the line of sight mechanic and enemies.

- I feel the difficult part of this project will be the movement system and making sure it always gives deterministic results. As such, this is a high-priority item.

- We can probably invite one or two people to do a very preliminary playtest at this point.

### Next Steps
- Sound. We cannot neglect sound like we have before.
- Enemy AI. How far do we want to push this?
- 3D model loading.

### Programming
One of the goals of this project is to explore systems programming while also being very pragmatic about what I choose to implement. However, the eye needs to always be on design.
Something I've noticed is that my current math knowledge is not great. I will definitely have to have perspective projection and quaternions DOWN for this project. Given the time limits, I probably shouldn't push this any further than I have to. We'll keep this as-is for now, then consider where to go next.

I've been watching Handmade Hero recently, and I want to try out some of the things Casey talks about. The thing to remember about Handmade Hero is that IT NEVER MANIFESTED IN A GAME. THERE IS NO HANDMADE HERO ON STEAM, THE PROJECT REMAINS UNFINISHED. As such, I should explore this carefully.

If I take on dependencies, they should be dependencies that are pretty easy to remove if I want to. This definitely means using OpenGL directly (Vulkan is too complex for this project). It probably also means using my own memory allocators. We can take on simple math libraries (cephes) and asset loaders (stb-image) if we need to.

MAKE SURE WE DON'T START IMPLEMENTING THE 3D GAME ENGINE CRAP WHICH IS THE REASON PEOPLE USE UNREAL.
We will try to use procedural animations for everything instead of skeletal animations. This can inform the visual aesthetic.
KEEP RENDERING VERY SIMPLE. We might be able to get away with this entire project with a quasi-immediate-mode renderer.

We are going to use Jai as our programming language. C would probably look better on my resume, but Jai has my back if things start to get funky.
We have to be VERY CAREFUL about not taking on too much of the Jai standard library, as it has a lot of interdependencies that kind of require you to buy into the whole thing.

WE SHOULD PROFILE SOON AND PROFILE OFTEN. As soon as we have stuff drawing on the screen with OpenGL, we should start profiling. For a while now, I have believed the 90s gamedev style of optimization, but haven't done much of it at all myself. This is hypocritical, and I need to learn how to do this for real.

### Finishing the Project
If things are not going well and I've spent a year working on this, I should give myself an escape hatch and be able to abandon the project. This is okay, and will be a learning experience about systems programming, etc.
If things are going mediocrely well, I can release this as freeware.
If things are going really well, we can consider a Steam release. There is too much bullshit on Steam, and I only want to put something there if I feel it is very high-quality and worth people's time.






##### 2025 - 4 - 11 Addendum: Course Correction
I'm getting too hackerman right now. It's turning into a bs game engine project. Level design was going okay early on, it's getting cut short now. I will restore it to its rightful place as I have solidified the old schedule and will get back to it. I have made some programming mistakes by following Handmade Hero BS. It would have been better to not have DLL hotloading or memory arenas (I'm fairly certain, not 100%). However, I don't want fix this now because I NEED to focus on gameplay features for the exhibition. 

Adding the level name entry bar was a mistake. I will only add editor features when I get sufficiently fed up with the thing I had before. After the new dragging widget is done, no more editor programming unless something becomes annoying and I know how I can fix it with an editor widget.

Getting gameplay features into a good-enough state for the exhibition is the PRIORITY.

For after the exhibition, I need to address the fact that this doesn't feel like _my_ game, it just feels like a game. Like I had some ideas one day and thought, "That would be cool, I guess". I need to understand how to make it my own, but I can't do that right now because the exhibition is a month away.


##### 2025 - 4 - 23 Addendum: Course Correction 2
I did asset hot-reloading which turned out to be a hackerman impulse. I think that qualifies as an editor feature. Let's define it like this. Any feature that the end user WILL NOT INTERACT WITH is by definition from the hackerman impulse. As such, those can be shunted to editor days which we can schedule as editor programming days in slots that used to be for editor programming, but now that most of that is done are for gameplay programming.
