# qake

qake is yet another makefile generator for c(++) projects.

```lua
foo = import "foo/foo.qk"

lib "bar" {
    lang = C,
    sources = {
        "bar.c"
    }
}

exe "qake" {
    lang = C,

    sources = {
        "main.c"
    },

    libs = {
        pkg("SDL2"),
        libs.bar,
        foo.libs.foo
    }
}

-- Generate the code
return generate()
```
