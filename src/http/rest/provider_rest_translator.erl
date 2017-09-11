%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module handles translation of entity logic results concerning
%%% provider entities into REST responses.
%%% @end
%%%-------------------------------------------------------------------
-module(provider_rest_translator).
-behaviour(rest_translator_behaviour).
-author("Lukasz Opiola").

-include("rest.hrl").
-include("errors.hrl").
-include("datastore/oz_datastore_models_def.hrl").
-include("registered_names.hrl").
-include_lib("ctool/include/logging.hrl").

-export([response/4]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Translates given entity logic result into REST response
%% expressed by #rest_resp{} record.
%% @end
%%--------------------------------------------------------------------
-spec response(Operation :: entity_logic:operation(),
    EntityId :: entity_logic:entity_id(), Resource :: entity_logic:resource(),
    Result :: entity_logic:result()) -> #rest_resp{}.
response(create, undefined, entity, {ok, {ProvId, Certificate}}) ->
    rest_handler:ok_body_reply(#{
        <<"providerId">> => ProvId,
        <<"certificate">> => Certificate
    });
response(create, undefined, entity_dev, {ok, {ProvId, Certificate}}) ->
    rest_handler:ok_body_reply(#{
        <<"providerId">> => ProvId,
        <<"certificate">> => Certificate
    });
response(create, _ProvId, support, {ok, SpaceId}) ->
    rest_handler:created_reply([<<"provider/spaces/">>, SpaceId]);
response(create, _ProvId, check_my_ports, {ok, Body}) ->
    rest_handler:ok_body_reply(Body);
response(create, _ProvId, map_group, {ok, GroupId}) ->
    rest_handler:ok_body_reply(#{
        <<"groupId">> => GroupId
    });

response(get, undefined, list, {ok, ProviderIds}) ->
    rest_handler:ok_body_reply(#{<<"providers">> => ProviderIds});
response(get, EntityId, data, {ok, ProviderData}) ->
    rest_handler:ok_body_reply(ProviderData#{<<"providerId">> => EntityId});
response(get, _ProvId, eff_users, {ok, UserIds}) ->
    rest_handler:ok_body_reply(#{<<"users">> => UserIds});
response(get, _ProvId, {eff_user, UserId}, {ok, UserData}) ->
    user_rest_translator:response(get, UserId, data, {ok, UserData});
response(get, _ProvId, eff_groups, {ok, GroupIds}) ->
    rest_handler:ok_body_reply(#{<<"groups">> => GroupIds});
response(get, _ProvId, {eff_group, GroupId}, {ok, GroupData}) ->
    group_rest_translator:response(get, GroupId, data, {ok, GroupData});
response(get, _ProvId, spaces, {ok, SpaceIds}) ->
    rest_handler:ok_body_reply(#{<<"spaces">> => SpaceIds});
response(get, _ProvId, {space, SpaceId}, {ok, SpaceData}) ->
    space_rest_translator:response(get, SpaceId, data, {ok, SpaceData});
response(get, _ProvId, {check_my_ip, _}, {ok, IP}) ->
    rest_handler:ok_body_reply(IP);

response(update, _ProvId, _, ok) ->
    rest_handler:updated_reply();

response(delete, _ProvId, _, ok) ->
    rest_handler:deleted_reply().