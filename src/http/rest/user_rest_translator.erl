%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module handles translation of entity logic results concerning
%%% user entities into REST responses.
%%% @end
%%%-------------------------------------------------------------------
-module(user_rest_translator).
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
response(create, UserId, {deprecated_default_space, UserId}, ok) ->
    rest_handler:ok_no_content_reply();

response(create, _UserId, authorize, {ok, DischargeMacaroon}) ->
    rest_handler:ok_body_reply({binary, DischargeMacaroon});

response(create, _UserId, client_tokens, {ok, Token}) ->
    rest_handler:ok_body_reply(#{<<"token">> => Token});

response(create, UserId, {default_space, UserId}, ok) ->
    rest_handler:ok_no_content_reply();

response(create, _UserId, space_alias, ok) ->
    rest_handler:ok_no_content_reply();

response(create, UserId, {default_provider, UserId}, ok) ->
    rest_handler:ok_no_content_reply();

response(create, _UserId, create_group, {ok, GroupId}) ->
    rest_handler:created_reply(
        % TODO VFS-2918
%%        [<<"user">>, <<"groups">>, GroupId]
        [<<"groups">>, GroupId]
    );

response(create, _UserId, create_space, {ok, SpaceId}) ->
    rest_handler:created_reply(
        % TODO VFS-2918
%%        [<<"user">>, <<"spaces">>, SpaceId]
        [<<"spaces">>, SpaceId]
    );

response(create, _UserId, create_handle_service, {ok, HServiceId}) ->
    rest_handler:created_reply(
        % TODO VFS-2918
%%        [<<"user">>, <<"handle_services">>, HServiceId]
        [<<"handle_services">>, HServiceId]
    );

response(create, _UserId, create_handle, {ok, HandleId}) ->
    rest_handler:created_reply(
        % TODO VFS-2918
%%        [<<"user">>, <<"handles">>, HandleId]
        [ <<"handles">>, HandleId]
    );

response(create, _UserId, join_group, {ok, GroupId}) ->
    rest_handler:created_reply([<<"user">>, <<"groups">>, GroupId]);

response(create, _UserId, join_space, {ok, SpaceId}) ->
    rest_handler:created_reply([<<"user">>, <<"spaces">>, SpaceId]);


response(get, UserId, {deprecated_default_space, UserId}, {ok, SpaceId}) ->
    rest_handler:ok_body_reply(#{<<"spaceId">> => SpaceId});

response(get, UserId, data, {ok, UserData}) ->
    rest_handler:ok_body_reply(UserData#{<<"userId">> => UserId});

response(get, undefined, list, {ok, Users}) ->
    rest_handler:ok_body_reply(#{<<"users">> => Users});

response(get, _UserId, oz_privileges, {ok, Privileges}) ->
    rest_handler:ok_body_reply(#{<<"privileges">> => Privileges});

response(get, _UserId, eff_oz_privileges, {ok, Privileges}) ->
    rest_handler:ok_body_reply(#{<<"privileges">> => Privileges});

response(get, UserId, {default_space, UserId}, {ok, DefaultSpace}) ->
    rest_handler:ok_body_reply(#{<<"spaceId">> => DefaultSpace});

response(get, _UserId, {space_alias, _SpaceId}, {ok, SpaceAlias}) ->
    rest_handler:ok_body_reply(#{<<"alias">> => SpaceAlias});

response(get, UserId, {default_provider, UserId}, {ok, DefaultProvider}) ->
    rest_handler:ok_body_reply(#{<<"providerId">> => DefaultProvider});

response(get, _UserId, client_tokens, {ok, Tokens}) ->
    rest_handler:ok_body_reply(#{<<"tokens">> => Tokens});

response(get, _UserId, groups, {ok, Groups}) ->
    rest_handler:ok_body_reply(#{<<"groups">> => Groups});

response(get, _UserId, eff_groups, {ok, Groups}) ->
    % TODO VFS-2918
    rest_handler:ok_body_reply(#{<<"effective_groups">> => Groups});
%%    rest_handler:ok_body_reply(#{<<"groups">> => Groups});

response(get, _UserId, {group, GroupId}, {ok, Group}) ->
    group_rest_translator:response(get, GroupId, data, {ok, Group});

response(get, _UserId, {eff_group, GroupId}, {ok, Group}) ->
    group_rest_translator:response(get, GroupId, data, {ok, Group});

response(get, UserId, spaces, {ok, Spaces}) ->
    % TODO VFS-2918
    DefaultSpace = case user_logic:get_default_space(?ROOT, UserId) of
        {ok, SpaceId} -> SpaceId;
        ?ERROR_NOT_FOUND -> undefined
    end,
    rest_handler:ok_body_reply(
        #{
            <<"spaces">> => Spaces,
            % TODO VFS-2918
            <<"default">> => DefaultSpace
        });

response(get, _UserId, eff_spaces, {ok, Spaces}) ->
    rest_handler:ok_body_reply(#{<<"spaces">> => Spaces});

response(get, _UserId, {space, SpaceId}, {ok, Space}) ->
    space_rest_translator:response(get, SpaceId, data, {ok, Space});

response(get, _UserId, {eff_space, SpaceId}, {ok, Space}) ->
    space_rest_translator:response(get, SpaceId, data, {ok, Space});

response(get, _UserId, eff_providers, {ok, Providers}) ->
    rest_handler:ok_body_reply(#{<<"providers">> => Providers});

response(get, _UserId, {eff_provider, ProviderId}, {ok, Provider}) ->
    provider_rest_translator:response(get, ProviderId, data, {ok, Provider});

response(get, _UserId, handle_services, {ok, HServices}) ->
    rest_handler:ok_body_reply(#{<<"handle_services">> => HServices});

response(get, _UserId, eff_handle_services, {ok, HServices}) ->
    rest_handler:ok_body_reply(#{<<"handle_services">> => HServices});

response(get, _UserId, {handle_service, HServiceId}, {ok, HService}) ->
    handle_service_rest_translator:response(get, HServiceId, data, {ok, HService});

response(get, _UserId, {eff_handle_service, HServiceId}, {ok, HService}) ->
    handle_service_rest_translator:response(get, HServiceId, data, {ok, HService});

response(get, _UserId, handles, {ok, Handles}) ->
    rest_handler:ok_body_reply(#{<<"handles">> => Handles});

response(get, _UserId, eff_handles, {ok, Handles}) ->
    rest_handler:ok_body_reply(#{<<"handles">> => Handles});

response(get, _UserId, {handle, HandleId}, {ok, Handle}) ->
    handle_rest_translator:response(get, HandleId, data, {ok, Handle});

response(get, _UserId, {eff_handle, HandleId}, {ok, Handle}) ->
    handle_rest_translator:response(get, HandleId, data, {ok, Handle});


response(update, _UserId, _, ok) ->
    rest_handler:updated_reply();


response(delete, _UserId, _, ok) ->
    rest_handler:deleted_reply().