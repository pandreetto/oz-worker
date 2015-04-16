%% ===================================================================
%% @author Tomasz Lichon
%% @copyright (C): 2014 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc Application main supervisor
%% @end
%% ===================================================================
-module(globalregistry_sup).
-author("Tomasz Lichon").

-behaviour(supervisor).

%% Includes
-include("registered_names.hrl").

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

%% start_link/0
%% ===================================================================
%% @doc Starts the supervisor
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
%% ===================================================================
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%% init/1
%% ===================================================================
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%% @end
-spec(init(Args :: term()) ->
    {ok, {SupFlags :: {RestartStrategy :: supervisor:strategy(),
        MaxR :: non_neg_integer(), MaxT :: non_neg_integer()},
        [ChildSpec :: supervisor:child_spec()]
    }} |
    ignore).
%% ===================================================================
init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 1000,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    Restart = permanent,
    Shutdown = 2000,
    Type = worker,

    Dao = {?Dao, {dao_worker, start_link, []},
        Restart, Shutdown, Type, [dao_worker]},

    OpChannel = {?OpChannel, {op_channel, start_link, []},
        Restart, Shutdown, Type, [op_channel]},

    {ok, {SupFlags, [Dao, OpChannel]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================