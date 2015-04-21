%%%-------------------------------------------------------------------
%%% @author Rafal Slota
%%% @copyright (C): 2013 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module implements {@link gen_server_behaviour} callbacks. <br/>
%%% DAO API functions are implemented in DAO sub-modules like: {@link dao_groups}, {@link dao_providers}. <br/>
%%% All DAO API functions Should not be used directly, use {@link dao_worker:handle_call/3} instead.
%%% Module :: atom() is module suffix (prefix is 'dao_'), MethodName :: atom() is the method name
%%% and ListOfArgs :: [term()] is list of argument for the method. <br/>
%%% See {@link dao_worker:handle_call/3} for more details.
%%% @end
%%%-------------------------------------------------------------------
-module(dao_worker).
-behaviour(gen_server).
-author("Rafal Slota").

-include_lib("ctool/include/logging.hrl").
-include_lib("dao/include/common.hrl").
-include_lib("dao/include/couch_db.hrl").
-include("dao/dao_external.hrl").
-include("dao/dao_types.hrl").
-include("registered_names.hrl").

-import(dao_helper, [name/1]).

-ifdef(TEST).
-compile([export_all]).
-endif.

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-record(state, {}).

%% API
-export([start_link/0]).

%%%===================================================================
%%% Start gen_server api
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% @end
%%--------------------------------------------------------------------
-spec start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}.
start_link() ->
    gen_server:start_link({local, ?Dao}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server.
%% @end
%%--------------------------------------------------------------------
-spec init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore.
init({Args, {init_status, undefined}}) ->
    ets:new(db_host_store, [named_table, public, bag, {read_concurrency, true}]),
    init({Args, {init_status, table_initialized}});
init({_Args, {init_status, table_initialized}}) -> %% Final stage of initialization. ETS table was initialized
    case application:get_env(?APP_Name, db_nodes) of
        {ok, Nodes} when is_list(Nodes) ->
            [dao_hosts:insert(Node) || Node <- Nodes, is_atom(Node)],
            catch dao_setup:setup_views(?DATABASE_DESIGN_STRUCTURE);
        _ ->
            ?warning("There are no DB hosts given in application env variable.")
    end,
    {ok, #state{}};
init({Args, {init_status, _TableInfo}}) ->
    init({Args, {init_status, table_initialized}});
init(Args) ->
    init({Args, {init_status, ets:info(db_host_store)}}).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handles call messages.
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request :: term(), From :: {pid(), Tag :: term()},
    State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}.
handle_call({ProtocolVersion, Target, Method, Args}, _From, State) when is_atom(Target), is_atom(Method), is_list(Args) ->
    put(protocol_version, ProtocolVersion), %% Some sub-modules may need it to communicate with DAO' gen_server
    Module =
        case atom_to_list(Target) of
            "utils" -> dao_worker;
            [$d, $a, $o, $_ | T] -> list_to_atom("dao_" ++ T);
            T -> list_to_atom("dao_" ++ T)
        end,
    try apply(Module, Method, Args) of
        {error, Err} ->
            ?error("Handling ~p:~p with args ~p returned error: ~p", [Module, Method, Args, Err]),
            {reply, {error, Err}, State};
        {ok, Response} -> {reply, {ok, Response}, State};
        ok -> {reply, ok, State};
        Other ->
            ?error("Handling ~p:~p with args ~p returned unknown response: ~p", [Module, Method, Args, Other]),
            {reply, {error, Other}, State}
    catch
        error:{badmatch, {ok, Record}} ->
            {reply, {error, {badrecord, Record}}, State};
        error:{badmatch, {error, Err}} ->
            {reply, {error, Err}, State};
        error:{badmatch, Reason} ->
            {reply, {error, Reason}, State};
        Type:Error ->
            ?error("Handling ~p:~p with args ~p interrupted by exception: ~p:~p ~n ~p", [Module, Method, Args, Type, Error, erlang:get_stacktrace()]),
            {reply, {error, Error}, State}
    end;
handle_call({ProtocolVersion, Method, Args}, _From, State) when is_atom(Method), is_list(Args) ->
    {reply, gen_server:call(?Dao, {ProtocolVersion, cluster, Method, Args}), State};
handle_call(_Request, _From, State) ->
    ?error("Unknown call request ~p ", [_Request]),
    {reply, {error, wrong_args}, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handles cast messages.
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}.
handle_cast(_Request, State) ->
    ?error("Unknown cast request ~p ", [_Request]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handles all non call/cast messages.
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}.
handle_info(_Info, State) ->
    ?error("Unknown info request ~p ", [_Info]),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
    State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Converts process state when code is changed.
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn :: term() | {down, term()}, State :: #state{},
    Extra :: term()) -> {ok, NewState :: #state{}} | {error, Reason :: term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
