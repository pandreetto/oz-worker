%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module encapsulates all user logic functionalities.
%%% In most cases, it is a wrapper for entity_logic functions.
%%% @end
%%%-------------------------------------------------------------------
-module(user_logic).
-author("Lukasz Opiola").

-include("errors.hrl").
-include("entity_logic.hrl").
-include("registered_names.hrl").
-include("datastore/oz_datastore_models_def.hrl").
-include_lib("ctool/include/logging.hrl").

-define(USER_ID_LENGTH_LIMIT, 249).

-define(PLUGIN, user_logic_plugin).

-export([
    create/1, create/2,
    create_client_token/2,
    authorize/1
]).
-export([
    get/2,
    get_data/2,
    list/1,
    get_oz_privileges/2, get_eff_oz_privileges/2,
    list_client_tokens/2,
    get_default_space/2,
    get_space_alias/3,
    get_default_provider/2
]).
-export([
    update_name/3, update_alias/3, update/3,
    update_oz_privileges/4, update_oz_privileges/3,
    set_default_space/3,
    set_space_alias/4,
    set_default_provider/3]).
-export([
    delete/2,
    delete_oz_privileges/2,
    delete_client_token/3,
    unset_default_space/2,
    delete_space_alias/3,
    unset_default_provider/2
]).
-export([
    create_group/3, create_group/4,
    create_space/3,
    create_handle_service/5, create_handle_service/3,
    create_handle/6, create_handle/3,

    join_group/3,
    join_space/3,

    get_groups/2, get_eff_groups/2,
    get_group/3, get_eff_group/3,

    get_spaces/2, get_eff_spaces/2,
    get_space/3, get_eff_space/3,

    get_eff_providers/2, get_eff_provider/3,

    get_handle_services/2, get_eff_handle_services/2,
    get_handle_service/3, get_eff_handle_service/3,

    get_handles/2, get_eff_handles/2,
    get_handle/3, get_eff_handle/3,

    leave_group/3,
    leave_space/3,
    leave_handle_service/3,
    leave_handle/3
]).
-export([
    exists/1,
    has_eff_oz_privilege/2,
    has_eff_space/2,
    has_eff_provider/2
]).
-export([
    idp_uid_to_system_uid/2,
    onepanel_uid_to_system_uid/1,
    create_user_by_linked_account/1,
    merge_linked_account/2,
    is_email_occupied/2,
    authenticate_by_basic_credentials/2,
    change_user_password/3,
    get_default_provider_if_online/1
]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a new user document in database based on user record.
%% @end
%%--------------------------------------------------------------------
-spec create(UserInfo :: #od_user{}) -> {ok, od_user:id()} | {error, term()}.
create(UserInfo) ->
    create(UserInfo, undefined).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new user document in database based on user record.
%% Allows to specify UserId (it must be not occupied).
%% @end
%%--------------------------------------------------------------------
-spec create(UserInfo :: #od_user{}, ProposedUserId :: od_user:id() | undefined) ->
    {ok, od_user:id()} | {error, term()}.
create(UserInfo, ProposedUserId) ->
    try
        case od_user:create(#document{key = ProposedUserId, value = UserInfo}) of
            {error, already_exists} ->
                ?ERROR_BAD_VALUE_ID_OCCUPIED(<<"userId">>);
            {ok, UserId} ->
                setup_user(UserId, UserInfo),
                {ok, UserId}
        end
    catch
        Type:Message ->
            ?error_stacktrace("Cannot create a new user - ~p:~p", [Type, Message]),
            ?ERROR_INTERNAL_SERVER_ERROR
    end.


%%--------------------------------------------------------------------
%% @doc
%% Creates a new client token for given user. Appends the token to the list
%% of user's tokens and returns the token.
%% @end
%%--------------------------------------------------------------------
-spec create_client_token(Client :: entity_logic:client(),
    UserId :: od_user:id()) -> {ok, Token :: binary()} | {error, term()}.
create_client_token(Client, UserId) ->
    entity_logic:create(Client, ?PLUGIN, UserId, client_tokens, #{}).


%%--------------------------------------------------------------------
%% @doc
%% Asserts authorization based on given identifier (retrieved from third party
%% caveats by the client). Has two variants:
%% 1) Identifier is given explicitly
%% 2) Identifier is provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec authorize(Data :: binary() | #{}) ->
    {ok, DischargeMacaroon :: binary()} | {error, term()}.
authorize(Identifier) when is_binary(Identifier) ->
    authorize(#{<<"identifier">> => Identifier});
authorize(Data) ->
    entity_logic:create(?NOBODY, ?PLUGIN, undefined, authorize, Data).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves a user record from database.
%% @end
%%--------------------------------------------------------------------
-spec get(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, #od_user{}} | {error, term()}.
get(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, entity).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves information about a user record from database.
%% @end
%%--------------------------------------------------------------------
-spec get_data(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, #{}} | {error, term()}.
get_data(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, data).


%%--------------------------------------------------------------------
%% @doc
%% Lists all users (their ids) in database.
%% @end
%%--------------------------------------------------------------------
-spec list(Client :: entity_logic:client()) ->
    {ok, [od_user:id()]} | {error, term()}.
list(Client) ->
    entity_logic:get(Client, ?PLUGIN, undefined, list).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves oz privileges of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_oz_privileges(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [privileges:oz_privilege()]} | {error, term()}.
get_oz_privileges(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, oz_privileges).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves effective oz privileges of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_oz_privileges(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [privileges:oz_privilege()]} | {error, term()}.
get_eff_oz_privileges(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, eff_oz_privileges).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves default space of given user. Returns ?ERROR_NOT_FOUND if the user
%% does not have a default space.
%% @end
%%--------------------------------------------------------------------
-spec get_default_space(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, od_space:id()} | {error, term()}.
get_default_space(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {default_space, UserId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves space alias for given space of a user. Returns ?ERROR_NOT_FOUND
%% if the user does not have a space alias for given space.
%% @end
%%--------------------------------------------------------------------
-spec get_space_alias(Client :: entity_logic:client(), UserId :: od_user:id(),
    SpaceId :: od_space:id()) -> {ok, binary()} | {error, term()}.
get_space_alias(Client, UserId, SpaceId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {space_alias, SpaceId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves default provider of given user. Returns ?ERROR_NOT_FOUND if the user
%% does not have a default provider.
%% @end
%%--------------------------------------------------------------------
-spec get_default_provider(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, od_provider:id()} | {error, term()}.
get_default_provider(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {default_provider, UserId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of client tokens of given user.
%% @end
%%--------------------------------------------------------------------
-spec list_client_tokens(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [token:id()]} | {error, term()}.
list_client_tokens(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, client_tokens).


%%--------------------------------------------------------------------
%% @doc
%% Updates the name of given user.
%% @end
%%--------------------------------------------------------------------
-spec update_name(Client :: entity_logic:client(), UserId :: od_user:id(),
    NewName :: binary()) -> ok | {error, term()}.
update_name(Client, UserId, NewName) ->
    update(Client, UserId, #{<<"name">> => NewName}).


%%--------------------------------------------------------------------
%% @doc
%% Updates the alias of given user.
%% @end
%%--------------------------------------------------------------------
-spec update_alias(Client :: entity_logic:client(), UserId :: od_user:id(),
    NewAlias :: binary()) -> ok | {error, term()}.
update_alias(Client, UserId, NewAlias) ->
    update(Client, UserId, #{<<"alias">> => NewAlias}).


%%--------------------------------------------------------------------
%% @doc
%% Updates information of given user (name and alias).
%% @end
%%--------------------------------------------------------------------
-spec update(Client :: entity_logic:client(), UserId :: od_user:id(),
    Data :: #{}) -> ok | {error, term()}.
update(Client, UserId, Data) ->
    entity_logic:update(Client, ?PLUGIN, UserId, entity, Data).


%%--------------------------------------------------------------------
%% @doc
%% Updates oz privileges of given user.
%% Allows to specify operation (set | grant | revoke) and the privileges.
%% @end
%%--------------------------------------------------------------------
-spec update_oz_privileges(Client :: entity_logic:client(), UserId :: od_user:id(),
    Operation :: entity_graph:privileges_operation(),
    Privs :: [privileges:oz_privilege()]) -> ok | {error, term()}.
update_oz_privileges(Client, UserId, Operation, Privs) when is_list(Privs) ->
    update_oz_privileges(Client, UserId, #{
        <<"operation">> => Operation,
        <<"privileges">> => Privs
    }).


%%--------------------------------------------------------------------
%% @doc
%% Updates oz privileges of given user.
%% Privileges must be included in proper Data object, operation is optional.
%% @end
%%--------------------------------------------------------------------
-spec update_oz_privileges(Client :: entity_logic:client(), UserId :: od_user:id(),
    Data :: #{}) -> ok | {error, term()}.
update_oz_privileges(Client, UserId, Data) ->
    entity_logic:update(Client, ?PLUGIN, UserId, oz_privileges, Data).


%%--------------------------------------------------------------------
%% @doc
%% Updates the default space for given user. Has two variants:
%% 1) SpaceId is given explicitly
%% 2) SpaceId is provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec set_default_space(Client :: entity_logic:client(), UserId :: od_user:id(),
    Data :: od_space:id() | #{}) -> ok | {error, term()}.
set_default_space(Client, UserId, SpaceId) when is_binary(SpaceId) ->
    set_default_space(Client, UserId, #{<<"spaceId">> => SpaceId});
set_default_space(Client, UserId, Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, {default_space, UserId}, Data).


%%--------------------------------------------------------------------
%% @doc
%% Updates the space alias for given space of a user. Has two variants:
%% 1) Alias is given explicitly
%% 2) Alias is provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec set_space_alias(Client :: entity_logic:client(), UserId :: od_user:id(),
    SpaceId :: od_space:id(), AliasOrData :: binary() | #{}) -> ok | {error, term()}.
set_space_alias(Client, UserId, SpaceId, Alias) when is_binary(Alias) ->
    set_space_alias(Client, UserId, SpaceId, #{<<"alias">> => Alias});
set_space_alias(Client, UserId, SpaceId, Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, {space_alias, SpaceId}, Data).


%%--------------------------------------------------------------------
%% @doc
%% Updates the default provider for given user. Has two variants:
%% 1) ProviderId is given explicitly
%% 2) ProviderId is provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec set_default_provider(Client :: entity_logic:client(), UserId :: od_user:id(),
    Data :: od_provider:id() | #{}) -> ok | {error, term()}.
set_default_provider(Client, UserId, ProviderId) when is_binary(ProviderId) ->
    set_default_provider(Client, UserId, #{<<"providerId">> => ProviderId});
set_default_provider(Client, UserId, Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, {default_provider, UserId}, Data).


%%--------------------------------------------------------------------
%% @doc
%% Deletes given user from database.
%% @end
%%--------------------------------------------------------------------
-spec delete(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    ok | {error, term()}.
delete(Client, UserId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, entity).


%%--------------------------------------------------------------------
%% @doc
%% Deletes (sets to empty list) oz privileges of given user.
%% @end
%%--------------------------------------------------------------------
-spec delete_oz_privileges(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    ok | {error, term()}.
delete_oz_privileges(Client, UserId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, oz_privileges).


%%--------------------------------------------------------------------
%% @doc
%% Deletes given token of given user.
%% @end
%%--------------------------------------------------------------------
-spec delete_client_token(Client :: entity_logic:client(), UserId :: od_user:id(),
    TokenId :: token:id()) -> ok | {error, term()}.
delete_client_token(Client, UserId, TokenId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, {client_token, TokenId}).


%%--------------------------------------------------------------------
%% @doc
%% Unsets the default space for given user.
%% @end
%%--------------------------------------------------------------------
-spec unset_default_space(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    ok | {error, term()}.
unset_default_space(Client, UserId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, {default_space, UserId}).


%%--------------------------------------------------------------------
%% @doc
%% Deletes the alias for a space of given user.
%% @end
%%--------------------------------------------------------------------
-spec delete_space_alias(Client :: entity_logic:client(), UserId :: od_user:id(),
    SpaceId :: od_space:id()) -> ok | {error, term()}.
delete_space_alias(Client, UserId, SpaceId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, {space_alias, SpaceId}).


%%--------------------------------------------------------------------
%% @doc
%% Unsets the default provider for given user.
%% @end
%%--------------------------------------------------------------------
-spec unset_default_provider(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    ok | {error, term()}.
unset_default_provider(Client, UserId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, {default_provider, UserId}).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new group for given user.
%% Allows to specify group name and type.
%% @end
%%--------------------------------------------------------------------
-spec create_group(Client :: entity_logic:client(), UserId :: od_user:id(),
    Name :: binary(), Type :: od_group:type()) ->
    {ok, od_group:id()} | {error, term()}.
create_group(Client, UserId, Name, Type) ->
    create_group(Client, UserId, #{<<"name">> => Name, <<"type">> => Type}).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new group for given user. Has two variants:
%% 1) Group name is given explicitly (the new group will be of default type)
%% 2) Group name is provided in a proper Data object, group type is optional.
%% @end
%%--------------------------------------------------------------------
-spec create_group(Client :: entity_logic:client(), UserId :: od_user:id(),
    NameOrData :: binary() | #{}) -> {ok, od_group:id()} | {error, term()}.
create_group(Client, UserId, Name) when is_binary(Name) ->
    create_group(Client, UserId, #{<<"name">> => Name, <<"type">> => role});
create_group(Client, UserId, Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, create_group, Data).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new space for given user. Has two variants:
%% 1) Space name is given explicitly
%% 2) Space name is provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec create_space(Client :: entity_logic:client(), UserId :: od_user:id(),
    NameOrData :: binary() | #{}) -> {ok, od_space:id()} | {error, term()}.
create_space(Client, UserId, Name) when is_binary(Name) ->
    create_space(Client, UserId, #{<<"name">> => Name});
create_space(Client, UserId, Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, create_space, Data).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new handle service for given user.
%% Allows to specify the Name, ProxyEndpoint and ServiceProperties.
%% @end
%%--------------------------------------------------------------------
-spec create_handle_service(Client :: entity_logic:client(), UserId :: od_user:id(),
    Name :: binary(), ProxyEndpoint :: od_handle_service:proxy_endpoint(),
    ServiceProperties :: od_handle_service:service_properties()) ->
    {ok, od_handle_service:id()} | {error, term()}.
create_handle_service(Client, UserId, Name, ProxyEndpoint, ServiceProperties) ->
    create_handle_service(Client, UserId, #{
        <<"name">> => Name,
        <<"proxyEndpoint">> => ProxyEndpoint,
        <<"serviceProperties">> => ServiceProperties
    }).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new handle service for given user.
%% Name, ProxyEndpoint and ServiceProperties must be given in proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec create_handle_service(Client :: entity_logic:client(), UserId :: od_user:id(),
    Data :: #{}) -> {ok, od_handle_service:id()} | {error, term()}.
create_handle_service(Client, UserId, Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, create_handle_service, Data).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new handle for given user.
%% Allows to specify the HServiceId, ResourceType, ResourceId and Metadata.
%% @end
%%--------------------------------------------------------------------
-spec create_handle(Client :: entity_logic:client(), UserId :: od_user:id(),
    HServiceId :: od_handle_service:id(), ResourceType :: od_handle:resource_type(),
    ResourceId :: od_handle:resource_id(), Metadata :: od_handle:metadata()) ->
    {ok, od_handle:id()} | {error, term()}.
create_handle(Client, UserId, HServiceId, ResourceType, ResourceId, Metadata) ->
    create_handle(Client, UserId, #{
        <<"handleServiceId">> => HServiceId,
        <<"resourceType">> => ResourceType,
        <<"resourceId">> => ResourceId,
        <<"metadata">> => Metadata
    }).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new handle for given user.
%% HServiceId, ResourceType, ResourceId and Metadata must be given in proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec create_handle(Client :: entity_logic:client(), UserId :: od_user:id(),
    Data :: #{}) -> {ok, od_handle:id()} | {error, term()}.
create_handle(Client, UserId, Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, create_handle, Data).


%%--------------------------------------------------------------------
%% @doc
%% Joins a group on behalf of given user based on group_invite_user token.
%% Has two variants:
%% 1) Token is given explicitly (as binary() or macaroon())
%% 2) Token is provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec join_group(Client :: entity_logic:client(), UserId :: od_user:id(),
    TokenOrData :: token:id() | macaroon:macaroon() | #{}) ->
    {ok, od_group:id()} | {error, term()}.
join_group(Client, UserId, Data) when is_map(Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, join_group, Data);
join_group(Client, UserId, Token) ->
    join_group(Client, UserId, #{<<"token">> => Token}).


%%--------------------------------------------------------------------
%% @doc
%% Joins a space on behalf of given user based on space_invite_user token.
%% Has two variants:
%% 1) Token is given explicitly (as binary() or macaroon())
%% 2) Token is provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec join_space(Client :: entity_logic:client(), UserId :: od_user:id(),
    TokenOrData :: token:id() | macaroon:macaroon() | #{}) ->
    {ok, od_space:id()} | {error, term()}.
join_space(Client, UserId, Data) when is_map(Data) ->
    entity_logic:create(Client, ?PLUGIN, UserId, join_space, Data);
join_space(Client, UserId, Token) ->
    join_space(Client, UserId, #{<<"token">> => Token}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of groups of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_groups(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_group:id()]} | {error, term()}.
get_groups(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, groups).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of effective groups of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_groups(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_group:id()]} | {error, term()}.
get_eff_groups(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, eff_groups).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific group among groups of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_group(Client :: entity_logic:client(), UserId :: od_user:id(),
    GroupId :: od_group:id()) -> {ok, #{}} | {error, term()}.
get_group(Client, UserId, GroupId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {group, GroupId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific effective group among
%% effective groups of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_group(Client :: entity_logic:client(), UserId :: od_user:id(),
    GroupId :: od_group:id()) -> {ok, #{}} | {error, term()}.
get_eff_group(Client, UserId, GroupId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {eff_group, GroupId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of spaces of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_spaces(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_space:id()]} | {error, term()}.
get_spaces(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, spaces).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of effective spaces of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_spaces(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_space:id()]} | {error, term()}.
get_eff_spaces(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, eff_spaces).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific space among spaces of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_space(Client :: entity_logic:client(), UserId :: od_user:id(),
    SpaceId :: od_space:id()) -> {ok, #{}} | {error, term()}.
get_space(Client, UserId, SpaceId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {space, SpaceId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific effective space among
%% effective spaces of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_space(Client :: entity_logic:client(), UserId :: od_user:id(),
    SpaceId :: od_space:id()) -> {ok, #{}} | {error, term()}.
get_eff_space(Client, UserId, SpaceId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {eff_space, SpaceId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of effective providers of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_providers(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_provider:id()]} | {error, term()}.
get_eff_providers(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, eff_providers).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific effective provider among
%% effective providers of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_provider(Client :: entity_logic:client(), UserId :: od_user:id(),
    ProviderId :: od_provider:id()) -> {ok, #{}} | {error, term()}.
get_eff_provider(Client, UserId, ProviderId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {eff_provider, ProviderId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of handle_services of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_handle_services(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_handle_service:id()]} | {error, term()}.
get_handle_services(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, handle_services).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of effective handle_services of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_handle_services(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_handle_service:id()]} | {error, term()}.
get_eff_handle_services(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, eff_handle_services).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific handle_service among
%% handle_services of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_handle_service(Client :: entity_logic:client(), UserId :: od_user:id(),
    HServiceId :: od_handle_service:id()) -> {ok, #{}} | {error, term()}.
get_handle_service(Client, UserId, HServiceId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {handle_service, HServiceId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific effective handle_service among
%% effective handle_services of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_handle_service(Client :: entity_logic:client(), UserId :: od_user:id(),
    HServiceId :: od_handle_service:id()) -> {ok, #{}} | {error, term()}.
get_eff_handle_service(Client, UserId, HServiceId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {eff_handle_service, HServiceId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of handles of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_handles(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_handle:id()]} | {error, term()}.
get_handles(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, handles).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of effective handles of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_handles(Client :: entity_logic:client(), UserId :: od_user:id()) ->
    {ok, [od_handle:id()]} | {error, term()}.
get_eff_handles(Client, UserId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, eff_handles).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific handle among
%% handles of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_handle(Client :: entity_logic:client(), UserId :: od_user:id(),
    HandleId :: od_handle:id()) -> {ok, #{}} | {error, term()}.
get_handle(Client, UserId, HandleId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {handle, HandleId}).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific effective handle among
%% effective handles of given user.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_handle(Client :: entity_logic:client(), UserId :: od_user:id(),
    HandleId :: od_handle:id()) -> {ok, #{}} | {error, term()}.
get_eff_handle(Client, UserId, HandleId) ->
    entity_logic:get(Client, ?PLUGIN, UserId, {eff_handle, HandleId}).


%%--------------------------------------------------------------------
%% @doc
%% Leaves specified group on behalf of given user.
%% @end
%%--------------------------------------------------------------------
-spec leave_group(Client :: entity_logic:client(), UserId :: od_user:id(),
    GroupId :: od_group:id()) -> ok | {error, term()}.
leave_group(Client, UserId, GroupId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, {group, GroupId}).


%%--------------------------------------------------------------------
%% @doc
%% Leaves specified space on behalf of given user.
%% @end
%%--------------------------------------------------------------------
-spec leave_space(Client :: entity_logic:client(), UserId :: od_user:id(),
    SpaceId :: od_space:id()) -> ok | {error, term()}.
leave_space(Client, UserId, SpaceId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, {space, SpaceId}).


%%--------------------------------------------------------------------
%% @doc
%% Leaves specified od_handle_service on behalf of given user.
%% @end
%%--------------------------------------------------------------------
-spec leave_handle_service(Client :: entity_logic:client(), UserId :: od_user:id(),
    HServiceId :: od_handle_service:id()) -> ok | {error, term()}.
leave_handle_service(Client, UserId, HServiceId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, {handle_service, HServiceId}).


%%--------------------------------------------------------------------
%% @doc
%% Leaves specified handle on behalf of given user.
%% @end
%%--------------------------------------------------------------------
-spec leave_handle(Client :: entity_logic:client(), UserId :: od_user:id(),
    HandleId :: od_handle:id()) -> ok | {error, term()}.
leave_handle(Client, UserId, HandleId) ->
    entity_logic:delete(Client, ?PLUGIN, UserId, {handle, HandleId}).


%%--------------------------------------------------------------------
%% @doc
%% Predicate saying whether a user exists.
%% @end
%%--------------------------------------------------------------------
-spec exists(UserId :: od_user:id()) -> boolean().
exists(UserId) ->
    od_user:exists(UserId).


%%--------------------------------------------------------------------
%% @doc
%% Predicate saying whether given user has specified effective oz privilege.
%% @end
%%--------------------------------------------------------------------
-spec has_eff_oz_privilege(UserIdOrUser :: od_user:id() | #od_user{},
    Privilege :: privileges:oz_privilege()) -> boolean().
has_eff_oz_privilege(UserId, Privilege) when is_binary(UserId) ->
    case od_user:get(UserId) of
        {ok, #document{value = User}} ->
            has_eff_oz_privilege(User, Privilege);
        _ ->
            false
    end;
has_eff_oz_privilege(#od_user{eff_oz_privileges = UserPrivileges}, Privilege) ->
    lists:member(Privilege, UserPrivileges).


%%--------------------------------------------------------------------
%% @doc
%% Predicate saying whether given user belongs to specified effective space.
%% @end
%%--------------------------------------------------------------------
-spec has_eff_space(UserIdOrUser :: od_user:id() | #od_user{},
    SpaceId :: od_space:id()) -> boolean().
has_eff_space(UserId, SpaceId) when is_binary(UserId) ->
    case od_user:get(UserId) of
        {ok, #document{value = User}} ->
            has_eff_space(User, SpaceId);
        _ ->
            false
    end;
has_eff_space(#od_user{eff_spaces = EffSpaces}, SpaceId) ->
    maps:is_key(SpaceId, EffSpaces).


%%--------------------------------------------------------------------
%% @doc
%% Predicate saying whether given user belongs to specified effective provider.
%% @end
%%--------------------------------------------------------------------
-spec has_eff_provider(UserIdOrUser :: od_user:id() | #od_user{},
    SpaceId :: od_provider:id()) -> boolean().
has_eff_provider(UserId, ProviderId) when is_binary(UserId) ->
    case od_user:get(UserId) of
        {ok, #document{value = User}} ->
            has_eff_provider(User, ProviderId);
        _ ->
            false
    end;
has_eff_provider(#od_user{eff_providers = EffProviders}, ProviderId) ->
    maps:is_key(ProviderId, EffProviders).


%%--------------------------------------------------------------------
%% @doc
%% Constructs user id based on Identity Provider name and user's id in that IdP.
%% @end
%%--------------------------------------------------------------------
-spec idp_uid_to_system_uid(IdPName :: atom(), IdPUserId :: binary()) -> od_user:id().
idp_uid_to_system_uid(IdPName, IdPUserId) ->
    % Pipes are not allowed in user name as they are used as special character
    % in associative IDs in GUI.
    UserId = base64:encode(str_utils:format_bin("~p:~s", [IdPName, IdPUserId])),
    case byte_size(UserId) > ?USER_ID_LENGTH_LIMIT of
        true -> throw(user_id_too_long);
        false -> UserId
    end.

%%--------------------------------------------------------------------
%% @doc
%% Constructs user id based on Identity Provider name and user's id in that IdP.
%% @end
%%--------------------------------------------------------------------
-spec onepanel_uid_to_system_uid(OnepanelUserId :: binary()) -> od_user:id().
onepanel_uid_to_system_uid(OnepanelUserId) ->
    <<"onezone:", OnepanelUserId/binary>>.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Creates a new user based on given linked account. Before creating such user,
%% it must be ensured that user with such linked account does not exist.
%% @end
%%--------------------------------------------------------------------
-spec create_user_by_linked_account(#linked_account{}) ->
    {ok, UserId :: od_user:id()} | {error, not_found}.
create_user_by_linked_account(LinkedAccount) ->
    #linked_account{provider_id = IdPName, user_id = IdPUserId} = LinkedAccount,
    UserId = idp_uid_to_system_uid(IdPName, IdPUserId),
    {ok, UserId} = create(#od_user{}, UserId),
    merge_linked_account(UserId, LinkedAccount),
    {ok, UserId}.


%%--------------------------------------------------------------------
%% @doc
%% Adds an linked account to user's account or replaces the old one (if
%% present). Gathers user name and emails in the process into user's account.
%% @end
%%--------------------------------------------------------------------
-spec merge_linked_account(UserId :: od_user:id(),
    LinkedAccount :: #linked_account{}) -> ok.
merge_linked_account(UserId, LinkedAccount) ->
    % The update cannot be done in one transaction, because linked account
    % merging causes adding/removing the user from groups, which modifies user
    % doc and would cause a deadlock. Instead, use a critical section to make
    % sure that merging accounts is sequential.
    critical_section:run({merge_acc, UserId}, fun() ->
        merge_linked_account_unsafe(UserId, LinkedAccount)
    end).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Adds an linked account to user's account or replaces the old one (if
%% present). Gathers user name and emails in the process into user's account.
%% Operates on #od_user{} record and returns a modified version.
%% This code should not be run in parallel.
%% @end
%%--------------------------------------------------------------------
-spec merge_linked_account_unsafe(UserId :: od_user:id(),
    LinkedAccount :: #linked_account{}) -> ok.
merge_linked_account_unsafe(UserId, LinkedAccount) ->
    {ok, #document{value = #od_user{
        name = Name, email_list = Emails, linked_accounts = LinkedAccounts
    } = UserInfo}} = od_user:get(UserId),
    #linked_account{
        provider_id = IdP, user_id = IdPUserId,
        email_list = LinkedEmails, groups = NewGroups
    } = LinkedAccount,
    % If no name is specified, take the one provided with new info
    NewName = case Name of
        <<"">> -> resolve_name_from_linked_account(LinkedAccount);
        _ -> Name
    end,
    % Add (normalized) emails from provider that are not yet added to account
    NormalizedEmails = [http_utils:normalize_email(E) || E <- LinkedEmails],
    NewEmails = lists:usort(Emails ++ NormalizedEmails),
    % Replace existing linked account, if present
    {NewLinkedAccs, OldGroups} = case find_linked_account(UserInfo, IdP, IdPUserId) of
        #linked_account{groups = OldGr} = OldLinkedAcc ->
            {[LinkedAccount | (LinkedAccounts -- [OldLinkedAcc])], OldGr};
        undefined ->
            {[LinkedAccount | LinkedAccounts], []}
    end,
    % Coalesce user groups
    idp_group_mapping:coalesce_groups(IdP, UserId, OldGroups, NewGroups),
    % Return updated user info
    {ok, _} = od_user:update(UserId, #{
        name => NewName,
        email_list => NewEmails,
        linked_accounts => NewLinkedAccs
    }),
    ok.


%%--------------------------------------------------------------------
%% @doc
%% Predicate telling if given email is occupied from the point of view of
%% given user. It is not recognized as occupied if the same user already has it.
%% @end
%%--------------------------------------------------------------------
-spec is_email_occupied(UserId :: od_user:id(), Email :: binary()) -> boolean().
is_email_occupied(UserId, Email) ->
    case od_user:get_by_criterion({email, Email}) of
        {ok, #document{key = UserId}} ->
            false;
        {ok, #document{}} ->
            true;
        _ ->
            false
    end.

%%--------------------------------------------------------------------
%% @doc
%% Contacts onepanel to authenticate a user using basic authorization
%% headers. They are sent in base64 encoded form, for example:
%%   <<"Basic dXNlcjpwYXNzd29yZA==">>
%% for credentials user:password, i.e. "Basic base64(user:password)".
%% If the user does not exist in OZ, it is created.
%% Onepanel returns the type of user, i.e. admin|regular. Based on this,
%% the user is added to or removed from admins group (we have to assume that
%% the type can change in time, so when admin type is revoked we should
%% take the admin rights away from the user).
%% @end
%%--------------------------------------------------------------------
-spec authenticate_by_basic_credentials(Login :: binary(),
    Password :: binary()) ->
    {ok, UserDoc :: #document{}, FirstLogin :: boolean()} | {error, term()}.
authenticate_by_basic_credentials(Login, Password) ->
    Headers = basic_auth_header(Login, Password),
    URL = get_onepanel_rest_user_url(Login),
    RestCallResult = case http_client:get(URL, Headers, <<"">>, [insecure]) of
        {ok, 200, _, JSON} ->
            json_utils:decode(JSON);
        {ok, 401, _, _} ->
            {error, <<"Invalid login or password">>};
        {ok, _, _, ErrorJSON} when size(ErrorJSON) > 0 ->
            try
                ErrorProps = json_utils:decode(ErrorJSON),
                Message = proplists:get_value(<<"description">>, ErrorProps,
                    <<"Invalid login or password">>),
                {error, Message}
            catch _:_ ->
                {error, bad_request}
            end;
        {ok, _, _, _} ->
            {error, bad_request};
        {error, Error} ->
            {error, Error}
    end,
    case RestCallResult of
        {error, Reason} ->
            {error, Reason};
        Props ->
            OnepanelUserId = proplists:get_value(<<"userId">>, Props),
            UserId = onepanel_uid_to_system_uid(OnepanelUserId),
            UserRole = proplists:get_value(<<"userRole">>, Props),
            {UserDocument, FirstLogin} = case od_user:get(UserId) of
                {error, {not_found, od_user}} ->
                    UserRecord = #od_user{
                        name = Login,
                        login = Login,
                        basic_auth_enabled = true
                    },
                    {ok, UserId} = create(UserRecord, UserId),
                    ?info("Created new account for user '~s' from onepanel "
                    "(role: '~s'), id: '~s'", [Login, UserRole, UserId]),
                    {ok, UserDoc} = od_user:get(UserId),
                    {UserDoc, true};
                {ok, #document{value = #od_user{} = UserInfo} = UserDoc} ->
                    % Make sure user login is up to date (it might have changed
                    % in onepanel since last login). Also enable basic auth for
                    % him.
                    NewDoc = UserDoc#document{
                        value = UserInfo#od_user{
                            login = Login,
                            basic_auth_enabled = true
                        }},
                    {ok, UserId} = od_user:save(NewDoc),
                    {NewDoc, false}
            end,
            % Check if user's role entitles him to belong to any groups
            {ok, GroupMapping} = application:get_env(
                ?APP_NAME, onepanel_role_to_group_mapping
            ),
            Groups = maps:get(UserRole, GroupMapping, []),
            lists:foreach(
                fun(GroupId) ->
                    case group_logic:add_user(?ROOT, GroupId, UserId) of
                        {ok, UserId} ->
                            {ok, #od_group{
                                name = GroupName
                            }} = group_logic:get(?ROOT, GroupId),
                            ?info("Added user '~s' to group '~s' based on "
                            "role '~s'", [Login, GroupName, UserRole]);
                        ?ERROR_RELATION_ALREADY_EXISTS(_, _, _, _) ->
                            ok
                    end
                end, Groups),
            {ok, UserDocument, FirstLogin}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Contacts onepanel to change user's password using basic authorization
%% headers. They are sent in base64 encoded form, for example:
%%   <<"Basic dXNlcjpwYXNzd29yZA==">>
%% for credentials user:password, i.e. "Basic base64(user:password)".
%% New password is sent in request body.
%% @end
%%--------------------------------------------------------------------
-spec change_user_password(Login :: binary(), OldPassword :: binary(),
    Password :: binary()) -> ok | {error, term()}.
change_user_password(Login, OldPassword, NewPassword) ->
    BasicAuthHeader = basic_auth_header(Login, OldPassword),
    Headers = BasicAuthHeader#{
        <<"content-type">> => <<"application/json">>
    },
    URL = get_onepanel_rest_user_url(Login),
    Body = json_utils:encode([{<<"password">>, NewPassword}]),
    case http_client:patch(URL, Headers, Body, [insecure]) of
        {ok, 204, _, _} ->
            ok;
        {ok, 401, _, _} ->
            {error, <<"Invalid password">>};
        {ok, _, _, ErrorJSON} when size(ErrorJSON) > 0 ->
            try
                ErrorProps = json_utils:decode(ErrorJSON),
                Message = proplists:get_value(<<"description">>, ErrorProps,
                    <<"Cannot change password">>),
                {error, Message}
            catch _:_ ->
                {error, bad_request}
            end;
        {ok, _, _, _} ->
            {error, bad_request};
        {error, Error} ->
            {error, Error}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Returns default provider for given user if it is online (connected to onezone
%% using subscriptions channel), or false otherwise.
%% @end
%%--------------------------------------------------------------------
-spec get_default_provider_if_online(UserOrId :: od_user:id() | #od_user{}) ->
    {true, od_provider:id()} | false.
get_default_provider_if_online(UserId) when is_binary(UserId) ->
    {ok, User} = get(?ROOT, UserId),
    get_default_provider_if_online(User);
get_default_provider_if_online(#od_user{default_provider = undefined}) ->
    false;
get_default_provider_if_online(#od_user{default_provider = DefaultProv}) ->
    case provider_logic:is_provider_connected(DefaultProv) of
        true -> {true, DefaultProv};
        false -> false
    end.


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns basic authorization headers based on login and password.
%% @end
%%--------------------------------------------------------------------
-spec basic_auth_header(Login :: binary(), Password :: binary()) ->
    http_client:headers().
basic_auth_header(Login, Password) ->
    UserAndPassword = base64:encode(<<Login/binary, ":", Password/binary>>),
    #{<<"Authorization">> => <<"Basic ", UserAndPassword/binary>>}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns onepanel REST endpoint for user management.
%% @end
%%--------------------------------------------------------------------
-spec get_onepanel_rest_user_url(Login :: binary()) -> URL :: binary().
get_onepanel_rest_user_url(Login) ->
    {ok, OnepanelRESTURL} =
        application:get_env(?APP_NAME, onepanel_rest_url),
    {ok, OnepanelGetUsersEndpoint} =
        application:get_env(?APP_NAME, onepanel_users_endpoint),
    <<(str_utils:to_binary(OnepanelRESTURL))/binary,
        (str_utils:to_binary(OnepanelGetUsersEndpoint))/binary, Login/binary>>.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns onepanel REST endpoint for user management.
%% @end
%%--------------------------------------------------------------------
-spec setup_user(UserId :: od_user:id(), UserInfo :: #od_user{}) -> ok.
setup_user(UserId, UserInfo) ->
    % Check if automatic first space is enabled, if so create a space
    % for the user.
    case application:get_env(?APP_NAME, enable_automatic_first_space) of
        {ok, true} ->
            SpaceName = case UserInfo#od_user.name of
                <<"">> ->
                    <<"Your First Space">>;
                Name ->
                    <<Name/binary, "'s space">>
            end,
            {ok, SpaceId} = space_logic:create(?USER(UserId), SpaceName),
            od_user:update(UserId, #{default_space => SpaceId});
        _ ->
            ok
    end,

    % Check if global groups are enabled, if so add the user to the groups.
    case application:get_env(?APP_NAME, enable_global_groups) of
        {ok, true} ->
            {ok, GlobalGroups} = application:get_env(?APP_NAME, global_groups),
            lists:foreach(
                fun({GroupId, Privileges}) ->
                    {ok, UserId} = group_logic:add_user(
                        ?ROOT, GroupId, UserId, Privileges
                    )
                end, GlobalGroups);
        _ ->
            ok
    end.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Finds a linked account in user doc based on IdP and user id in that IdP.
%% Returns undefined upon failure.
%% @end
%%--------------------------------------------------------------------
-spec find_linked_account(UserInfo :: od_user:info(), IdP :: atom(),
    IdPUserId :: binary()) -> undefined | #linked_account{}.
find_linked_account(#od_user{linked_accounts = LinkedAccounts}, IdP, IdPUserId) ->
    lists:foldl(
        fun
            (LAcc = #linked_account{provider_id = PId, user_id = UId}, undefined)
                when PId =:= IdP, UId =:= IdPUserId ->
                LAcc;
            (_Other, Found) ->
                Found
        end, undefined, LinkedAccounts).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Resolve what name should be set for user based on his linked account.
%% If user name was send by linked provider, use it.
%% If not, try this with login.
%% If not, try using the email (the part before @) as name.
%% If there is no email, return a generic "unknown" string.
%% @end
%%--------------------------------------------------------------------
-spec resolve_name_from_linked_account(#linked_account{}) -> binary().
resolve_name_from_linked_account(#linked_account{
    name = <<"">>,
    login = <<"">>,
    email_list = []
}) ->
    <<"Unknown Name">>;
resolve_name_from_linked_account(#linked_account{
    name = <<"">>,
    login = <<"">>,
    email_list = EmailList
}) ->
    hd(binary:split(hd(EmailList), <<"@">>));
resolve_name_from_linked_account(#linked_account{
    name = <<"">>,
    login = Login
}) ->
    Login;
resolve_name_from_linked_account(#linked_account{
    name = Name
}) ->
    Name.
