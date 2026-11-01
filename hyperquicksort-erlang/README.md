# Hyperquicksort in Erlang

A parallel sorting algorithm: **hyperquicksort** on a hypercube of Erlang processes. A university assignment that I implemented on my own (code comments are in German).

## How it works
For a hypercube of dimension `N` the program starts `2^N` worker processes plus one master process.

1. **Distribute:** the master splits the input list evenly across the workers.
2. **Local sort:** every worker sorts its part with quicksort.
3. **Repeat `N` times (once per dimension):**
   - The leader of each group (lowest ID) picks the median of its sorted list as the pivot. The master passes it to the whole group.
   - Every worker splits its list into elements below and above the pivot.
   - Each worker swaps one half with its neighbour (ID XOR bit), and merges the half it receives with the half it kept.
4. **Collect:** the master gathers the lists in ID order. The concatenation is the sorted result.

The master synchronizes the phases (it waits until all workers report back), and workers with empty lists are handled.

## Usage
```erlang
1> c(hyqiso).
2> Cube = hyqiso:hyperQuickInit(3).          % 2^3 = 8 worker processes
3> hyqiso:hyperQuickS(Cube, [5,3,9,1,7,2,8,4,6]).
[1,2,3,4,5,6,7,8,9]
4> hyqiso:hyperQuickStop(Cube).              % terminates all processes
```
The program prints every step (pivot choice, split, swap, merge), which makes the algorithm easy to follow.

## Tests
`test.escript` compares the result with `lists:sort/1` for cube dimensions 1 to 4, including very short and empty lists:
```
erlc hyqiso.erl
escript test.escript
```

## Notes
- Needs Erlang/OTP. Tested with OTP 25.
- `-compile(export_all)` is enabled, so the compiler prints a warning.
