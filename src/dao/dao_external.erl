%%%-------------------------------------------------------------------
%%% @author Tomasz Lichon
%%% @copyright (C): 2014 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module provides application specific functions needed by dao
%%% library to work with database
%%% @end
%%%-------------------------------------------------------------------
-module(dao_external).
-author("Tomasz Lichon").

-behaviour(dao_external_behaviour).

-include_lib("ctool/include/logging.hrl").
-include_lib("dao/dao_external.hrl").
-include("registered_names.hrl").

-define(synch_call_timeout, 1000).

%% API
-export([set_db/1, get_db/0, record_info/1, is_valid_record/1, sequential_synch_call/3, view_def_location/0]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Sets current working database name
%% @end
%%--------------------------------------------------------------------
-spec set_db(DbName :: string()) -> ok.
set_db(DbName) ->
    put(current_db, DbName).

%%--------------------------------------------------------------------
%% @doc Gets current working database name
%% @end
%%--------------------------------------------------------------------
-spec get_db() -> DbName :: string().
get_db() ->
    case get(current_db) of
        DbName when is_list(DbName) ->
            DbName;
        _ ->
            ?DEFAULT_DB
    end.

%%--------------------------------------------------------------------
%% @doc Checks if given record/record name is supported and existing record
%% @end
%%--------------------------------------------------------------------
-spec is_valid_record(Record :: atom() | string() | tuple()) -> boolean().
is_valid_record(Record) when is_list(Record) ->
    is_valid_record(list_to_atom(Record));
is_valid_record(Record) when is_atom(Record) ->
    case ?dao_record_info(Record) of
        {_Size, _Fields, _} ->
            true;    %% When checking only name of record, we omit size check
        _ -> false
    end;
is_valid_record(Record) when not is_tuple(Record); not is_atom(element(1, Record)) ->
    false;
is_valid_record(Record) ->
    case ?dao_record_info(element(1, Record)) of
        {Size, Fields, _} when is_list(Fields), tuple_size(Record) =:= Size ->
            true;
        _ -> false
    end.

%%--------------------------------------------------------------------
%% @doc Returns info about given record
%% @end
%%--------------------------------------------------------------------
-spec record_info(Record :: atom() | string() | tuple()) -> {Size, Fields, DefaultInstance} when
    Size :: integer(),
    Fields :: list(),
    DefaultInstance :: tuple().
record_info(Record) ->
    ?dao_record_info(Record).

%%--------------------------------------------------------------------
%% @doc Synchronizes sequentially multiple calls to given dao function.
%%--------------------------------------------------------------------
-spec sequential_synch_call(Module :: atom(), Function :: atom(), Args :: list()) -> Result :: term().
sequential_synch_call(Module, Function, Args) ->
    try
        gen_server:call(?Dao, {get(protocol_version), Module, Function, Args}, ?synch_call_timeout)
    catch
        _Type:Error ->
            ?error("Sequential synch call ~p:~p(~p) error: ~p", [Module, Function, Args, Error]),
            {error, Error}
    end.

%%--------------------------------------------------------------------
%% @doc Returns location of database views definitions
%%--------------------------------------------------------------------
-spec view_def_location() -> Location :: string().
view_def_location() ->
    {ok, Location} = application:get_env(?APP_Name, view_def_location),
    Location.