%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module implements entity logic plugin behaviour and handles
%%% entity logic operations corresponding to od_share model.
%%% @end
%%%-------------------------------------------------------------------
-module(n_share_logic_plugin).
-author("Lukasz Opiola").
-behaviour(entity_logic_plugin_behaviour).

-include("errors.hrl").
-include("entity_logic.hrl").
-include("datastore/oz_datastore_models_def.hrl").
-include_lib("ctool/include/logging.hrl").
-include_lib("ctool/include/privileges.hrl").

-type resource() :: entity | data | list.

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
get_entity(ShareId) ->
    case od_share:get(ShareId) of
        {ok, #document{value = Share}} ->
            {ok, Share};
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
create(_Client, _, entity, Data) ->
    ShareId = maps:get(<<"shareId">>, Data),
    Name = maps:get(<<"name">>, Data),
    SpaceId = maps:get(<<"spaceId">>, Data),
    RootFileId = maps:get(<<"rootFileId">>, Data),
    Share = #document{key = ShareId, value = #od_share{
        name = Name,
        root_file = RootFileId,
        public_url = n_share_logic:share_id_to_public_url(ShareId)
    }},
    case od_share:create(Share) of
        {ok, ShareId} ->
            entity_graph:add_relation(
                od_share, ShareId,
                od_space, SpaceId
            ),
            {ok, ShareId};
        _ ->
            % This can potentially happen if a share with given share id
            % has been created between data verification and create
            ?ERROR_INTERNAL_SERVER_ERROR
    end.


%%--------------------------------------------------------------------
%% @doc
%% Retrieves a resource based on EntityId and Resource identifier.
%% @end
%%--------------------------------------------------------------------
-spec get(Client :: n_entity_logic:client(), EntityId :: n_entity_logic:entity_id(),
    Entity :: n_entity_logic:entity(), Resource :: resource()) ->
    n_entity_logic:result().
get(_, undefined, undefined, list) ->
    {ok, ShareDocs} = od_share:list(),
    {ok, [ShareId || #document{key = ShareId} <- ShareDocs]};

get(_, _ShareId, #od_share{} = Share, data) ->
    #od_share{
        name = Name, public_url = PublicUrl, space = SpaceId,
        root_file = RootFileId, handle = HandleId
    } = Share,
    {ok, #{
        <<"name">> => Name, <<"publicUrl">> => PublicUrl,
        <<"spaceId">> => SpaceId, <<"rootFileId">> => RootFileId,
        <<"handleId">> => HandleId
    }}.


%%--------------------------------------------------------------------
%% @doc
%% Updates a resource based on EntityId, Resource identifier and Data.
%% @end
%%--------------------------------------------------------------------
-spec update(EntityId :: n_entity_logic:entity_id(), Resource :: resource(),
    n_entity_logic:data()) -> n_entity_logic:result().
update(ShareId, entity, #{<<"name">> := NewName}) ->
    {ok, _} = od_share:update(ShareId, #{name => NewName}),
    ok.


%%--------------------------------------------------------------------
%% @doc
%% Deletes a resource based on EntityId and Resource identifier.
%% @end
%%--------------------------------------------------------------------
-spec delete(EntityId :: n_entity_logic:entity_id(), Resource :: resource()) ->
    n_entity_logic:result().
delete(ShareId, entity) ->
    entity_graph:delete_with_relations(od_share, ShareId).


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
exists(_) ->
    % No matter the resource, return true if it belongs to a share
    {internal, fun(#od_share{}) ->
        % If the share with ShareId can be found, it exists. If not, the
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
authorize(create, undefined, entity, ?USER(UserId)) ->
    {data_dependent, fun(Data) ->
        SpaceId = maps:get(<<"spaceId">>, Data, <<"">>),
        n_space_logic:has_eff_privilege(
            SpaceId, UserId, ?SPACE_MANAGE_SHARES
        )
    end};
authorize(get, _ShareId, entity, ?USER(UserId)) ->
    {internal, fun(#od_share{space = SpaceId}) ->
        n_space_logic:has_eff_user(SpaceId, UserId)
    end};


authorize(update, _ShareId, entity, ?USER(UserId)) ->
    {internal, fun(#od_share{space = SpaceId}) ->
        n_space_logic:has_eff_privilege(SpaceId, UserId, ?SPACE_MANAGE_SHARES)
    end};

authorize(delete, _ShareId, entity, ?USER(UserId)) ->
    {internal, fun(#od_share{space = SpaceId}) ->
        n_space_logic:has_eff_privilege(SpaceId, UserId, ?SPACE_MANAGE_SHARES)
    end}.


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
validate(create, entity) -> #{
    required => #{
        <<"shareId">> => {binary, {not_exists, fun(Value) ->
            not n_share_logic:exists(Value)
        end}},
        <<"name">> => {binary, non_empty},
        <<"rootFileId">> => {binary, non_empty},
        <<"spaceId">> => {binary, {exists, fun(Value) ->
            n_space_logic:exists(Value)
        end}}
    }
};
validate(update, entity) -> #{
    required => #{
        <<"name">> => {binary, non_empty}
    }
}.


%%--------------------------------------------------------------------
%% @doc
%% Returns readable string representing the entity with given id.
%% @end
%%--------------------------------------------------------------------
-spec entity_to_string(EntityId :: n_entity_logic:entity_id()) -> binary().
entity_to_string(ShareId) ->
    od_share:to_string(ShareId).


