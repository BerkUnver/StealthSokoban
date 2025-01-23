Level :: struct {
    blocks: Fixed_Array(32, Block);

    player_position: Vector3i;
    flags: enum {PULLING :: 1;};

    collision: Collision;
}


Collision :: struct {
    position: Vector3i;
    size: Vector3i;

    filled: [] *Block;
    // @TODO This is stored x-major, then z, then y.
    // This makes sense from the perspective of wanting to be 
    // able to type levels directly into code for this initial
    // development period, but may make less sense later.
    // Consider coming back to this.
    // @TODO Implement a bit array for better cache coherency.
}


Block :: struct {
    position: Vector3i;
    size: Vector3i;
    filled: [] bool;
    color: Vector4;
    moveable: bool;
    // @TODO Pregenerate the mesh for the block and upload it to the GPU
    // @TODO Make a bit array data structure for better cache coherency
}


level_init :: (using level: *Level, level_arena: *Memory_Arena) {
    T :: true;
    F :: false;
     
    block_0 := append(*blocks);
    block_0.* = .{
        position = .{-3, -1, -2},
        size = .{6, 1, 4},
        filled = .[
            T, T, T, T, T, T,
            T, T, T, T, T, T,
            T, T, T, T, T, T,
            T, T, T, T, T, T
        ],
        color = .{1, 0, 0, 1},
        moveable = false
    };
    
    block_1 := append(*blocks);
    block_1.* = .{
        position = .{-3, 0, -2},
        size = .{6, 1, 4},
        filled = .[
            F, F, F, F, F, T,
            T, F, F, F, F, F, 
            F, F, F, F, F, F,
            T, T, T, T, T, T
        ],
        color = .{1, 143.0/255.0, 0, 1},
        moveable = false
    };

    block_2 := append(*blocks);
    block_2.* = .{
        position = .{-1, 0, -2},
        size = .{3, 1, 2},
        filled = .[
            T, T, T,
            T, F, T
        ],
        color = .{0, 0, 1, 1},
        moveable = true
    };
    /* 
    block_3 := append(*blocks);
    block_3.* = .{
        position = .{-1, 0, 0},
        size = .{3, 1, 1},
        filled = .[T, T, T],
        color = .{0, 0.5, 0, 1},
        moveable = true
    };
    */
    
    //
    // Generate your collision information based on the blocks
    //
    

    // This generates the collision information based on the bounding box of what's in the level.
    // We may want to bring this back, or possibly have bounding box widgets in the level editor.

    /*
    start: Vector3i;
    end: Vector3i;
    for blocks {
        if it_index == 0 {
            start = it.position;
            end = it.position + it.size;
        } else {
            if it.position.x < start.x start.x = it.position.x;
            if it.position.y < start.y start.y = it.position.y;
            if it.position.z < start.z start.z = it.position.z;
            
            it_end := it.position + it.size;
            if it_end.x > end.x end.x = it_end.x;
            if it_end.y > end.y end.y = it_end.y;
            if it_end.z > end.z end.z = it_end.z;
        }
    }

    size := end - start;
    collision_array_size := size.x * size.y * size.z;
    success, collision_memory := arena_alloc_array(*level_arena, collision_array_size, *Block);
    assert(success);
    */
    
    
    // @Temporary
    START :: Vector3i.{-10, -10, -10};
    END :: Vector3i.{10, 10, 10};
    size := END - START;
    collision_array_size := size.x * size.y * size.z;

    for blocks {
        assert(it.position.x >= START.x
            && it.position.y >= START.y
            && it.position.z >= START.z);
        assert(it.position.x + it.size.x < END.x
            && it.position.y + it.size.y < END.y
            && it.position.z + it.size.z < END.z);
    }
    success, collision_memory := arena_alloc_array(level_arena, collision_array_size, *Block);
    assert(success);

    collision = .{
        position = START,
        size = size,
        filled = collision_memory
    };

    for * blocks {
        assert(add_block_to_collision(*collision, it));
    }

    player_position = .{0, 0, -1};
}


level_update :: (using level: *Level, event: Input_Event) { 
    if event.input == #char " " {
        if event.down flags |= .PULLING;
        else          flags &= ~.PULLING;
    } else {
        if !event.down return;
        push_direction: Vector3i;
        if event.input == {
            case xx #char "W"; push_direction.z += 1;
            case xx #char "A"; push_direction.x -= 1;
            case xx #char "S"; push_direction.z -= 1;
            case xx #char "D"; push_direction.x += 1;
            case xx #char "Q"; push_direction.y += 1;
            case xx #char "E"; push_direction.y -= 1;
            case; return;

        }
        
        new_player_position := player_position + push_direction;

        
        // This code took a while to put together and likely is only going to get more complex.

        // When the player moves, either the entire move needs to succeed at once or fail at once.
        // When the player pushes or pulls a block, a lot about the game state needs to change.
        // If we're trying to update the game state and we find out that the move the player is
        // trying to make is illegal, then we need to undo all the changes we made to the game
        // state while determining if that move is legal.

        // Right now, I am just removing all the blocks from the collision map, updating them,
        // re-adding them to the collision map, and undoing all of that if it turns out one of
        // the blocks is overlapping with something.
        
        // If we are not _very_ careful, this could get messy really quickly.
        // Possibly consider investigating an alternate strategy that does not touch the core
        // game state until we _know_ we can make a move, then do the update.

        //          -berk, 22 - 1 - 2025.

        // @TODO Add pulling blocks next to you, not just in the opposite direction of where
        // you are moving (I'm pretty sure we want this)

        moving_blocks: Fixed_Array(2, *Block);
        
        pushed_in_bounds, pushed_block := get_block(collision, new_player_position);
        if !pushed_in_bounds return;

        if pushed_block {
            if !pushed_block.moveable return;
            assert(append(*moving_blocks, pushed_block));
        }

        if flags & .PULLING {
            pulled_in_bounds, pulled_block := get_block(collision, player_position - push_direction);
            if pulled_in_bounds && pulled_block && pulled_block.moveable && !contains(moving_blocks, pulled_block) {
                assert(append(*moving_blocks, pulled_block));
            }
        }
        
        for moving_blocks {
            remove_block_from_collision(*collision, it);
        }

        move_failed := false;
        for moving_blocks {
            it.position += push_direction;
            if !add_block_to_collision(*collision, it) {

                // Undo everything we just tried to do
                it.position -= push_direction;
                for #v2 < 0..it_index-1 {
                    block := moving_blocks[it];
                    remove_block_from_collision(*collision, block);
                    block.position -= push_direction;
                }

                for moving_blocks {
                    assert(add_block_to_collision(*collision, it));
                }

                move_failed = true;
                break;
            }
        }

        if !move_failed player_position = new_player_position;
    }
}
