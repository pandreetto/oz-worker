%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C): 2017 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This behaviour should be implemented by modules that implement entity logic
%%% operations. Every entity logic plugin serves as a middleware between
%%% API and datastore in the context of specific entity type (od_xxx records).
%%% @end
%%%-------------------------------------------------------------------
-module(entity_logic_plugin_behaviour).
-include("datastore/oz_datastore_models_def.hrl").

%%--------------------------------------------------------------------
%% @doc
%% Retrieves an entity from datastore based on its EntityId.
%% Should return ?ERROR_NOT_FOUND if the entity does not exist.
%% @end
%%--------------------------------------------------------------------
-callback get_entity(EntityId :: entity_logic:entity_id()) ->
    {ok, entity_logic:entity()} | {error, Reason :: term()}.


%%--------------------------------------------------------------------
%% @doc
%% Creates a resource based on EntityId, Resource identifier and Data.
%% @end
%%--------------------------------------------------------------------
-callback create(Client :: entity_logic:client(),
    EntityId :: entity_logic:entity_id(), Resource :: entity_logic:resource(),
    entity_logic:data()) -> entity_logic:result().


%%--------------------------------------------------------------------
%% @doc
%% Retrieves a resource based on EntityId and Resource identifier.
%% @end
%%--------------------------------------------------------------------
-callback get(Client :: entity_logic:client(), EntityId :: entity_logic:entity_id(),
    Entity :: entity_logic:entity(), Resource :: entity_logic:resource()) ->
    entity_logic:result().


%%--------------------------------------------------------------------
%% @doc
%% Updates a resource based on EntityId, Resource identifier and Data.
%% @end
%%--------------------------------------------------------------------
-callback update(EntityId :: entity_logic:entity_id(),
    Resource :: entity_logic:resource(),
    entity_logic:data()) -> entity_logic:result().


%%--------------------------------------------------------------------
%% @doc
%% Deletes a resource based on EntityId and Resource identifier.
%% @end
%%--------------------------------------------------------------------
-callback delete(EntityId :: entity_logic:entity_id(),
    Resource :: entity_logic:resource()) -> entity_logic:result().


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
-callback exists(Resource :: entity_logic:resource()) ->
    entity_logic:existence_verificator()|
    [entity_logic:existence_verificator()].


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
-callback authorize(Operation :: entity_logic:operation(),
    EntityId :: entity_logic:entity_id(), Resource :: entity_logic:resource(),
    Client :: entity_logic:client()) ->
    entity_logic:authorization_verificator() |
    [authorization_verificator:existence_verificator()].


%%--------------------------------------------------------------------
%% @doc
%% Returns validity verificators for given Operation and Resource identifier.
%% Returns a map with 'required', 'optional' and 'at_least_one' keys.
%% Under each of them, there is a map:
%%      Key => {type_verificator, value_verificator}
%% Which means how value of given Key should be validated.
%% @end
%%--------------------------------------------------------------------
-callback validate(Operation :: entity_logic:operation(),
    Resource :: entity_logic:resource()) ->
    entity_logic:validity_verificator().


%%--------------------------------------------------------------------
%% @doc
%% Returns readable string representing the entity with given id.
%% @end
%%--------------------------------------------------------------------
-callback entity_to_string(EntityId :: entity_logic:entity_id()) -> binary().