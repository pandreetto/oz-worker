%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module handles translation of system errors into REST responses.
%%% @end
%%%-------------------------------------------------------------------
-module(handle_service_rest_translator).
-author("Lukasz Opiola").

-include("rest.hrl").
-include("errors.hrl").
-include("datastore/oz_datastore_models_def.hrl").
-include("registered_names.hrl").
-include_lib("ctool/include/logging.hrl").

-export([response/4]).

% TODO VFS-2918
response(create, _HServiceId, {deprecated_user_privileges, _UserId}, ok) ->
    n_rest_handler:ok_no_content_reply();
% TODO VFS-2918
response(create, _HServiceId, {deprecated_child_privileges, _GroupId}, ok) ->
    n_rest_handler:ok_no_content_reply();

response(create, undefined, entity, {ok, HServiceId}) ->
    n_rest_handler:created_reply([<<"handle_services">>, HServiceId]);

response(create, HServiceId, users, {ok, UserId}) ->
    n_rest_handler:created_reply(
        [<<"handle_services">>, HServiceId, <<"users">>, UserId]
    );

response(create, HServiceId, groups, {ok, GroupId}) ->
    n_rest_handler:created_reply(
        [<<"handle_services">>, HServiceId, <<"groups">>, GroupId]
    );

response(get, HServiceId, data, {ok, HServiceData}) ->
    n_rest_handler:ok_body_reply(HServiceData#{<<"handle_serviceId">> => HServiceId});

response(get, undefined, list, {ok, HServices}) ->
    n_rest_handler:ok_body_reply(#{<<"handle_services">> => HServices});

response(get, _HServiceId, users, {ok, Users}) ->
    n_rest_handler:ok_body_reply(#{<<"users">> => Users});

response(get, _HServiceId, eff_users, {ok, Users}) ->
    n_rest_handler:ok_body_reply(#{<<"users">> => Users});

response(get, _HServiceId, {user, UserId}, {ok, User}) ->
    user_rest_translator:response(get, UserId, data, {ok, User});

response(get, _HServiceId, {eff_user, UserId}, {ok, User}) ->
    user_rest_translator:response(get, UserId, data, {ok, User});

response(get, _HServiceId, {user_privileges, _UserId}, {ok, Privileges}) ->
    n_rest_handler:ok_body_reply(#{<<"privileges">> => Privileges});

response(get, _HServiceId, {eff_user_privileges, _UserId}, {ok, Privileges}) ->
    n_rest_handler:ok_body_reply(#{<<"privileges">> => Privileges});

response(get, _HServiceId, groups, {ok, Groups}) ->
    n_rest_handler:ok_body_reply(#{<<"groups">> => Groups});

response(get, _HServiceId, eff_groups, {ok, Groups}) ->
    n_rest_handler:ok_body_reply(#{<<"groups">> => Groups});

response(get, _HServiceId, {group, GroupId}, {ok, Group}) ->
    group_rest_translator:response(get, GroupId, data, {ok, Group});

response(get, _HServiceId, {eff_group, GroupId}, {ok, Group}) ->
    group_rest_translator:response(get, GroupId, data, {ok, Group});

response(get, _HServiceId, {group_privileges, _GroupId}, {ok, Privileges}) ->
    n_rest_handler:ok_body_reply(#{<<"privileges">> => Privileges});

response(get, _HServiceId, {eff_group_privileges, _GroupId}, {ok, Privileges}) ->
    n_rest_handler:ok_body_reply(#{<<"privileges">> => Privileges});

response(get, _HServiceId, handles, {ok, Handles}) ->
    n_rest_handler:ok_body_reply(#{<<"handles">> => Handles});

response(get, _HServiceId, {handle, HandleId}, {ok, Handle}) ->
    handle_rest_translator:response(get, HandleId, data, {ok, Handle});


response(update, _HServiceId, _, ok) ->
    n_rest_handler:updated_reply();


response(delete, _HServiceId, _, ok) ->
    n_rest_handler:deleted_reply().