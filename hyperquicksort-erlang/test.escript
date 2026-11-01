#!/usr/bin/env escript
%% Compares hyqiso against lists:sort/1 for several cube sizes and list lengths.
%% Run:  erlc hyqiso.erl && escript test.escript
main(_) ->
    Cases = [{1,10},{2,17},{3,5},{4,100},{3,1},{2,0}],
    lists:foreach(
      fun({N, Len}) ->
          Cube = hyqiso:hyperQuickInit(N),
          L = [rand:uniform(20) || _ <- lists:seq(1, Len)],
          S = hyqiso:hyperQuickS(Cube, L),
          io:format("RESULT dimension=~p length=~p ok=~p~n", [N, Len, S =:= lists:sort(L)]),
          hyqiso:hyperQuickStop(Cube)
      end, Cases).
