%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2014 ACK CYFRONET AGH
%%% This software is released under the MIT license 
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module handles requests with URL in form alias.gr.domain and
%%% performs a HTTP redirect to proper provider.
%%% @end
%%%-------------------------------------------------------------------
-module(client_redirect_handler).

-include_lib("ctool/include/logging.hrl").
-include("datastore/oz_datastore_models_def.hrl").
-include_lib("hackney/include/hackney_lib.hrl").

-export([init/3, handle/2, terminate/3]).

%%--------------------------------------------------------------------
%% @doc Cowboy handler callback, no state is required
%% @end
%%--------------------------------------------------------------------
-spec init(any(), term(), any()) -> {ok, term(), []}.
init(_Type, Req, [RequestedPort]) ->
    {ok, Req, RequestedPort}.

%%--------------------------------------------------------------------
%% @doc
%% Handles a request returning a HTTP Redirect (307 - Moved temporarily).
%% @end
%%--------------------------------------------------------------------
-spec handle(term(), term()) -> {ok, term(), term()}.
handle(Req, RequestedPort = State) ->
    try
        % Get query string from URL
        % Get the alias from URL
        {Alias, _} = cowboy_req:binding(alias, Req),

        % Find the user and his default provider
        GetUserResult = case Alias of
            <<?NO_ALIAS_UUID_PREFIX, UUID/binary>> ->
                od_user:get(UUID);
            _ ->
                case od_user:get_by_criterion({alias, Alias}) of
                    {ok, Ans} ->
                        {ok, Ans};
                    _ ->
                        od_user:get(Alias)
                end
        end,
        {ok, #document{
            key = UserId,
            value = #od_user{
                chosen_provider = ChosenProvider
            }}} = GetUserResult,
        % If default provider is not known, set it.
        RedirectionPoint =
            try
                {ok, #od_provider{
                    redirection_point = RedPoint
                }} = n_provider_logic:get(?ROOT, ChosenProvider),
                RedPoint
            catch _:_ ->
                {ok, NewChosenProv} =
                    n_provider_logic:choose_provider_for_user(UserId),
                {ok, _} = od_user:update(UserId, #{
                    chosen_provider => NewChosenProv
                }),
                {ok, #od_provider{
                    redirection_point = RedPoint2
                }} = n_provider_logic:get(?ROOT, NewChosenProv),
                RedPoint2
            end,
        #{host := Host} = url_utils:parse(RedirectionPoint),
        {Path, _} = cowboy_req:path(Req),
        QueryString = case cowboy_req:qs(Req) of
            {<<"">>, _} ->
                <<"">>;
            {QS, _} ->
                <<"?", QS/binary>>
        end,
        % Redirect to provider's hostname, but to requested port
        URL = str_utils:format_bin("https://~s:~B~s~s", [
            Host, RequestedPort, Path, QueryString
        ]),
        {ok, Req2} = cowboy_req:reply(307,
            [
                {<<"location">>, URL},
                {<<"content-type">>, <<"text/html">>}
            ], <<"">>, Req),
        {ok, Req2, State}
    catch T:M ->
        ?debug_stacktrace("Error while redirecting client - ~p:~p", [T, M]),
        {ok, Req3} = cowboy_req:reply(404, [], <<"">>, Req),
        {ok, Req3, State}
    end.

%%--------------------------------------------------------------------
%% @doc Cowboy handler callback, no cleanup needed
%% @end
%%--------------------------------------------------------------------
-spec terminate(term(), term(), term()) -> ok.
terminate(_Reason, _Req, _State) ->
    ok.
