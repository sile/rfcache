-module(rfcache).
-behaivour(gen_server).

-export([start_link/3, get/2, get/3, erase/2, erase/3, clear/1, clear/2, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
         
-record(state, {name, nodes, retrieve_fn}).

-define(TRY(Exp), try 
                      Exp
                  catch _:Reason ->
                          {error, Reason}
                  end).

%%%%%%%%%%%%%%
%%% Client API
start_link(Name, Nodes, RetrieveFn) ->
    gen_server:start_link({local, Name}, ?MODULE, {Name,Nodes,RetrieveFn}, []).

get(Server, Key) ->
    get(Server, Key, 5000).

get(Server, Key, Timeout) ->
    case ets:lookup(Server, Key) of
        [{_, Value}] -> {ok, Value};
        _ -> ?TRY(gen_server:call(Server, {retrieve, Key}, Timeout))
    end.

erase(Server, Key) ->
    erase(Server, Key, 5000).

erase(Server, Key, Timeout) ->
    ?TRY(gen_server:call(Server, {erase,Key}, Timeout)).

clear(Server) ->
    clear(Server, 5000).
    
clear(Server, Timeout) ->
    gen_server:call(Server, clear, Timeout).
    
stop(Server) ->
    gen_server:cast(Server, stop).


%%%%%%%%%%%%%%%%%%%%%%%
%%% gen_server Callback
init({Name,Nodes,RetrieveFn}) ->
    net_kernel:monitor_nodes(true),
    ets:new(Name, [named_table, set, {read_concurrency,true}]),
    {ok, #state{name=Name,
                nodes=start_sync_servers(Name, Nodes, RetrieveFn),
                retrieve_fn=RetrieveFn}}.

handle_call({retrieve, Key}, _From, #state{retrieve_fn=RetFn, name=Name}=State) ->
    Response = case ?TRY(RetFn(Key)) of
                   {ok, Value} -> ets:insert(Name, {Key, Value}),
                                  {ok, Value};
                   Other -> Other
               end,
    {reply, Response, State};

handle_call({erase, Key}, _From, #state{name=Name, nodes=Nodes}=State) ->
    ets:delete(Name, Key),
    case erase_entry_on_all_node(Key, Name, Nodes) of
        [] -> {reply, ok, State};
        FailedNodes ->
            {reply, {error, {failed, FailedNodes}}, State}
    end;

handle_call(clear, _From, #state{name=Name, nodes=Nodes}=State) ->
    ets:delete(Name),
    case clear_entry_on_all_node(Name, Nodes) of
        [] -> {reply, ok, State};
        FailedNodes ->
            {reply, {error, {failed, FailedNodes}}, State}
    end;

handle_call(clear_impl, _From, State) ->
    ets:delete(State#state.name),
    {reply, true, State};

handle_call({erase_impl, Key}, _From, State) ->
    ets:delete(State#state.name, Key),
    {reply, true, State};
    
handle_call(_, _, State) ->
    {stop, unhandled_message, State}.

handle_cast({merger_nodes,Nodes1}, #state{nodes=Nodes2}=State) ->
    {noreply, State#state{nodes=filter_nodes(Nodes1++Nodes2)}};

handle_cast({remove_node,Node}, #state{nodes=Nodes}=State) ->
    {noreply, State#state{nodes=lists:delete(Node, Nodes)}}; 

handle_cast(stop, #state{name=Name, nodes=Nodes}=State) ->
    ets:delete(Name),
    broadcast(Name, Nodes, {remove_node,self()}),
    {stop, normal, State};

handle_cast(_, State) ->
    {stop, unhandled_message, State}.

handle_info({nodedown,Node}, #state{nodes=Nodes}=State) ->
    {noreply, State#state{nodes=lists:delete(Node,Nodes)}};
 
handle_info(_Info,State) -> 
    {noreply, State}.

terminate(_Reason, #state{name=Name, nodes=Nodes}) -> 
    broadcast(Name, Nodes, {remove_node,self()}),
    ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.


%%%%%%%%%%%%%%%%%%%%%
%%% Internal Function
filter_nodes(Nodes) ->
    lists:filter(fun is_valid_node/1, lists:usort(Nodes)).

is_valid_node(Node) ->
    case node() of
        Node -> false;
        _ -> case net_adm:ping(Node) of
                 pong -> true;
                 _ -> false
             end
    end.

broadcast(Name, Nodes, Message) ->
    lists:foreach(fun (Node) -> gen_server:cast({Name,Node}, Message) end, Nodes).

start_sync_servers(Name, Nodes, RetrieveFn) ->
    ValidNodes = filter_nodes(Nodes),
    StartNodes = 
        lists:filter(
          fun (Node) ->
                  case rpc:call(Node, ?MODULE, start_link, [Name,[node()|ValidNodes],RetrieveFn]) of
                      {badrpc, _} -> false;
                      {ok, _} -> true;
                                 {error, {already_started,_}} -> 
                          gen_server:cast({Name,Node}, {merger_nodes, [node()|ValidNodes]}),
                          true;
                      _ -> false
                  end
          end,
          ValidNodes),
    StartNodes.

call_on_all_node(Name, Nodes, Message) ->
    lists:filter(
      fun (Node) ->
              Succeeded =
                  try
                      gen_server:call({Name, Node}, Message) 
                  catch 
                      _:_ ->  
                          false
                  end,
              not Succeeded
      end,
      Nodes).    

erase_entry_on_all_node(Key, Name, Nodes) ->
    call_on_all_node(Name, Nodes, {erase_impl,Key}).

clear_entry_on_all_node(Name, Nodes) ->
    call_on_all_node(Name, Nodes, clear_impl).
