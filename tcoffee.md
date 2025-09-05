# Compilation

We're using sub-optimal flags to avoid problems.

## Working flags

```text
CFLAGS=-g -O0 -fno-strict-aliasing -Wall -Wno-write-strings -std=c++98
```

## Known issues

Errors with -O2:

```text
CFLAGS=-O2 -DNDEBUG -fno-strict-aliasing -Wall -Wno-write-strings -std=c++98
```