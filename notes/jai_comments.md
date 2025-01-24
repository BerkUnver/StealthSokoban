The purpose of this file is so I can write down my critisms of Jai, then when I have enough I can submit them to Jon if they're good.

##### The pass-by-value semantics
Some stuff here makes no sense.
The documentation claims that structs or things > 8 bytes will be discretely passed by pointer when you call them. However, you can still take pointers to them. The documentation says they are probably going to get rid of this.

Apparently the "discrete passing by value" doesn't apply to #expand macros. It just makes a copy, without making a warning, and still lets you take pointers to them! (I need to verify that this is actually what is going on, I passed a struct into a for\_expansion by value and took pointers to it, but they were to a copy, and this took 2.5 hours to debug)

The context is a value for some reason, it should explicitly be a pointer, especially if changes to the context persist after a function is called.
