%%%-------------------------------------------------------------------
%%% @author Michal Zmuda
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This worker maintains stream which fetches recent changes
%%% from the couchbase. Only one worker is maintain active stream.
%%% todo: do not monitor global name
%%% todo: use solution introduced in VFS-1748
%%% @end
%%%-------------------------------------------------------------------
-module(changes_worker).
-author("Michal Zmuda").

-behaviour(worker_plugin_behaviour).

-include("registered_names.hrl").
-include("subscriptions/subscriptions.hrl").
-include("datastore/oz_datastore_models.hrl").
-include_lib("ctool/include/logging.hrl").

%% worker_plugin_behaviour callbacks
-export([init/1, handle/1, cleanup/0, change_callback/1]).

-define(STREAM_GLOBAL_NAME, subscriptions_current_changes_stream).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Handles changes & dispatches them to be processed.
%% @end
%%--------------------------------------------------------------------
-spec change_callback({ok, stream_ended | [datastore:doc()]}) -> ok.
change_callback({error, _, _}) ->
    ok;
change_callback({ok, end_of_stream}) ->
    gen_server:cast(?MODULE, {stop, stream_ended});
change_callback({ok, Docs}) when is_list(Docs) ->
    lists:foreach(fun(#document{seq = Seq, value = Value} = Doc) ->
        Type = element(1, Value),
        Request = {handle_change, Seq, Doc, Type},
        worker_proxy:cast(?SUBSCRIPTIONS_WORKER_NAME, Request)
    end, Docs).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================


%%--------------------------------------------------------------------
%% @doc
%% Initialises the worker and schedules stream presence checks.
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) ->
    {ok, State :: worker_host:plugin_state()} | {error, Reason :: term()}.
init(_Args) ->
    couchbase_changes:enable([subscriptions:bucket()]),
    couchbase_changes_worker:start_link(subscriptions:bucket(), <<"">>),
    schedule_stream_presence_check(),
    {ok, #{}}.


%%--------------------------------------------------------------------
%% @doc
%% Handles requests.
%% @end
%%--------------------------------------------------------------------
-spec handle(Request :: term()) -> ok | {error, Reason :: term()} | no_return().
handle(healthcheck) ->
    case global:whereis_name(?STREAM_GLOBAL_NAME) of
        undefined -> {error, stream_not_running};
        _ -> ok
    end;

handle(stream_presence_check) ->
    case global:whereis_name(?STREAM_GLOBAL_NAME) of
        undefined -> start_changes_stream();
        _ -> ?debug("Stream detected - presence check OK")
    end, ok;

handle(_Request) ->
    ?log_bad_request(_Request).

%%--------------------------------------------------------------------
%% @doc
%% Cleans up the worker.
%% @end
%%--------------------------------------------------------------------
-spec cleanup() -> ok | {error, Reason :: term()}.
cleanup() ->
    ok.


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initialize changes stream, which starts from current sequence number.
%% If claim for the global name is not valid, the stream is terminated.
%% If couchbase is not reachable, stream is not to be started.
%% @end
%%--------------------------------------------------------------------
-spec start_changes_stream() -> ok.
start_changes_stream() ->
    case get_last_seq() of
        {error, Reason} ->
            ?warning("Stream failed to start due to ~p", [Reason]);
        {ok, Start} ->
            {ok, Pid} = couchbase_changes:stream(subscriptions:bucket(), <<"">>,
                fun change_callback/1, [{since, Start}, {until, infinity}]
            ),
            case global:register_name(?STREAM_GLOBAL_NAME, Pid) of
                yes -> ?info("Stream sucessfully started & registered");
                no ->
                    ?warning("Stream conflict - name could not be registered"),
                    exit(Pid, could_not_register_name)
            end
    end,
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Get latest sequence number from cache (or from datastore if cache is empty)
%% @end
%%--------------------------------------------------------------------
-spec get_last_seq() -> {ok, non_neg_integer()}| {error, term()}.
get_last_seq() ->
    case changes_cache:newest_seq() of
        {ok, Val} -> {ok, Val};
        _ -> fetch_last_seq()
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Get latest sequence number from datastore.
%% Should be used only when provider is started.
%% @end
%%--------------------------------------------------------------------
-spec fetch_last_seq() -> {ok, non_neg_integer()}| {error, term()}.
fetch_last_seq() ->
    try
        {ok, _, LastSeq} = couchbase_driver:get_counter(
            #{bucket => subscriptions:bucket()},
            couchbase_changes:get_seq_key(<<"">>)
        ),
        {ok, LastSeq}
    catch
        E:R ->
            ?error_stacktrace("Last sequence unavailable as ~p:~p", [E, R]),
            {error, couchbeam_changes_not_working}
    end.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Schedules stream presence check. Checks are executed at regular interval
%% and they trigger stream restarts once problems are detected.
%% First check is performed immediately.
%% @end
%%--------------------------------------------------------------------

-spec schedule_stream_presence_check() -> ok.
schedule_stream_presence_check() ->
    {ok, Interval} = application:get_env(?APP_NAME,
        changes_stream_presence_check_interval_seconds),

    worker_proxy:cast({?MODULE, node()}, stream_presence_check),

    {ok, _} = timer:send_interval(timer:seconds(Interval), whereis(?MODULE),
        {timer, stream_presence_check}),
    ok.