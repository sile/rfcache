-module(test).

-compile(export_all).

time(Count) ->
    {ok,Pid} = rfcache:start_link(test, [], fun (_) -> {ok,random:uniform()} end),
    
%    L1 = lists:seq(1, Count),
    L2 = lists:seq(1, Count*2),
    
    lists:foreach(fun(X) -> rfcache:get(test, X) end,
                  L2),

    Start = now(),

    lists:foreach(fun(X) -> rfcache:get(test, X) end,
                  L2),

    io:format("# elapsed: ~p ms~n", [timer:now_diff(now(), Start) / 1000]),
    
    rfcache:stop(Pid).

time2(Count) ->
%    L1 = lists:seq(1, Count),
    L2 = lists:seq(1, Count*2),
    
    lists:foreach(fun(X) -> put(X, X) end,
                  L2),

    Start = now(),

    lists:foreach(fun(X) -> get(X) end,
                  L2),
    io:format("# elapsed: ~p ms~n", [timer:now_diff(now(), Start) / 1000]),
    ok.

time3(Count, ProcCount) ->
    {ok,Pid} = rfcache:start_link(test, []),
    
    L1 = lists:seq(1, Count),
    L2 = lists:seq(1, Count*2),
    
    lists:foreach(fun(X) -> rfcache:put(Pid, X, X) end,
                  L1),

    From = self(),
    Start = now(),
    
    lists:foreach(
      fun (_) ->
              spawn(fun () ->
                            lists:foreach(fun(X) -> rfcache:get(Pid, X) end,
                                          L2),
                            From ! finish
                    end)
      end,
      lists:seq(1, ProcCount)),
    
    lists:foreach(
      fun (_) ->
              receive 
                  finish -> ok
              end
      end,
      lists:seq(1, ProcCount)),

    io:format("# elapsed: ~p ms~n", [timer:now_diff(now(), Start) / 1000]),
    
    rfcache:stop(Pid).


time4(Count, ProcCount) ->
    {ok,Pid} = rfcache:start_link(test, []),

    L2 = lists:seq(1, Count*2),
    
    lists:foreach(fun(X) -> 
                          rfcache:get(test, X)
                  end,
                  L2),

    From = self(),
    Start = now(),
    
    lists:foreach(
      fun (_) ->
              spawn(fun () ->
                            lists:foreach(fun(X) -> rfcache:get(test, X) end,
                                          L2),
                            From ! finish
                    end)
      end,
      lists:seq(1, ProcCount)),
    
    lists:foreach(
      fun (_) ->
              receive 
                  finish -> ok
              end
      end,
      lists:seq(1, ProcCount)),

    io:format("# elapsed: ~p ms~n", [timer:now_diff(now(), Start) / 1000]),
    
    rfcache:stop(Pid)
    .

