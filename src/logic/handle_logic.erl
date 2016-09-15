%%%-------------------------------------------------------------------
%%% @author Tomasz Lichon
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc The module implementing the business logic for handles in the registry.
%%% This module serves as a buffer between the database and the REST API.
%%% @end
%%%-------------------------------------------------------------------
-module(handle_logic).
-author("Tomasz Lichon").

-include("datastore/oz_datastore_models_def.hrl").

%% API
-export([exists/1, has_user/2, has_effective_user/2, has_group/2, has_effective_privilege/3]).
-export([create/5, modify/3, set_user_privileges/3, set_group_privileges/3]).
-export([get_data/1, get_users/1, get_groups/1, get_user_privileges/2, get_group_privileges/2, get_effective_user_privileges/2]).
-export([add_user/2, add_group/2]).
-export([remove/1, remove_user/2, remove_group/2, cleanup/1]).
-export([list/1]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Returns whether a handle exists.
%% Throws exception when call to the datastore fails.
%% @end
%%--------------------------------------------------------------------
-spec exists(HandleId :: binary()) ->
    boolean().
exists(HandleId) ->
    handle:exists(HandleId).

%%--------------------------------------------------------------------
%% @doc Returns whether the user identified by UserId is a member of the handle.
%% Shall return false in any other case (handle doesn't exist, etc).
%% Throws exception when call to the datastore fails.
%% @end
%%--------------------------------------------------------------------
-spec has_user(HandleId :: binary(), UserId :: binary()) ->
    boolean().
has_user(HandleId, UserId) ->
    case handle:get(HandleId) of
        {error, {not_found, _}} ->
            false;
        {ok, #document{value = #handle{users = Users}}} ->
            lists:keymember(UserId, 1, Users)
    end.

%%--------------------------------------------------------------------
%% @doc Returns whether the user identified by UserId is a member of the handle,
%% either directly or through a group.
%% Shall return false in any other case (handle doesn't exist, etc).
%% Throws exception when call to the datastore fails.
%% @end
%%--------------------------------------------------------------------
-spec has_effective_user(HandleId :: binary(), UserId :: binary()) ->
    boolean().
has_effective_user(HandleId, UserId) ->
    case handle:get(HandleId) of
        {error, {not_found, _}} ->
            false;
        {ok, #document{value = #handle{users = Users, groups = HandleGroups}}} ->
            case lists:keymember(UserId, 1, Users) of
                true ->
                    true;
                false ->
                    case onedata_user:get(UserId) of
                        {error, {not_found, _}} ->
                            false;
                        {ok, #document{value = #onedata_user{groups = UserGroups}}} ->
                            HandleGroupsSet = ordsets:from_list([GroupId || {GroupId, _} <- HandleGroups]),
                            UserGroupsSet = ordsets:from_list(UserGroups),
                            not ordsets:is_disjoint(HandleGroupsSet, UserGroupsSet)
                    end
            end
    end.

%%--------------------------------------------------------------------
%% @doc Returns whether the group identified by GroupId is a member of the handle.
%% Shall return false in any other case (handle doesn't exist, etc).
%% Throws exception when call to the datastore fails.
%% @end
%%--------------------------------------------------------------------
-spec has_group(HandleId :: binary(), GroupId :: binary()) ->
    boolean().
has_group(HandleId, GroupId) ->
    case handle:get(HandleId) of
        {error, {not_found, _}} ->
            false;
        {ok, #document{value = #handle{groups = Groups}}} ->
            lists:keymember(GroupId, 1, Groups)
    end.

%%--------------------------------------------------------------------
%% @doc Returns whether the handle's user identified by UserId has privilege
%% in the handle. Shall return false in any other case (handle doesn't exist,
%% user is not handle's member, etc).
%% Throws exception when call to the datastore fails.
%% @end
%%--------------------------------------------------------------------
-spec has_effective_privilege(HandleId :: binary(), UserId :: binary(),
    Privilege :: privileges:handle_privilege()) ->
    boolean().
has_effective_privilege(HandleId, UserId, Privilege) ->
    case has_effective_user(HandleId, UserId) of
        false -> false;
        true ->
            {ok, UserPrivileges} = get_effective_user_privileges(HandleId, UserId),
            ordsets:is_element(Privilege, UserPrivileges)
    end.

%%--------------------------------------------------------------------
%% @doc Creates a handle for a user.
%% Throws exception when call to the datastore fails, or token/member_from_token doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec create(UserId :: binary(), HandleServiceId :: binary(),
    ResourceType :: binary(), ResourceId :: binary(), HandleLocation :: binary()) ->
    {ok, HandleId :: binary()}.
create(UserId, HandleServiceId, ResourceType, ResourceId, HandleLocation) ->
    Privileges = privileges:handle_admin(),
    Handle = #handle{handle_service_id = HandleServiceId, resource_type = ResourceType,
        resource_id = ResourceId, handle = HandleLocation, users = [{UserId, Privileges}]},

    {ok, HandleId} = handle:save(#document{value = Handle}),
    {ok, _} = onedata_user:update(UserId, fun(User = #onedata_user{handles = UHandles}) ->
        {ok, User#onedata_user{handles = [HandleId | UHandles]}}
    end),

    {ok, HandleId}.

%%--------------------------------------------------------------------
%% @doc Modifies handle's data.
%% Throws exception when call to the datastore fails, or handle doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec modify(handle:id(), handle:resource_type(), handle:resource_id()) -> ok.
modify(_HandleId, undefined, undefined) ->
    ok;
modify(HandleId, NewResourceType, NewResourceId) ->
    {ok, _} = handle:update(HandleId,
        fun(Handle = #handle{resource_type = ResourceType, resource_id = ResourceId}) ->
            FinalResourceType = utils:ensure_defined(NewResourceType, undefined, ResourceType),
            FinalResourceId = utils:ensure_defined(NewResourceId, undefined, ResourceId),
            {ok, Handle#handle{resource_type = FinalResourceType, resource_id = FinalResourceId}}
        end),
    ok.

%%--------------------------------------------------------------------
%% @doc Sets privileges for an user member of the handle.
%% Throws exception when call to the datastore fails, or handle doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec set_user_privileges(HandleId :: binary(), UserId :: binary(),
    Privileges :: [privileges:handle_privilege()]) ->
    ok.
set_user_privileges(HandleId, UserId, Privileges) ->
    {ok, _} = handle:update(HandleId,
        fun(Handle = #handle{users = Users}) ->
            PrivilegesNew = ordsets:from_list(Privileges),
            UsersNew = lists:keyreplace(UserId, 1, Users, {UserId, PrivilegesNew}),
            {ok, Handle#handle{users = UsersNew}}
        end),
    ok.

%%--------------------------------------------------------------------
%% @doc Sets privileges for a group member of the handle.
%% Throws exception when call to the datastore fails, or handle doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec set_group_privileges(HandleId :: binary(), GroupId :: binary(),
    Privileges :: [privileges:handle_privilege()]) ->
    ok.
set_group_privileges(HandleId, GroupId, Privileges) ->
    {ok, _} = handle:update(HandleId,
        fun(Handle = #handle{groups = Groups}) ->
            PrivilegesNew = ordsets:from_list(Privileges),
            GroupsNew = lists:keyreplace(GroupId, 1, Groups, {GroupId, PrivilegesNew}),
            {ok, Handle#handle{groups = GroupsNew}}
        end),
    ok.

%%--------------------------------------------------------------------
%% @doc Adds a new user to a handle.
%% @end
%%--------------------------------------------------------------------
-spec add_user(HandleId :: binary(), UserId :: binary()) ->
    {ok, HandleId :: binary()}.
add_user(HandleId, UserId) ->
    case has_user(HandleId, UserId) of
        true -> ok;
        false ->
            {ok, _} = handle:update(HandleId, fun(Handle) ->
                Privileges = privileges:handle_user(),
                #handle{users = Users} = Handle,
                {ok, Handle#handle{users = [{UserId, Privileges} | Users]}}
            end),
            {ok, _} = onedata_user:update(UserId, fun(User) ->
                #onedata_user{handles = UHandles} = User,
                {ok, User#onedata_user{handles = [HandleId | UHandles]}}
            end)
    end,
    {ok, HandleId}.

%%--------------------------------------------------------------------
%% @doc Adds a new group to a handle.
%% @end
%%--------------------------------------------------------------------
-spec add_group(HandleId :: binary(), GroupId :: binary()) ->
    {ok, HandleId :: binary()}.
add_group(HandleId, GroupId) ->
    case has_group(HandleId, GroupId) of
        true -> ok;
        false ->
            {ok, _} = handle:update(HandleId, fun(Handle) ->
                Privileges = privileges:handle_user(),
                #handle{groups = Groups} = Handle,
                {ok, Handle#handle{groups = [{GroupId, Privileges} | Groups]}}
            end),
            {ok, _} = user_group:update(GroupId, fun(Group) ->
                #user_group{handles = Handles} = Group,
                {ok, Group#user_group{handles = [HandleId | Handles]}}
            end)
    end,
    {ok, HandleId}.


%%--------------------------------------------------------------------
%% @doc Returns details about the handle.
%% Throws exception when call to the datastore fails, or handle doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec get_data(HandleId :: binary()) -> {ok, [proplists:property()]}.
get_data(HandleId) ->
    {ok, #document{value = #handle{handle_service_id = HandleServiceId, handle = Handle,
        resource_type = ResourceType, resource_id = ResourceId}}} =
        handle:get(HandleId),
    {ok, [
        {handleId, HandleId},
        {handleServiceId, HandleServiceId},
        {handle, Handle},
        {resourceType, ResourceType},
        {resourceId, ResourceId}
    ]}.

%%--------------------------------------------------------------------
%% @doc Returns details about handle's users.
%% Throws exception when call to the datastore fails, or handle doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec get_users(HandleId :: binary()) ->
    {ok, [proplists:property()]}.
get_users(HandleId) ->
    {ok, #document{value = #handle{users = Users}}} = handle:get(HandleId),
    {UserIds, _} = lists:unzip(Users),
    {ok, [{users, UserIds}]}.

%%--------------------------------------------------------------------
%% @doc Returns details about handle's groups.
%% Throws exception when call to the datastore fails, or handle doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec get_groups(HandleId :: binary()) ->
    {ok, [proplists:property()]}.
get_groups(HandleId) ->
    {ok, #document{value = #handle{groups = GroupTuples}}} = handle:get(HandleId),
    {Groups, _} = lists:unzip(GroupTuples),
    {ok, [{groups, Groups}]}.

%%--------------------------------------------------------------------
%% @doc Returns list of handle's member privileges.
%% Throws exception when call to the datastore fails, or handle doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec get_user_privileges(HandleId :: binary(), UserId :: binary()) ->
    {ok, [privileges:handle_privilege()]}.
get_user_privileges(HandleId, UserId) ->
    {ok, #document{value = #handle{users = Users}}} = handle:get(HandleId),
    {_, Privileges} = lists:keyfind(UserId, 1, Users),
    {ok, [{privileges, Privileges}]}.

%%--------------------------------------------------------------------
%% @doc Returns list of handle's member privileges.
%% Throws exception when call to the datastore fails, or handle doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec get_group_privileges(HandleId :: binary(), GroupId :: binary()) ->
    {ok, [privileges:handle_privilege()]}.
get_group_privileges(HandleId, GroupId) ->
    {ok, #document{value = #handle{groups = Groups}}} = handle:get(HandleId),
    {_, Privileges} = lists:keyfind(GroupId, 1, Groups),
    {ok, [{privileges, Privileges}]}.

%%--------------------------------------------------------------------
%% @doc Removes the handle.
%% Throws exception when call to the datastore fails, or handle is already removed.
%% @end
%%--------------------------------------------------------------------
-spec remove(HandleId :: binary()) -> true.
remove(HandleId) ->
    {ok, #document{value = Handle}} = handle:get(HandleId),
    #handle{users = Users, groups = Groups} = Handle,

    lists:foreach(fun({UserId, _}) ->
        {ok, _} = onedata_user:update(UserId, fun(User) ->
            #onedata_user{handles = UHandles} = User,
            {ok, User#onedata_user{
                handles = lists:delete(HandleId, UHandles)
            }}
        end)
    end, Users),

    lists:foreach(fun({GroupId, _}) ->
        {ok, _} = user_group:update(GroupId, fun(Group) ->
            #user_group{handles = GHandles} = Group,
            {ok, Group#user_group{handles = lists:delete(HandleId, GHandles)}}
        end)
    end, Groups),

    case handle:delete(HandleId) of
        ok -> true;
        _ -> false
    end.

%%--------------------------------------------------------------------
%% @doc Removes user from the handle.
%% Throws exception when call to the datastore fails, or handle/user doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec remove_user(HandleId :: binary(), UserId :: binary()) ->
    true.
remove_user(HandleId, UserId) ->
    {ok, _} = onedata_user:update(UserId, fun(User) ->
        #onedata_user{handles = UHandles} = User,
        {ok, User#onedata_user{handles = lists:delete(HandleId, UHandles)}}
    end),
    {ok, _} = handle:update(HandleId, fun(Handle) ->
        #handle{users = Users} = Handle,
        {ok, Handle#handle{users = lists:keydelete(UserId, 1, Users)}}
    end),
    cleanup(HandleId),
    true.

%%--------------------------------------------------------------------
%% @doc Removes group from the handle.
%% Throws exception when call to the datastore fails, or handle/group doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec remove_group(HandleId :: binary(), GroupId :: binary()) ->
    true.
remove_group(HandleId, GroupId) ->
    {ok, _} = user_group:update(GroupId, fun(Group) ->
        #user_group{handles = Handles} = Group,
        {ok, Group#user_group{handles = lists:delete(HandleId, Handles)}}
    end),
    {ok, _} = handle:update(HandleId, fun(Handle) ->
        #handle{groups = Groups} = Handle,
        {ok, Handle#handle{groups = lists:keydelete(GroupId, 1, Groups)}}
    end),

    cleanup(HandleId),
    true.

%%--------------------------------------------------------------------
%% @doc Removes the handle if empty.
%% Throws exception when call to the datastore fails, or handle is already removed.
%% @end
%%--------------------------------------------------------------------
-spec cleanup(HandleId :: binary()) -> boolean() | no_return().
cleanup(HandleId) ->
    {ok, #document{value = #handle{groups = Groups, users = Users}}} = handle:get(HandleId),
    case {Groups, Users} of
        {[], []} -> remove(HandleId);
        _ -> false
    end.

%%--------------------------------------------------------------------
%% @doc Retrieves effective user privileges taking into account any groups
%% he is a member of that also are members of the handle.
%% Throws exception when call to the datastore fails, or handle/user doesn't exist.
%% @end
%%--------------------------------------------------------------------
-spec get_effective_user_privileges(HandleId :: binary(), UserId :: binary()) ->
    {ok, ordsets:ordset(privileges:handle_privilege())}.
get_effective_user_privileges(HandleId, UserId) ->
    {ok, #document{value = #onedata_user{groups = UGroups}}} = onedata_user:get(UserId),
    {ok, #document{value = #handle{users = UserTuples, groups = SGroupTuples}}} = handle:get(HandleId),

    UserGroups = sets:from_list(UGroups),

    PrivilegesSets = lists:filtermap(fun({GroupId, Privileges}) ->
        case sets:is_element(GroupId, UserGroups) of
            true -> {true, ordsets:from_list(Privileges)};
            false -> false
        end
    end, SGroupTuples),

    UserPrivileges =
        case lists:keyfind(UserId, 1, UserTuples) of
            {UserId, Privileges} -> ordsets:from_list(Privileges);
            false -> ordsets:new()
        end,

    {ok, ordsets:union([UserPrivileges | PrivilegesSets])}.

%%--------------------------------------------------------------------
%% @doc Returns user's handles.
%% Throws exception when call to the datastore fails, or user doesn't exist, or his groups
%% don't exist.
%% @end
%%--------------------------------------------------------------------
-spec list(UserId :: binary()) ->
    {ok, [proplists:property()]}.
list(UserId) ->
    {ok, Doc} = onedata_user:get(UserId),
    AllUserHandles = get_all_handles(Doc),
    {ok, [{handles, AllUserHandles}]}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Returns a list of all handles that a user belongs to, directly or through
%% a group.
%% Throws exception when call to the datastore fails, or user's groups don't
%% exist.
%% @end
%%--------------------------------------------------------------------
-spec get_all_handles(Doc :: datastore:document()) ->
    ordsets:ordset(HandleId :: binary()).
get_all_handles(#document{value = #onedata_user{
    handles = UserHandles, groups = Groups}}) ->

    UserHandlesSet = ordsets:from_list(UserHandles),
    GroupHandlesSets = lists:map(
        fun(GroupId) ->
            {ok, GroupDoc} = user_group:get(GroupId),
            #document{value = #user_group{handles = GroupHandles}} = GroupDoc,
            ordsets:from_list(GroupHandles)
        end, Groups),

    ordsets:union([UserHandlesSet | GroupHandlesSets]).