%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2015 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module implements data_backend_behaviour and is used to synchronize
%%% the file model used in Ember application.
%%% THIS IS A PROTOTYPE AND AN EXAMPLE OF IMPLEMENTATION.
%%% @end
%%%-------------------------------------------------------------------
-module(space_data_backend).
-author("Lukasz Opiola").

-compile([export_all]).

-include_lib("ctool/include/logging.hrl").

%% API
-export([init/0]).
-export([find/2, find_all/1, find_query/2]).
-export([create_record/2, update_record/3, delete_record/2]).

%% Convenience macro to log a debug level log dumping given variable.
-define(log_debug(_Arg),
    ?alert("~s", [str_utils:format("SPACE_DATA_BACKEND: ~s: ~p", [??_Arg, _Arg])])
).


init() ->
    ?log_debug({websocket_init, g_session:get_session_id()}),
%%    {ok, _Pid} = data_backend:async_process(fun() -> async_loop() end),
    ok.


find(<<"space">>, [_SpaceId]) ->
    {error, not_iplemented}.

find_query(<<"space">>, _Data) ->
    {error, not_iplemented}.

%% Called when ember asks for all files
find_all(<<"space">>) ->
    UserId = g_session:get_user_id(),
    {ok, Res} = user_logic:get_spaces(UserId),
    Spaces = proplists:get_value(spaces, Res),
    Default = proplists:get_value(default, Res),
    Res = lists:map(
        fun(SpaceId) ->
            {ok, SpaceData} = space_logic:get_data(SpaceId, provider),
            Name = proplists:get_value(name, SpaceData),
            {ok, [{providers, Providers}]} =
                space_logic:get_providers(SpaceId, provider),
            [
                {<<"id">>, <<"s1">>},
                {<<"name">>, Name},
                {<<"isDefault">>, SpaceId =:= Default},
                {<<"providers">>, Providers}
            ]
        end, Spaces),
    {ok, Res}.


%% Called when ember asks to create a record
create_record(<<"space">>, _Data) ->
    {error, not_iplemented}.

%% Called when ember asks to update a record
update_record(<<"space">>, _Id, _Data) ->
    {error, not_iplemented}.

%% Called when ember asks to delete a record
delete_record(<<"space">>, _Id) ->
    {error, not_iplemented}.
