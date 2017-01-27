%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc

%%% @end
%%%-------------------------------------------------------------------
-module(n_handle_service_logic).
-author("Lukasz Opiola").

-include("datastore/oz_datastore_models_def.hrl").
-include_lib("ctool/include/logging.hrl").

-define(PLUGIN, n_handle_service_logic_plugin).

-export([
    create/4, create/2
]).
-export([
    get/2,
    get_data/2,
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
    user_has_eff_privilege/3,
    group_has_eff_privilege/3
]).


create(Client, Name, ProxyEndpoint, ServiceProperties) ->
    create(Client, #{
        <<"name">> => Name,
        <<"proxyEndpoint">> => ProxyEndpoint,
        <<"serviceProperties">> => ServiceProperties
    }).
create(Client, Data) ->
    n_entity_logic:create(Client, ?PLUGIN, undefined, entity, Data).


get(Client, HServiceId) ->
    n_entity_logic:get(Client, ?PLUGIN, entity, HServiceId).


get_data(Client, HServiceId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, data).


list(Client) ->
    n_entity_logic:get(Client, ?PLUGIN, undefined, list).


update(Client, HServiceId, Data) ->
    n_entity_logic:update(Client, ?PLUGIN, HServiceId, entity, Data).


delete(Client, HServiceId) ->
    n_entity_logic:delete(Client, ?PLUGIN, HServiceId, entity).


%%--------------------------------------------------------------------
%% @doc
%% Adds specified user to given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec add_user(Client :: n_entity_logic:client(),
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
-spec add_user(Client :: n_entity_logic:client(),
    HServiceId :: od_handle_service:id(), UserId :: od_user:id(),
    PrivilegesPrivilegesOrData :: [privileges:handle_service_privileges()] | #{}) ->
    {ok, od_user:id()} | {error, term()}.
add_user(Client, HServiceId, UserId, Privileges) when is_list(Privileges) ->
    add_user(Client, HServiceId, UserId, #{
        <<"privileges">> => Privileges
    });
add_user(Client, HServiceId, UserId, Data) ->
    n_entity_logic:create(Client, ?PLUGIN, HServiceId, {user, UserId}, Data).


%%--------------------------------------------------------------------
%% @doc
%% Adds specified group to given handle_service.
%% @end
%%--------------------------------------------------------------------
-spec add_group(Client :: n_entity_logic:client(),
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
-spec add_group(Client :: n_entity_logic:client(),
    HServiceId :: od_handle_service:id(), GroupId :: od_group:id(),
    PrivilegesOrData :: [privileges:handle_service_privileges()] | #{}) ->
    {ok, od_group:id()} | {error, term()}.
add_group(Client, HServiceId, GroupId, Privileges) when is_binary(GroupId) ->
    add_group(Client, HServiceId, GroupId, #{
        <<"privileges">> => Privileges
    });
add_group(Client, HServiceId, GroupId, Data) ->
    n_entity_logic:create(Client, ?PLUGIN, HServiceId, {child, GroupId}, Data).


get_users(Client, HServiceId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, users).


get_eff_users(Client, HServiceId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, eff_users).


get_user(Client, HServiceId, UserId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {user, UserId}).


get_eff_user(Client, HServiceId, UserId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {eff_user, UserId}).


get_user_privileges(Client, HServiceId, UserId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {user_privileges, UserId}).


get_eff_user_privileges(Client, HServiceId, UserId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {eff_user_privileges, UserId}).


get_groups(Client, HServiceId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, groups).


get_eff_groups(Client, HServiceId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, eff_groups).


get_group(Client, HServiceId, GroupId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {group, GroupId}).


get_eff_group(Client, HServiceId, GroupId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {eff_group, GroupId}).


get_group_privileges(Client, HServiceId, GroupId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {group_privileges, GroupId}).


get_eff_group_privileges(Client, HServiceId, GroupId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {eff_group_privileges, GroupId}).


get_handles(Client, HServiceId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, handles).


get_handle(Client, HServiceId, HandleId) ->
    n_entity_logic:get(Client, ?PLUGIN, HServiceId, {handle, HandleId}).


update_user_privileges(Client, HServiceId, UserId, Operation, Privs) when is_list(Privs) ->
    update_user_privileges(Client, HServiceId, UserId, #{
        <<"operation">> => Operation,
        <<"privileges">> => Privs
    }).
update_user_privileges(Client, HServiceId, UserId, Data) ->
    n_entity_logic:update(Client, ?PLUGIN, HServiceId, {user_privileges, UserId}, Data).


update_group_privileges(Client, HServiceId, GroupId, Operation, Privs) when is_list(Privs) ->
    update_group_privileges(Client, HServiceId, GroupId, #{
        <<"operation">> => Operation,
        <<"privileges">> => Privs
    }).
update_group_privileges(Client, HServiceId, GroupId, Data) ->
    n_entity_logic:update(Client, ?PLUGIN, HServiceId, {group_privileges, GroupId}, Data).


remove_user(Client, HServiceId, UserId) ->
    n_entity_logic:delete(Client, ?PLUGIN, HServiceId, {user, UserId}).


remove_group(Client, HServiceId, GroupId) ->
    n_entity_logic:delete(Client, ?PLUGIN, HServiceId, {group, GroupId}).


user_has_eff_privilege(HServiceId, UserId, Privilege) when is_binary(HServiceId) ->
    case od_handle_service:get(HServiceId) of
        {ok, #document{value = HService}} ->
            user_has_eff_privilege(HService, UserId, Privilege);
        _ ->
            false
    end;
user_has_eff_privilege(#od_handle_service{eff_users = UsersPrivileges}, UserId, Privilege) ->
    {UserPrivileges, _} = maps:get(UserId, UsersPrivileges, {[], []}),
    lists:member(Privilege, UserPrivileges).


group_has_eff_privilege(HServiceId, GroupId, Privilege) when is_binary(HServiceId) ->
    case od_handle_service:get(HServiceId) of
        {ok, #document{value = HService}} ->
            group_has_eff_privilege(HService, GroupId, Privilege);
        _ ->
            false
    end;
group_has_eff_privilege(#od_handle_service{eff_groups = GroupsPrivileges}, GroupId, Privilege) ->
    {GroupPrivileges, _} = maps:get(GroupId, GroupsPrivileges, {[], []}),
    lists:member(Privilege, GroupPrivileges).


%%--------------------------------------------------------------------
%% @doc
%% Returns whether a handle service exists.
%% @end
%%--------------------------------------------------------------------
-spec exists(HServiceId :: od_handle_service:id()) -> boolean().
exists(HServiceId) ->
    od_handle_service:exists(HServiceId).


