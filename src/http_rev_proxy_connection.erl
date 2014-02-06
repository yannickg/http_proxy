%% Copyright (c) 2014, Yannick Guay <yannick.guay@gmail.com>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(http_rev_proxy_connection).

-export([proxy_request/1]).

-record(state, {
   socket_from = undefined :: inet:socket(),
   transport_from = undefined :: module(),
   socket_to = undefined :: inet:socket(),
   transport_to = undefined :: module()
}).

proxied_server(Req) ->
   % {"www.google.com", 80, <<"www.google.com">>}.
   case cowboy_req:path(Req) of
      {<<"/websocket">>, _} -> 
         {"siptricks.com", 5062, <<"siptricks.com">>};
      {_, _} ->
         {"siptricks.com", 80, <<"siptricks.com">>}
   end.

set_socket_options(true, #state{socket_from=Socket, transport_from=Transport}) ->
   Transport:setopts(Socket, [{active, once}]);
set_socket_options(false, _) ->
   ok.

proxy_request(Req) ->
   lager:info("~16w http_rev_proxy_connection:proxy_request", [self()]),

   {Hostname, Port, Header} = proxied_server(Req),
   {ok, SocketTo} = gen_tcp:connect(Hostname, Port, [binary, {active, once}, {nodelay, true}, {reuseaddr, true}]),

   % Rewrite headers.
   Req2 = http_rev_proxy_request:new(Req),
   Req3 = http_rev_proxy_request:replace_header(<<"host">>, Header, Req2),
   {Packet, Req4} = http_rev_proxy_request:build_packet(Req3),
   gen_tcp:send(SocketTo, Packet),

   [SocketFrom, TransportFrom] = cowboy_req:get([socket, transport], Req),
   State=#state{socket_from=SocketFrom, transport_from=TransportFrom,
      socket_to=SocketTo, transport_to=gen_tcp},
   set_socket_options(http_rev_proxy_request:request_is_websocket(Req4), State),
   socket_listener(State).



socket_listener(State=#state{socket_from=SocketFrom, transport_from=TransportFrom,
      socket_to=SocketTo, transport_to=TransportTo}) ->
   lager:info("~16w http_rev_proxy_handler:socket_listener", [self()]),
   receive
      {tcp, SocketTo, Data} ->
         inet:setopts(SocketTo, [{active, once}]),
         TransportFrom:send(SocketFrom, Data),
         socket_listener(State);
      {tcp_closed, SocketTo} ->
         TransportFrom:close(SocketFrom),
         lager:warning("~16w tcp_closed", [self()]);
      {tcp_error, SocketTo, _Reason} ->
         TransportFrom:close(SocketFrom),
         lager:warning("~16w tcp_error", [self()]);
      {tcp, SocketFrom, Data} ->
         inet:setopts(SocketFrom, [{active, once}]),
         TransportTo:send(SocketTo, Data),
         socket_listener(State);
      {tcp_closed, SocketFrom} ->
         TransportTo:close(SocketTo),
         lager:warning("~16w tcp_closed", [self()]);
      {tcp_error, SocketFrom, _Reason} ->
         TransportTo:close(SocketTo),
         lager:warning("~16w tcp_error", [self()])
   end.