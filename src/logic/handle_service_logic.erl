%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module encapsulates all handle service logic functionalities.
%%% In most cases, it is a wrapper for entity_logic functions.
%%% @end
%%%-------------------------------------------------------------------
-module(handle_service_logic).
-author("Lukasz Opiola").

-include("datastore/oz_datastore_models.hrl").
-include_lib("ctool/include/logging.hrl").

-define(PLUGIN, handle_service_logic_plugin).

-export([
    create/4, create/2
]).
-export([
    get/2,
    get_protected_data/2,
    list/1
]).
-export([
    update/3
]).
-export([
    delete/2
]).
-export([

    add_user/3, add_user/4,
    add_group/3, add_group/4,

    get_users/2, get_eff_users/2,
    get_user/3, get_eff_user/3,
    get_user_privileges/3, get_eff_user_privileges/3,

    get_groups/2, get_eff_groups/2,
    get_group/3, get_eff_group/3,
    get_group_privileges/3, get_eff_group_privileges/3,

    get_handles/2, get_handle/3,

    update_user_privileges/5, update_user_privileges/4,
    update_group_privileges/5, update_group_privileges/4,

    remove_user/3,
    remove_group/3
]).
-export([
    exists/1,
    has_eff_privilege/3,
    has_eff_user/2,
    has_eff_group/2
]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a new handle_service document in database based on Name,
%% ProxyEndpoint and ServiceProperties.
%% @end
%%--------------------------------------------------------------------
-spec create(Client :: entity_logic:client(), Name :: binary(),
    ProxyEndpoint :: od_handle_service:proxy_endpoint(),
    ServiceProperties :: od_handle_service:service_properties()) ->
    {ok, od_handle_service:id()} | {error, term()}.
create(Client, Name, ProxyEndpoint, ServiceProperties) ->
    create(Client, #{
        <<"name">> => Name,
        <<"proxyEndpoint">> => ProxyEndpoint,
        <<"serviceProperties">> => ServiceProperties
    }).


%%--------------------------------------------------------------------
%% @doc
%% Creates a new handle_service document in database. Name, ProxyEndpoint
%% and ServiceProperties are provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec create(Client :: entity_logic:client(), Data :: #{}) ->
    {ok, od_handle_service:id()} | {error, term()}.
create(Client, Data) ->
    AuthHint = case Client of
        ?USER(UserId) -> ?AS_USER(UserId);
        _ -> undefined
    end,
    ?CREATE_RETURN_ID(entity_logic:handle(#el_req{
        operation = create,
        client = Client,
        gri = #gri{type = od_handle_service, id = undefined, aspect = instance},
        data = Data,
        auth_hint = AuthHint
    })).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves a handle_service record from database.
%% @end
%%--------------------------------------------------------------------
-spec get(Client :: entity_logic:client(), HServiceId :: od_handle_service:id()) ->
    {ok, #od_handle_service{}} | {error, term()}.
get(Client, HServiceId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = instance}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves protected handle_service data from database.
%% @end
%%--------------------------------------------------------------------
-spec get_protected_data(Client :: entity_logic:client(), HServiceId :: od_handle_service:id()) ->
    {ok, maps:map()} | {error, term()}.
get_protected_data(Client, HServiceId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = instance, scope = protected}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Lists all handle_services (their ids) in database.
%% @end
%%--------------------------------------------------------------------
-spec list(Client :: entity_logic:client()) ->
    {ok, [od_handle_service:id()]} | {error, term()}.
list(Client) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = undefined, aspect = list}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Updates information of given handle_service. Supports updating Name,
%% ProxyEndpoint and ServiceProperties.
%% @end
%%--------------------------------------------------------------------
-spec update(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    Data :: #{}) -> ok | {error, term()}.
update(Client, HServiceId, Data) ->
    entity_logic:handle(#el_req{
        operation = update,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = instance},
        data = Data
    }).


%%--------------------------------------------------------------------
%% @doc
%% Deletes given handle_service from database.
%% @end
%%--------------------------------------------------------------------
-spec delete(Client :: entity_logic:client(), HServiceId :: od_handle_service:id()) ->
    ok | {error, term()}.
delete(Client, HServiceId) ->
    entity_logic:handle(#el_req{
        operation = delete,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = instance}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Adds specified user to given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec add_user(Client :: entity_logic:client(),
    HServiceId :: od_handle_service:id(), UserId :: od_user:id()) ->
    {ok, od_user:id()} | {error, term()}.
add_user(Client, HServiceId, UserId)  ->
    add_user(Client, HServiceId, UserId, #{}).


%%--------------------------------------------------------------------
%% @doc
%% Adds specified user to given handle_service.
%% Allows to specify the privileges of the newly added user. Has two variants:
%% 1) Privileges are given explicitly
%% 2) Privileges are provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec add_user(Client :: entity_logic:client(),
    HServiceId :: od_handle_service:id(), UserId :: od_user:id(),
    PrivilegesPrivilegesOrData :: [privileges:handle_service_privileges()] | #{}) ->
    {ok, od_user:id()} | {error, term()}.
add_user(Client, HServiceId, UserId, Privileges) when is_list(Privileges) ->
    add_user(Client, HServiceId, UserId, #{
        <<"privileges">> => Privileges
    });
add_user(Client, HServiceId, UserId, Data) ->
    ?CREATE_RETURN_ID(entity_logic:handle(#el_req{
        operation = create,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {user, UserId}},
        data = Data
    })).


%%--------------------------------------------------------------------
%% @doc
%% Adds specified group to given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec add_group(Client :: entity_logic:client(),
    HServiceId :: od_handle_service:id(), GroupId :: od_group:id()) ->
    {ok, od_group:id()} | {error, term()}.
add_group(Client, HServiceId, GroupId)  ->
    add_group(Client, HServiceId, GroupId, #{}).


%%--------------------------------------------------------------------
%% @doc
%% Adds specified group to given handle_service.
%% Allows to specify the privileges of the newly added group. Has two variants:
%% 1) Privileges are given explicitly
%% 2) Privileges are provided in a proper Data object.
%% @end
%%--------------------------------------------------------------------
-spec add_group(Client :: entity_logic:client(),
    HServiceId :: od_handle_service:id(), GroupId :: od_group:id(),
    PrivilegesOrData :: [privileges:handle_service_privileges()] | #{}) ->
    {ok, od_group:id()} | {error, term()}.
add_group(Client, HServiceId, GroupId, Privileges) when is_list(Privileges) ->
    add_group(Client, HServiceId, GroupId, #{
        <<"privileges">> => Privileges
    });
add_group(Client, HServiceId, GroupId, Data) ->
    ?CREATE_RETURN_ID(entity_logic:handle(#el_req{
        operation = create,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {group, GroupId}},
        data = Data
    })).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of users of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_users(Client :: entity_logic:client(), SpaceId :: od_space:id()) ->
    {ok, [od_user:id()]} | {error, term()}.
get_users(Client, HServiceId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = users}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of effective users of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_users(Client :: entity_logic:client(), SpaceId :: od_space:id()) ->
    {ok, [od_user:id()]} | {error, term()}.
get_eff_users(Client, HServiceId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = eff_users}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific user among users of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_user(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    UserId :: od_user:id()) -> {ok, #{}} | {error, term()}.
get_user(Client, HServiceId, UserId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_user, id = UserId, aspect = instance, scope = shared},
        auth_hint = ?THROUGH_HANDLE_SERVICE(HServiceId)
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific effective user among
%% effective users of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_user(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    UserId :: od_user:id()) -> {ok, #{}} | {error, term()}.
get_eff_user(Client, HServiceId, UserId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_user, id = UserId, aspect = instance, scope = shared},
        auth_hint = ?THROUGH_HANDLE_SERVICE(HServiceId)
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the privileges of specific user among users of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_user_privileges(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    UserId :: od_user:id()) -> {ok, [privileges:handle_service_privileges()]} | {error, term()}.
get_user_privileges(Client, HServiceId, UserId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {user_privileges, UserId}}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the effective privileges of specific effective user
%% among effective users of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_user_privileges(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    UserId :: od_user:id()) -> {ok, [privileges:handle_service_privileges()]} | {error, term()}.
get_eff_user_privileges(Client, HServiceId, UserId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {eff_user_privileges, UserId}}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of groups of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_groups(Client :: entity_logic:client(), HServiceId :: od_handle_service:id()) ->
    {ok, [od_group:id()]} | {error, term()}.
get_groups(Client, HServiceId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = groups}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of effective groups of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_groups(Client :: entity_logic:client(), HServiceId :: od_handle_service:id()) ->
    {ok, [od_group:id()]} | {error, term()}.
get_eff_groups(Client, HServiceId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = eff_groups}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific group among groups of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_group(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    GroupId :: od_group:id()) -> {ok, #{}} | {error, term()}.
get_group(Client, HServiceId, GroupId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_group, id = GroupId, aspect = instance, scope = shared},
        auth_hint = ?THROUGH_HANDLE_SERVICE(HServiceId)
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific effective group among
%% effective groups of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_group(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    GroupId :: od_group:id()) -> {ok, #{}} | {error, term()}.
get_eff_group(Client, HServiceId, GroupId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_group, id = GroupId, aspect = instance, scope = shared},
        auth_hint = ?THROUGH_HANDLE_SERVICE(HServiceId)
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the privileges of specific group among groups of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_group_privileges(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    GroupId :: od_group:id()) -> {ok, [privileges:handle_service_privileges()]} | {error, term()}.
get_group_privileges(Client, HServiceId, GroupId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {group_privileges, GroupId}}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the effective privileges of specific effective group
%% among effective groups of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_eff_group_privileges(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    GroupId :: od_group:id()) -> {ok, [privileges:handle_service_privileges()]} | {error, term()}.
get_eff_group_privileges(Client, HServiceId, GroupId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {eff_group_privileges, GroupId}}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the list of handles of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_handles(Client :: entity_logic:client(), HServiceId :: od_handle_service:id()) ->
    {ok, [od_handle:id()]} | {error, term()}.
get_handles(Client, HServiceId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = handles}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves the information about specific handle among handles of given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec get_handle(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    HandleId :: od_handle:id()) -> {ok, #{}} | {error, term()}.
get_handle(Client, HServiceId, HandleId) ->
    entity_logic:handle(#el_req{
        operation = get,
        client = Client,
        gri = #gri{type = od_handle, id = HandleId, aspect = instance, scope = protected},
        auth_hint = ?THROUGH_HANDLE_SERVICE(HServiceId)
    }).


%%--------------------------------------------------------------------
%% @doc
%% Updates privileges of specified user of given handle_service.
%% Allows to specify operation (set | grant | revoke) and the privileges.
%% @end
%%--------------------------------------------------------------------
-spec update_user_privileges(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    UserId :: od_user:id(), Operation :: entity_graph:privileges_operation(),
    Privs :: [privileges:handle_service_privilege()]) -> ok | {error, term()}.
update_user_privileges(Client, HServiceId, UserId, Operation, Privs) when is_list(Privs) ->
    update_user_privileges(Client, HServiceId, UserId, #{
        <<"operation">> => Operation,
        <<"privileges">> => Privs
    }).


%%--------------------------------------------------------------------
%% @doc
%% Updates privileges of specified user of given handle_service.
%% Privileges must be included in proper Data object, operation is optional.
%% @end
%%--------------------------------------------------------------------
-spec update_user_privileges(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    UserId :: od_user:id(), Data :: #{}) -> ok | {error, term()}.
update_user_privileges(Client, HServiceId, UserId, Data) ->
    entity_logic:handle(#el_req{
        operation = update,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {user_privileges, UserId}},
        data = Data
    }).


%%--------------------------------------------------------------------
%% @doc
%% Updates privileges of specified group of given handle_service.
%% Allows to specify operation (set | grant | revoke) and the privileges.
%% @end
%%--------------------------------------------------------------------
-spec update_group_privileges(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    GroupId :: od_group:id(), Operation :: entity_graph:privileges_operation(),
    Privs :: [privileges:handle_service_privilege()]) -> ok | {error, term()}.
update_group_privileges(Client, HServiceId, GroupId, Operation, Privs) when is_list(Privs) ->
    update_group_privileges(Client, HServiceId, GroupId, #{
        <<"operation">> => Operation,
        <<"privileges">> => Privs
    }).


%%--------------------------------------------------------------------
%% @doc
%% Updates privileges of specified group of given handle_service.
%% Privileges must be included in proper Data object, operation is optional.
%% @end
%%--------------------------------------------------------------------
-spec update_group_privileges(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    GroupId :: od_user:id(), Data :: #{}) -> ok | {error, term()}.
update_group_privileges(Client, HServiceId, GroupId, Data) ->
    entity_logic:handle(#el_req{
        operation = update,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {group_privileges, GroupId}},
        data = Data
    }).


%%--------------------------------------------------------------------
%% @doc
%% Removes specified user from given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec remove_user(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    UserId :: od_user:id()) -> ok | {error, term()}.
remove_user(Client, HServiceId, UserId) ->
    entity_logic:handle(#el_req{
        operation = delete,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {user, UserId}}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Removes specified group from given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec remove_group(Client :: entity_logic:client(), HServiceId :: od_handle_service:id(),
    GroupId :: od_group:id()) -> ok | {error, term()}.
remove_group(Client, HServiceId, GroupId) ->
    entity_logic:handle(#el_req{
        operation = delete,
        client = Client,
        gri = #gri{type = od_handle_service, id = HServiceId, aspect = {group, GroupId}}
    }).


%%--------------------------------------------------------------------
%% @doc
%% Returns whether a handle service exists.
%% @end
%%--------------------------------------------------------------------
-spec exists(HServiceId :: od_handle_service:id()) -> boolean().
exists(HServiceId) ->
    {ok, Exists} =od_handle_service:exists(HServiceId),
    Exists.


%%--------------------------------------------------------------------
%% @doc
%% Predicate saying whether specified effective user has specified
%% effective privilege in given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec has_eff_privilege(HServiceOrId :: od_handle_service:id() | #od_handle_service{},
    UserId :: od_user:id(), Privilege :: privileges:handle_service_privileges()) ->
    boolean().
has_eff_privilege(HServiceId, UserId, Privilege) when is_binary(HServiceId) ->
    case od_handle_service:get(HServiceId) of
        {ok, #document{value = HService}} ->
            has_eff_privilege(HService, UserId, Privilege);
        _ ->
            false
    end;
has_eff_privilege(#od_handle_service{eff_users = UsersPrivileges}, UserId, Privilege) ->
    {UserPrivileges, _} = maps:get(UserId, UsersPrivileges, {[], []}),
    lists:member(Privilege, UserPrivileges).


%%--------------------------------------------------------------------
%% @doc
%% Predicate saying whether specified user is an effective user in given
%% handle_service.
%% @end
%%--------------------------------------------------------------------
-spec has_eff_user(HServiceOrId :: od_handle_service:id() | #od_handle_service{},
    UserId :: od_user:id()) -> boolean().
has_eff_user(HServiceId, UserId) when is_binary(HServiceId) ->
    case od_handle_service:get(HServiceId) of
        {ok, #document{value = HService}} ->
            has_eff_user(HService, UserId);
        _ ->
            false
    end;
has_eff_user(#od_handle_service{eff_users = EffUsers}, UserId) ->
    maps:is_key(UserId, EffUsers).


%%--------------------------------------------------------------------
%% @doc
%% Predicate saying whether specified group is an effective group in given
%% handle_service.
%% @end
%%--------------------------------------------------------------------
-spec has_eff_group(HServiceOrId :: od_handle_service:id() | #od_handle_service{},
    GroupId :: od_group:id()) -> boolean().
has_eff_group(HServiceId, GroupId) when is_binary(HServiceId) ->
    case od_handle_service:get(HServiceId) of
        {ok, #document{value = HService}} ->
            has_eff_group(HService, GroupId);
        _ ->
            false
    end;
has_eff_group(#od_handle_service{eff_groups = EffGroups}, GroupId) ->
    maps:is_key(GroupId, EffGroups).
