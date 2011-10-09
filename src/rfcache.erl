-module(rfcache).
-behaivour(gen_server).

-export([start_link/2, get/2, get/3, put/3, stop/1,
         add_node/2, sync_nodes/1]).
-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-record(state, {name,
                nodes}).
        
%% TODO: 他nodeのダウンを検出
start_link(Name, Nodes) ->
    gen_server:start_link({local, Name}, ?MODULE, {Name,Nodes}, []).

get(Server, Key) ->
    gen_server:call(Server, {get,Key}).

get(Server, Key, Timeout) ->
    gen_server:call(Server, {get,Key}, Timeout).

put(Server, Key, Value) ->
    gen_server:cast(Server, {put,Key,Value}).
    
stop(Server) ->
    gen_server:cast(Server,stop).

add_node(Server,Node) ->
    gen_server:cast(Server, {add_node,Node}),
    sync_nodes(Server).

sync_nodes(Server) ->
    gen_server:cast(Server, sync_nodes).


%%%%%%%%%%
broadcast_entry(State, Key, Value) ->
    #state{name=Name,nodes=Nodes} = State,
    lists:foreach(
      fun(Node) ->
              gen_server:cast({Name,Node}, {internal_put, Key, Value})
      end,
      Nodes).

is_valid_node(Node) ->
    %% TODO: timeout
    case net_adm:ping(Node) of
        pong -> true;
        _ -> false
    end.

sync_nodes_impl(Name, Nodes) ->
    lists:foreach(
      fun (Node1) ->
              lists:foreach(
                fun (Node2) ->
                        gen_server:cast({Name,Node1}, {add_node,Node2})
                end,
                Nodes)
      end,
      Nodes).

%%%%%%%%%%
init({Name,Nodes}) ->
    net_kernel:monitor_nodes(true),
    ValidNodes = lists:filter(fun is_valid_node/1, Nodes),
    sync_nodes_impl(Name,ValidNodes),
    {ok, #state{name=Name,
                nodes=ValidNodes}}.

handle_call({get,Key}, _From, State) ->
    case erlang:get(Key) of
        {ok, Value} -> {reply, {ok,Value}, State};
        _ -> {reply, {error,noexists}, State}
    end;

handle_call(_, _, State) ->
    {stop, normal, State}.

handle_cast({put,Key,Value}, State) ->
    erlang:put(Key, {ok,Value}),
    broadcast_entry(State, Key, Value),
    {noreply,State};

handle_cast({internal_put,Key,Value}, State) ->
    erlang:put(Key, {ok,Value}),
    {noreply,State};

handle_cast({add_node,Node}, State) ->
    #state{nodes=Nodes} = State,
    case {is_valid_node(Node), lists:member(Node,Nodes)} of
        {false,_} ->
            {noreply, State};
        {_,true} ->
            {noreply, State};
        _ ->
            {noreply, State#state{nodes=[Node|Nodes]}}
    end;

handle_cast(sync_nodes, State) ->
    %% TODO: 効率化
    #state{name=Name, nodes=Nodes} = State, 
    sync_nodes_impl(Name,Nodes);

handle_cast(stop, State) ->
    {stop, normal, State};

handle_cast(_, State) ->
    {stop, normal, State}.

handle_info({nodeup,Node},State) ->
    io:format("#[LOG]: nodeup ~p~n", [Node]),
    {noreply, State};

handle_info({nodedown,Node},State) ->
    io:format("#[LOG]: nodedown ~p~n", [Node]),
    #state{nodes=Nodes} = State,
    {noreply, State#state{nodes=lists:delete(Node,Nodes)}};

handle_info(Info,State) ->
    {stop,Info,State}.

terminate(Reason, State) ->
    {stop,Reason,State}.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
