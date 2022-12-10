programming language endgame.

## Example

```endron
@std;$struct,{|import;"std"}
@print;$fn,:std.print

/// This function does something
@do_something;{$fn;{
    @x;$num
    @y;$num
    @z;$num
    @s;$str
},$num},{
    !:^print;x,y,z,s

    // blocks implicitly return the result of the last meta operation
    #+;x,y,z
}

@Storage;$type,{$struct;{
    @stored;$num
    @capacity;$num
}}

@main;{$fn;{},$void},{
    @storage;$:^Storage,{
        ~stored;-10.0
        ~capacity;100
    }

    @result;$num
    ~result;{!:^do_something;:*storage.stored,:*storage.capacity,100,"Hello, world!"}

    !:^print;:storage.stored
    !:^print;:storage.capacity

    ?{#=;:*result,100};{
        !:^print;"Result is 100"
    },{
        !:^print;"Result is not 100"
    }

    ?{#>;:*result,100};{
        !:^print;"Result is greater than 100"
    },{
        !:^print;"Result is not greater than 100"
    }
}
```
