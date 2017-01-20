%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module implements entity logic plugin behaviour and handles
%%% entity logic operations corresponding to od_space model.
%%% @end
%%%-------------------------------------------------------------------
-module(n_space_logic_plugin).
-author("Lukasz Opiola").
-behaviour(entity_logic_plugin_behaviour).

-include("errors.hrl").
-include("tokens.hrl").
-include("entity_logic.hrl").
-include("datastore/oz_datastore_models_def.hrl").
-include_lib("ctool/include/logging.hrl").
-include_lib("ctool/include/privileges.hrl").

-type resource() :: {deprecated_user_privileges, od_user:id()} | % TODO VFS-2918
{deprecated_group_privileges, od_group:id()} | % TODO VFS-2918
{deprecated_create_share, od_share:id()} |  % TODO VFS-2918
deprecated_invite_user_token | deprecated_invite_group_token |  % TODO VFS-2918
deprecated_invite_provider_token | % TODO VFS-2918
invite_user_token | invite_group_token | invite_provider_token |
entity | data | list |
users | eff_users | {user, od_user:id()} | {eff_user, od_user:id()} |
{user_privileges, od_user:id()} | {eff_user_privileges, od_user:id()} |
groups | eff_groups | {group, od_group:id()} | {eff_group, od_group:id()} |
{group_privileges, od_user:id()} | {eff_group_privileges, od_user:id()} |
shares | {share, od_share:id()} |
providers | {provider, od_provider:id()}.

-export_type([resource/0]).

-export([get_entity/1, create/4, get/4, update/3, delete/2]).
-export([exists/1, authorize/4, validate/2]).
-export([entity_to_string/1]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Retrieves an entity from datastore based on its EntityId.
%% Should return ?ERROR_NOT_FOUND if the entity does not exist.
%% @end
%%--------------------------------------------------------------------
-spec get_entity(EntityId :: n_entity_logic:entity_id()) ->
    {ok, n_entity_logic:entity()} | {error, Reason :: term()}.
get_entity(SpaceId) ->
    case od_space:get(SpaceId) of
        {ok, #document{value = Space}} ->
            {ok, Space};
        _ ->
            ?ERROR_NOT_FOUND
    end.


%%--------------------------------------------------------------------
%% @doc
%% Creates a resource based on EntityId, Resource identifier and Data.
%% @end
%%--------------------------------------------------------------------
-spec create(Client :: n_entity_logic:client(),
    EntityId :: n_entity_logic:entity_id(), Resource :: resource(),
    n_entity_logic:data()) -> n_entity_logic:result().
% TODO VFS-2918
create(_Client, SpaceId, {deprecated_user_privileges, UserId}, Data) ->
    Privileges = maps:get(<<"privileges">>, Data),
    Operation = maps:get(<<"operation">>, Data, set),
    entity_graph:update_relation(
        od_user, UserId,
        od_space, SpaceId,
        {Operation, Privileges}
    );
% TODO VFS-2918
create(_Client, SpaceId, {deprecated_child_privileges, GroupId}, Data) ->
    Privileges = maps:get(<<"privileges">>, Data),
    Operation = maps:get(<<"operation">>, Data, set),
    entity_graph:update_relation(
        od_group, GroupId,
        od_space, SpaceId,
        {Operation, Privileges}
    );
% TODO VFS-2918
create(Client, SpaceId, {deprecated_create_share, ShareId}, Data) ->
    case n_share_logic:exists(ShareId) of
        true ->
            ?ERROR_BAD_VALUE_ID_OCCUPIED(<<"shareId">>);
        false ->
            n_share_logic_plugin:create(Client, undefined, entity, Data#{
                <<"spaceId">> => SpaceId,
                <<"shareId">> => ShareId
            })
    end;

create(Client, _, entity, #{<<"name">> := Name}) ->
    {ok, SpaceId} = od_space:create(#document{value = #od_space{name = Name}}),
    case Client of
        ?USER(UserId) ->
            entity_graph:add_relation(
                od_user, UserId,
                od_space, SpaceId,
                privileges:space_admin()
            );
        _ ->
            ok
    end,
    {ok, SpaceId};

create(Client, SpaceId, invite_user_token, _) ->
    {ok, Token} = token_logic:create(
        Client,
        ?SPACE_INVITE_USER_TOKEN,
        {od_space, SpaceId}
    ),
    {ok, Token};

create(Client, SpaceId, invite_group_token, _) ->
    {ok, Token} = token_logic:create(
        Client,
        ?SPACE_INVITE_GROUP_TOKEN,
        {od_space, SpaceId}
    ),
    {ok, Token};

create(Client, SpaceId, invite_provider_token, _) ->
    {ok, Token} = token_logic:create(
        Client,
        ?SPACE_SUPPORT_TOKEN,
        {od_space, SpaceId}
    ),
    {ok, Token};

create(_Client, SpaceId, users, Data) ->
    UserId = maps:get(<<"userId">>, Data),
    Privileges = maps:get(<<"privileges">>, Data, privileges:space_user()),
    entity_graph:add_relation(
        od_user, UserId,
        od_space, SpaceId,
        Privileges
    ),
    {ok, UserId};

create(_Client, SpaceId, groups, Data) ->
    GroupId = maps:get(<<"groupId">>, Data),
    Privileges = maps:get(<<"privileges">>, Data, privileges:space_user()),
    entity_graph:add_relation(
        od_group, GroupId,
        od_space, SpaceId,
        Privileges
    ),
    {ok, GroupId}.


%%--------------------------------------------------------------------
%% @doc
%% Retrieves a resource based on EntityId and Resource identifier.
%% @end
%%--------------------------------------------------------------------
-spec get(Client :: n_entity_logic:client(), EntityId :: n_entity_logic:entity_id(),
    Entity :: n_entity_logic:entity(), Resource :: resource()) ->
    n_entity_logic:result().
% TODO VFS-2918 - remove Client from get when these are not needed
% TODO VFS-2918
get(Client, SpaceId, _, deprecated_invite_user_token) ->
    {ok, Token} = token_logic:create(
        Client,
        ?SPACE_INVITE_USER_TOKEN,
        {od_space, SpaceId}
    ),
    {ok, Token};
% TODO VFS-2918
get(Client, SpaceId, _, deprecated_invite_group_token) ->
    {ok, Token} = token_logic:create(
        Client,
        ?SPACE_INVITE_GROUP_TOKEN,
        {od_space, SpaceId}
    ),
    {ok, Token};
% TODO VFS-2918
get(Client, SpaceId, _, deprecated_invite_provider_token) ->
    {ok, Token} = token_logic:create(
        Client,
        ?SPACE_SUPPORT_TOKEN,
        {od_space, SpaceId}
    ),
    {ok, Token};

get(_, undefined, undefined, list) ->
    {ok, SpaceDocs} = od_space:list(),
    {ok, [SpaceId || #document{key = SpaceId} <- SpaceDocs]};
get(_, _SpaceId, #od_space{name = Name}, data) ->
    {ok, #{<<"name">> => Name}};

get(_, _SpaceId, #od_space{users = Users}, users) ->
    {ok, maps:keys(Users)};
get(_, _SpaceId, #od_space{eff_users = Users}, eff_users) ->
    {ok, maps:keys(Users)};
get(_, _SpaceId, #od_space{}, {user, UserId}) ->
    {ok, User} = ?throw_on_failure(n_user_logic_plugin:get_entity(UserId)),
    n_user_logic_plugin:get(?ROOT, UserId, User, data);
get(_, _SpaceId, #od_space{}, {eff_user, UserId}) ->
    {ok, User} = ?throw_on_failure(n_user_logic_plugin:get_entity(UserId)),
    n_user_logic_plugin:get(?ROOT, UserId, User, data);
get(_, _SpaceId, #od_space{users = Users}, {user_privileges, UserId}) ->
    {ok, maps:get(UserId, Users)};
get(_, _SpaceId, #od_space{eff_users = Users}, {eff_user_privileges, UserId}) ->
    {Privileges, _} = maps:get(UserId, Users),
    {ok, Privileges};

get(_, _SpaceId, #od_space{groups = Groups}, groups) ->
    {ok, maps:keys(Groups)};
get(_, _SpaceId, #od_space{eff_groups = Groups}, eff_groups) ->
    {ok, maps:keys(Groups)};
get(_, _SpaceId, #od_space{}, {group, GroupId}) ->
    {ok, Group} = ?throw_on_failure(n_group_logic_plugin:get_entity(GroupId)),
    n_group_logic_plugin:get(?ROOT, GroupId, Group, data);
get(_, _SpaceId, #od_space{}, {eff_group, GroupId}) ->
    {ok, Group} = ?throw_on_failure(n_group_logic_plugin:get_entity(GroupId)),
    n_group_logic_plugin:get(?ROOT, GroupId, Group, data);
get(_, _SpaceId, #od_space{groups = Groups}, {group_privileges, GroupId}) ->
    {ok, maps:get(GroupId, Groups)};
get(_, _SpaceId, #od_space{eff_groups = Groups}, {eff_group_privileges, GroupId}) ->
    {Privileges, _} = maps:get(GroupId, Groups),
    {ok, Privileges};

get(_, _SpaceId, #od_space{shares = Shares}, shares) ->
    {ok, Shares};
get(_, _SpaceId, #od_space{}, {share, ShareId}) ->
    {ok, Share} = ?throw_on_failure(n_share_logic_plugin:get_entity(ShareId)),
    n_share_logic_plugin:get(?ROOT, ShareId, Share, data);

get(_, _SpaceId, #od_space{providers = Providers}, providers) ->
    {ok, maps:keys(Providers)};
get(_, _SpaceId, #od_space{}, {provider, ProviderId}) ->
    {ok, Provider} = ?throw_on_failure(n_provider_logic_plugin:get_entity(ProviderId)),
    n_provider_logic_plugin:get(?ROOT, ProviderId, Provider, data).


%%--------------------------------------------------------------------
%% @doc
%% Updates a resource based on EntityId, Resource identifier and Data.
%% @end
%%--------------------------------------------------------------------
-spec update(EntityId :: n_entity_logic:entity_id(), Resource :: resource(),
    n_entity_logic:data()) -> n_entity_logic:result().
update(SpaceId, entity, #{<<"name">> := NewName}) ->
    {ok, _} = od_space:update(SpaceId, #{name => NewName}),
    ok;

update(SpaceId, {user_privileges, UserId}, Data) ->
    Privileges = maps:get(<<"privileges">>, Data),
    Operation = maps:get(<<"operation">>, Data, set),
    entity_graph:update_relation(
        od_user, UserId,
        od_space, SpaceId,
        {Operation, Privileges}
    );

update(SpaceId, {group_privileges, GroupId}, Data) ->
    Privileges = maps:get(<<"privileges">>, Data),
    Operation = maps:get(<<"operation">>, Data, set),
    entity_graph:update_relation(
        od_group, GroupId,
        od_space, SpaceId,
        {Operation, Privileges}
    ).


%%--------------------------------------------------------------------
%% @doc
%% Deletes a resource based on EntityId and Resource identifier.
%% @end
%%--------------------------------------------------------------------
-spec delete(EntityId :: n_entity_logic:entity_id(), Resource :: resource()) ->
    n_entity_logic:result().
delete(SpaceId, entity) ->
    entity_graph:delete_with_relations(od_space, SpaceId);

delete(SpaceId, {user, UserId}) ->
    entity_graph:remove_relation(
        od_user, UserId,
        od_space, SpaceId
    );

delete(SpaceId, {group, GroupId}) ->
    entity_graph:remove_relation(
        od_group, GroupId,
        od_space, SpaceId
    ).


%%--------------------------------------------------------------------
%% @doc
%% Returns existence verificators for given Resource identifier.
%% Existence verificators can be internal, which means they operate on the
%% entity to which the resource corresponds, or external - independent of
%% the entity. If there are multiple verificators, they will be checked in
%% sequence until one of them returns true.
%% Implicit verificators 'true' | 'false' immediately stop the verification
%% process with given result.
%% @end
%%--------------------------------------------------------------------
-spec exists(Resource :: resource()) ->
    n_entity_logic:existence_verificator()|
    [n_entity_logic:existence_verificator()].
exists({user, UserId}) ->
    {internal, fun(#od_space{users = Users}) ->
        maps:is_key(UserId, Users)
    end};
exists({eff_user, UserId}) ->
    {internal, fun(#od_space{eff_users = Users}) ->
        maps:is_key(UserId, Users)
    end};
exists({user_privileges, UserId}) ->
    {internal, fun(#od_space{users = Users}) ->
        maps:is_key(UserId, Users)
    end};
exists({eff_user_privileges, UserId}) ->
    {internal, fun(#od_space{eff_users = Users}) ->
        maps:is_key(UserId, Users)
    end};

exists({group, UserId}) ->
    {internal, fun(#od_space{groups = Users}) ->
        maps:is_key(UserId, Users)
    end};
exists({eff_group, UserId}) ->
    {internal, fun(#od_space{eff_groups = Users}) ->
        maps:is_key(UserId, Users)
    end};
exists({group_privileges, UserId}) ->
    {internal, fun(#od_space{groups = Users}) ->
        maps:is_key(UserId, Users)
    end};
exists({eff_group_privileges, UserId}) ->
    {internal, fun(#od_space{eff_groups = Users}) ->
        maps:is_key(UserId, Users)
    end};

exists({share, ProviderId}) ->
    {internal, fun(#od_space{shares = Providers}) ->
        maps:is_key(ProviderId, Providers)
    end};

exists({provider, ProviderId}) ->
    {internal, fun(#od_space{providers = Providers}) ->
        maps:is_key(ProviderId, Providers)
    end};

exists(_) ->
    % No matter the resource, return true if it belongs to a space
    {internal, fun(#od_space{}) ->
        % If the space with SpaceId can be found, it exists. If not, the
        % verification will fail before this function is called.
        true
    end}.


%%--------------------------------------------------------------------
%% @doc
%% Returns existence verificators for given Resource identifier.
%% Existence verificators can be internal, which means they operate on the
%% entity to which the resource corresponds, or external - independent of
%% the entity. If there are multiple verificators, they will be checked in
%% sequence until one of them returns true.
%% Implicit verificators 'true' | 'false' immediately stop the verification
%% process with given result.
%% @end
%%--------------------------------------------------------------------
-spec authorize(Operation :: n_entity_logic:operation(),
    EntityId :: n_entity_logic:entity_id(), Resource :: resource(),
    Client :: n_entity_logic:client()) ->
    n_entity_logic:authorization_verificator() |
    [authorization_verificator:existence_verificator()].
% TODO VFS-2918
authorize(create, _GroupId, {deprecated_create_share, _ShareId}, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_MANAGE_SHARES);
% TODO VFS-2918
authorize(get, _GroupId, deprecated_invite_user_token, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_INVITE_USER);
% TODO VFS-2918
authorize(get, _GroupId, deprecated_invite_group_token, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_INVITE_GROUP);
% TODO VFS-2918
authorize(get, _GroupId, deprecated_invite_provider_token, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_INVITE_PROVIDER);
% TODO VFS-2918
authorize(create, _GroupId, {deprecated_user_privileges, _UserId}, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_SET_PRIVILEGES);
% TODO VFS-2918
authorize(create, _GroupId, {deprecated_child_privileges, _ChildGroupId}, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_SET_PRIVILEGES);

authorize(create, undefined, entity, ?USER) ->
    true;

authorize(create, _SpaceId, invite_user_token, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_INVITE_USER);

authorize(create, _SpaceId, invite_group_token, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_INVITE_GROUP);

authorize(create, _SpaceId, invite_provider_token, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_INVITE_PROVIDER);

authorize(create, _SpaceId, users, ?USER(UserId)) ->
    auth_by_oz_privilege(UserId, ?OZ_SPACES_ADD_MEMBERS);

authorize(create, _SpaceId, groups, ?USER(UserId)) ->
    auth_by_oz_privilege(UserId, ?OZ_SPACES_ADD_MEMBERS);


authorize(get, undefined, list, ?USER(UserId)) ->
    n_user_logic:has_eff_oz_privilege(UserId, ?OZ_SPACES_LIST);

authorize(get, _SpaceId, entity, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_VIEW);

authorize(get, _SpaceId, data, ?USER(UserId)) ->
    auth_by_membership(UserId);

authorize(get, _SpaceId, data, ?PROVIDER(ProviderId)) ->
    auth_by_support(ProviderId);

authorize(get, _SpaceId, shares, ?USER(UserId)) ->
    auth_by_membership(UserId);

authorize(get, _SpaceId, shares, ?PROVIDER(ProviderId)) ->
    auth_by_support(ProviderId);

authorize(get, _SpaceId, {share, _ShareId}, ?USER(UserId)) ->
    auth_by_membership(UserId);

authorize(get, _SpaceId, {share, _ShareId}, ?PROVIDER(ProviderId)) ->
    auth_by_support(ProviderId);

authorize(get, _SpaceId, providers, ?PROVIDER(ProviderId)) ->
    auth_by_support(ProviderId);

authorize(get, _SpaceId, _, ?USER(UserId)) ->
    % All other resources can be accessed with view privileges
    auth_by_privilege(UserId, ?SPACE_VIEW);


authorize(update, _SpaceId, entity, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_UPDATE);

authorize(update, _SpaceId, {user_privileges, _UserId}, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_SET_PRIVILEGES);

authorize(update, _SpaceId, {group_privileges, _GroupId}, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_SET_PRIVILEGES);


authorize(delete, _SpaceId, entity, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_DELETE);

authorize(delete, _SpaceId, {user, _UserId}, ?USER(UserId)) -> [
    auth_by_privilege(UserId, ?SPACE_REMOVE_USER),
    auth_by_oz_privilege(UserId, ?OZ_SPACES_REMOVE_MEMBERS)
];

authorize(delete, _SpaceId, {group, _GroupId}, ?USER(UserId)) -> [
    auth_by_privilege(UserId, ?SPACE_REMOVE_GROUP),
    auth_by_oz_privilege(UserId, ?OZ_SPACES_REMOVE_MEMBERS)
];

authorize(delete, _SpaceId, {provider, _ProviderId}, ?USER(UserId)) ->
    auth_by_privilege(UserId, ?SPACE_REMOVE_PROVIDER).


%%--------------------------------------------------------------------
%% @doc
%% Returns validity verificators for given Operation and Resource identifier.
%% Returns a map with 'required', 'optional' and 'at_least_one' keys.
%% Under each of them, there is a map:
%%      Key => {type_verificator, value_verificator}
%% Which means how value of given Key should be validated.
%% @end
%%--------------------------------------------------------------------
-spec validate(Operation :: n_entity_logic:operation(),
    Resource :: resource()) ->
    n_entity_logic:validity_verificator().
% TODO VFS-2918
validate(create, {deprecated_create_share, _ShareId}) -> #{
    required => #{
        <<"name">> => {binary, non_empty},
        <<"rootFileId">> => {binary, non_empty}
    }
};
% TODO VFS-2918
validate(create, {deprecated_user_privileges, UserId}) ->
    validate(update, {user_privileges, UserId});
% TODO VFS-2918
validate(create, {deprecated_group_privileges, GroupId}) ->
    validate(update, {user_privileges, GroupId});

validate(create, entity) -> #{
    required => #{
        <<"name">> => {binary, non_empty}
    }
};
validate(create, invite_user_token) -> #{
};
validate(create, invite_group_token) -> #{
};
validate(create, invite_provider_token) -> #{
};
validate(create, users) -> #{
    required => #{
        <<"userId">> => {binary, {exists, fun(Value) ->
            n_user_logic:exists(Value)
        end}}
    }
};
validate(create, groups) -> #{
    required => #{
        <<"groupId">> => {binary, {exists, fun(Value) ->
            n_group_logic:exists(Value)
        end}}
    }
};

validate(update, entity) -> #{
    required => #{
        <<"name">> => {binary, non_empty}
    }
};
validate(update, {user_privileges, _UserId}) -> #{
    required => #{
        <<"privileges">> => {list_of_atoms, privileges:space_privileges()}
    },
    optional => #{
        <<"operation">> => {atom, [set, grant, revoke]}
    }
};
validate(update, {group_privileges, GroupId}) ->
    validate(update, {user_privileges, GroupId}).


%%--------------------------------------------------------------------
%% @doc
%% Returns readable string representing the entity with given id.
%% @end
%%--------------------------------------------------------------------
-spec entity_to_string(EntityId :: n_entity_logic:entity_id()) -> binary().
entity_to_string(SpaceId) ->
    od_space:to_string(SpaceId).


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns authorization verificator that checks if given user belongs
%% to the space represented by entity.
%% @end
%%--------------------------------------------------------------------
-spec auth_by_membership(UserId :: od_user:id()) ->
    n_entity_logic:authorization_verificator().
auth_by_membership(UserId) ->
    {internal, fun(#od_space{users = Users, eff_users = EffUsers}) ->
        maps:is_key(UserId, EffUsers) orelse maps:is_key(UserId, Users)
    end}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns authorization verificator that checks if given provider supports
%% the space represented by entity.
%% @end
%%--------------------------------------------------------------------
-spec auth_by_support(ProviderId :: od_provider:id()) ->
    n_entity_logic:authorization_verificator().
auth_by_support(ProviderId) ->
    {internal, fun(#od_space{providers = Providers}) ->
        maps:is_key(ProviderId, Providers)
    end}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns authorization verificator that checks if given user has specific
%% effective privilege in the space represented by entity.
%% @end
%%--------------------------------------------------------------------
-spec auth_by_privilege(UserId :: od_user:id(),
    Privilege :: privileges:space_privilege()) ->
    n_entity_logic:authorization_verificator().
auth_by_privilege(UserId, Privilege) ->
    {internal, fun(#od_space{} = Space) ->
        n_space_logic:has_eff_privilege(Space, UserId, Privilege)
    end}.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns authorization verificator that checks if given user has specified
%% effective oz privilege.
%% @end
%%--------------------------------------------------------------------
-spec auth_by_oz_privilege(UserId :: od_user:id(),
    Privilege :: privileges:oz_privilege()) ->
    n_entity_logic:authorization_verificator().
auth_by_oz_privilege(UserId, Privilege) ->
    {external, fun() ->
        n_user_logic:has_eff_oz_privilege(UserId, Privilege)
    end}.

