%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module contains definitions of all REST operations, in a
%%% format of cowboy router.
%%% @end
%%%-------------------------------------------------------------------
-module(rest_routes).
-author("Lukasz Opiola").

-include("rest.hrl").

-export([all/0]).

all() ->
    AllRoutes = lists:flatten([
        provider_routes()
    ]),
    % Convert all routes to cowboy-compliant routes
    % (rest handler module must be added as second element to the tuples)
    lists:map(fun({Path, State}) ->
        {Path, ?REST_HANDLER_MODULE, State}
    end, AllRoutes).


provider_routes() ->
    P = n_provider_logic_plugin,
    [
        {<<"/providers">>, #rest_req{methods = #{
            get => {P, undefined, list},
            post => {P, undefined, entity}
        }}},
        {<<"/providers/:id">>, #rest_req{methods = #{
            get => {P, ?BINDING(id), entity}
        }}},
        {<<"/providers/:id/users">>, #rest_req{methods = #{
            get => {P, ?BINDING(id), users}
        }}},
        {<<"/providers/:id/users/:uid">>, #rest_req{methods = #{
            get => {P, ?BINDING(id), {user, ?BINDING(uid)}}
        }}},
        {<<"/providers/:id/groups">>, #rest_req{methods = #{
            get => {P, ?BINDING(id), groups}
        }}},
        {<<"/providers/:id/groups/:gid">>, #rest_req{methods = #{
            get => {P, ?BINDING(id), {group, ?BINDING(gid)}}
        }}},
        {<<"/providers/:id/spaces">>, #rest_req{methods = #{
            get => {P, ?BINDING(id), spaces}
        }}},
        {<<"/providers/:id/spaces/:sid">>, #rest_req{methods = #{
            get => {P, ?BINDING(id), {space, ?BINDING(sid)}}
        }}},
        {<<"/provider">>, #rest_req{methods = #{
            get => {P, ?CLIENT_ID, entity},
            post => {P, undefined, entity},
            patch => {P, ?CLIENT_ID, entity},
            delete => {P, ?CLIENT_ID, entity}
        }}},
        {<<"/provider_dev">>, #rest_req{methods = #{
            post => {P, undefined, entity}
        }}},
        {<<"/provider/spaces">>, #rest_req{methods = #{
            get => {P, ?CLIENT_ID, spaces},
            post => {P, ?CLIENT_ID, spaces}
        }}},
        {<<"/provider/spaces/support">>, #rest_req{methods = #{
            post => {P, ?CLIENT_ID, entity}
        }}},
        {<<"/provider/spaces/:sid">>, #rest_req{methods = #{
            get => {P, ?CLIENT_ID, {space, ?BINDING(sid)}},
            delete => {P, ?CLIENT_ID, {space, ?BINDING(sid)}}
        }}},
        {<<"/provider/test/check_my_ip">>, #rest_req{methods = #{
            get => {P, undefined, check_my_ip}
        }}},
        {<<"/provider/test/check_my_ports">>, #rest_req{methods = #{
            post => {P, undefined, check_my_ports}
        }}}
    ].
