-module(http_proxy_tcp).

-behavior(gen_server).

%% public API
-export([start_link/2, tcp_open/3, tcp_message/4, tcp_close/3]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start_link(Num, Port) ->
   io:format("Entering server~n"),
   gen_server:start_link({local, ?MODULE}, ?MODULE, [Num, Port], []).

tcp_open(Pid, Socket, Transport) ->
   gen_server:call(Pid, {tcp_open, Socket, Transport}).

tcp_message(Pid, Socket, Transport, Message) ->
   gen_server:call(Pid, {tcp_message, Socket, Transport, Message}).

tcp_close(Pid, Socket, Transport) ->
   gen_server:call(Pid, {tcp_close, Socket, Transport}).

-record(state, {state_machine_pid}).

% This is called when a connection is made to the server
init([Num, Port]) ->
   io:format("Initializing server~n"),
   {ok, _} = ranch:start_listener(http_proxy, Num,
      ranch_tcp, [{port, Port}], http_proxy_protocol, []),
   ranch:set_protocol_options(http_proxy, [{http_proxy_tcp, self()}]),
   {ok, #state{state_machine_pid=dict:new()}}.

% handle_call is invoked in response to gen_server:call
handle_call({tcp_open, Socket, Transport}, _From, State) ->

   % Create State Machine
   lager:info ("instantiating state machine", []),
   {ok, Pid} = http_proxy_connection:start_link(Socket, Transport),
   lager:info("pid: ~p", [Pid]),
   {reply, ok, State#state{state_machine_pid = dict:store(Socket, Pid, State#state.state_machine_pid)}};

handle_call({tcp_message, Socket, Transport, Message}, _From, State) ->

   % Send state machine new data
   Pid = dict:fetch(Socket, State#state.state_machine_pid),
   lager:info("pid: ~p", [Pid]),
   http_proxy_connection:received_message(Pid, Message),
   % Transport:send(Socket, Data),
   {reply, ok, State};

handle_call({tcp_close, Socket, Transport}, _From, State) ->

   ok = Transport:close(Socket),
   {reply, ok, State};

handle_call(_Message, _From, Library) ->
    {reply, error, Library}.

% We get compile warnings from gen_server unless we define these
handle_cast(_Message, Library) -> {noreply, Library}.
handle_info(_Message, Library) -> {noreply, Library}.
terminate(_Reason, _Library) -> ok.
code_change(_OldVersion, Library, _Extra) -> {ok, Library}.