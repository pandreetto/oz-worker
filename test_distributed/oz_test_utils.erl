%%%-------------------------------------------------------------------
%%% @author Krzysztof Trzepla
%%% @copyright (C): 2014 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc Common functions for ct tests.
%%% @end
%%%-------------------------------------------------------------------

-module(oz_test_utils).

-include("datastore/oz_datastore_models_def.hrl").
-include_lib("ctool/include/test/test_utils.hrl").

%% API
-export([create_user/2, get_client_token/2, remove_user/2]).
-export([create_group/3, join_group/3, remove_group/2]).
-export([create_space/3, join_space/3, leave_space/3, remove_space/2]).
-export([modify_space/4, support_space/4, set_space_privileges/4]).
-export([create_provider/2, remove_provider/2]).
-export([remove_all_entities/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Creates user in onezone.
%% @end
%%--------------------------------------------------------------------
-spec create_user(Config :: term(), User :: #onedata_user{}) ->
    {ok, Id :: binary()} | {error, Reason :: term()}.
create_user(Config, User) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, user_logic, create, [User])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Creates a client token for given user.
%% @end
%%--------------------------------------------------------------------
-spec get_client_token(Config :: term(), UserId :: binary()) ->
    {ok, Id :: binary()} | {error, Reason :: term()}.
get_client_token(Config, UserId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, auth_logic, gen_token, [UserId])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Removes user from onezone.
%% @end
%%--------------------------------------------------------------------
-spec remove_user(Config :: term(), UserId :: binary()) ->
    boolean() | {error, Reason :: term()}.
remove_user(Config, UserId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, user_logic, remove, [UserId])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Creates group in onezone.
%% @end
%%--------------------------------------------------------------------
-spec create_group(Config :: term(), UserId :: binary(), Name :: binary()) ->
    {ok, Id :: binary()} | {error, Reason :: term()}.
create_group(Config, UserId, Name) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, group_logic, create, [UserId, Name, undefined])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Adds a user or group to group in onezone.
%% @end
%%--------------------------------------------------------------------
-spec join_group(Config :: term(), Member :: {user | group, Id :: binary()}, GroupId :: binary()) ->
    ok | {error, Reason :: term()}.
join_group(Config, {user, MemberId}, GroupId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, erlang, apply, [fun() ->
            {ok, Token} = token_logic:create(
                #client{type = user, id = MemberId},
                group_invite_token,
                {group, GroupId}
            ),
            {ok, Macaroon} = token_utils:deserialize(Token),
            {ok, GroupId} = group_logic:join(MemberId, Macaroon)
        end, []]),
        ok
    catch
        _:Reason ->
            {error, Reason}
    end;

join_group(Config, {group, MemberId}, GroupId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, erlang, apply, [fun() ->
            {ok, Token} = token_logic:create(
                #client{type = user, id = MemberId},
                group_invite_group_token,
                {group, GroupId}
            ),
            {ok, Macaroon} = token_utils:deserialize(Token),
            {ok, GroupId} = group_logic:join_group(MemberId, Macaroon)
        end, []]),
        ok
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Removes group from onezone.
%% @end
%%--------------------------------------------------------------------
-spec remove_group(Config :: term(), UserId :: binary()) ->
    boolean() | {error, Reason :: term()}.
remove_group(Config, GroupId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, group_logic, remove, [GroupId])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Creates space in onezone.
%% @end
%%--------------------------------------------------------------------
-spec create_space(Config :: term(), Member :: {user | group, Id :: binary()}, Name :: binary()) ->
    {ok, Id :: binary()} | {error, Reason :: term()}.
create_space(Config, Member, Name) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, space_logic, create, [Member, Name])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Joins space as a user or a group.
%% @end
%%--------------------------------------------------------------------
-spec join_space(Config :: term(), {user | group, Id :: binary()}, SpaceId :: binary()) ->
    ok | {error, Reason :: term()}.
join_space(Config, {user, UserId}, SpaceId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        {ok, SpaceId} = rpc:call(Node, erlang, apply, [fun() ->
            {ok, Token} = token_logic:create(#client{type = user, id = UserId}, space_invite_user_token, {space, SpaceId}),
            {ok, Macaroon} = token_utils:deserialize(Token),
            space_logic:join({user, UserId}, Macaroon)
        end, []]),
        ok
    catch
        _:Reason ->
            {error, Reason}
    end;

join_space(Config, {group, GroupId}, SpaceId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        {ok, SpaceId} = rpc:call(Node, erlang, apply, [fun() ->
            {ok, Token} = token_logic:create(#client{type = provider}, space_invite_group_token, {space, SpaceId}),
            {ok, Macaroon} = token_utils:deserialize(Token),
            space_logic:join({group, GroupId}, Macaroon)
        end, []]),
        ok
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Leaves space as a user or a group.
%% @end
%%--------------------------------------------------------------------
-spec leave_space(Config :: term(), {user | group, Id :: binary()}, SpaceId :: binary()) ->
    ok | {error, Reason :: term()}.
leave_space(Config, {user, UserId}, SpaceId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, space_logic, remove_user, [SpaceId, UserId])
    catch
        _:Reason ->
            {error, Reason}
    end;

leave_space(Config, {group, GroupId}, SpaceId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, space_logic, remove_group, [SpaceId, GroupId])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Supports space by provider.
%% @end
%%--------------------------------------------------------------------
-spec support_space(Config :: term(), ProviderId :: binary(), SpaceId :: binary(), Size :: non_neg_integer()) ->
    ok | {error, Reason :: term()}.
support_space(Config, ProviderId, SpaceId, Size) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        {ok, SpaceId} = rpc:call(Node, erlang, apply, [fun() ->
            {ok, Token} = token_logic:create(#client{type = provider}, space_support_token, {space, SpaceId}),
            {ok, Macaroon} = token_utils:deserialize(Token),
            space_logic:support(ProviderId, Macaroon, Size)
        end, []]),
        ok
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Sets privileges in a space for a user or group.
%% @end
%%--------------------------------------------------------------------
-spec set_space_privileges(Config :: term(), Member :: {user, Id :: binary()},
    SpaceId :: binary(), Privileges :: [privileges:space_privilege()]) ->
    ok | {error, Reason :: term()}.
set_space_privileges(Config, Member, SpaceId, Privileges) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, space_logic, set_privileges, [SpaceId, Member, Privileges])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Modifies space name.
%% @end
%%--------------------------------------------------------------------
-spec modify_space(Config :: term(), SpaceId :: binary(),
    Member :: {user, Id :: binary()} | provider, Name :: binary()) ->
    {ok, Id :: binary()} | {error, Reason :: term()}.
modify_space(Config, SpaceId, Member, Name) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, space_logic, modify, [SpaceId, Member, Name])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Removes space.
%% @end
%%--------------------------------------------------------------------
-spec remove_space(Config :: term(), SpaceId :: binary()) ->
    boolean() | {error, Reason :: term()}.
remove_space(Config, SpaceId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, space_logic, remove, [SpaceId])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Creates a provider.
%% @end
%%--------------------------------------------------------------------
-spec create_provider(Config :: term(), Name :: binary()) ->
    {ok, ProviderId :: binary(), ProviderCertPem :: binary()} |
    {error, Reason :: term()}.
create_provider(Config, Name) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        Prefix = "provider" ++ integer_to_list(random:uniform(123345123)),
        KeyFile = filename:join(?TEMP_DIR, Prefix ++ "_key.pem"),
        CSRFile = filename:join(?TEMP_DIR, Prefix ++ "_csr.pem"),
        os:cmd("openssl genrsa -out " ++ KeyFile ++ " 2048"),
        os:cmd("openssl req -new -batch -key " ++ KeyFile ++ " -out " ++ CSRFile),
        {ok, CSR} = file:read_file(CSRFile),
        rpc:call(Node, provider_logic, create, [
            Name,
            [<<"127.0.0.1">>],
            <<"127.0.0.1">>,
            CSR
        ])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Removes a provider.
%% @end
%%--------------------------------------------------------------------
-spec remove_provider(Config :: term(), ProviderId :: binary()) ->
    boolean() | {error, Reason :: term()}.
remove_provider(Config, ProviderId) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        rpc:call(Node, provider_logic, remove, [ProviderId])
    catch
        _:Reason ->
            {error, Reason}
    end.

%%--------------------------------------------------------------------
%% @doc Removes all entities from onezone (users, groups, spaces, providers).
%% @end
%%--------------------------------------------------------------------
-spec remove_all_entities(Config :: term()) -> ok | {error, Reason :: term()}.
remove_all_entities(Config) ->
    try
        [Node | _] = ?config(oz_worker_nodes, Config),
        % Delete all providers
        {ok, PrDocs} = rpc:call(Node, provider, list, []),
        [true = remove_provider(Config, PId) || #document{key = PId} <- PrDocs],
        % Delete all spaces
        {ok, SpaceDocs} = rpc:call(Node, space, list, []),
        [true = remove_space(Config, SId) || #document{key = SId} <- SpaceDocs],
        % Delete all groups
        {ok, GroupDocs} = rpc:call(Node, user_group, list, []),
        [true = remove_group(Config, GId) || #document{key = GId} <- GroupDocs],
        % Delete all users
        {ok, UserDocs} = rpc:call(Node, onedata_user, list, []),
        [true = remove_user(Config, UId) || #document{key = UId} <- UserDocs],
        ok
    catch
        _:Reason ->
            {error, Reason}
    end.
