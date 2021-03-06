%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2015 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module implements gui_route_plugin_behaviour. It decides on:
%%%   - mapping of URLs to pages (routes)
%%%   - logic and requirements on different routes
%%%   - what pages are used for login, logout, displaying errors
%%%   - what modules handles server logic of WebSocket connection with
%%%         the client (data and callback backends)
%%% @end
%%%-------------------------------------------------------------------
-module(gui_route_plugin).
-author("Lukasz Opiola").
-behaviour(gui_route_plugin_behaviour).

-include("http/gui_paths.hrl").
-include("auth_common.hrl").
-include("registered_names.hrl").
-include("datastore/oz_datastore_models.hrl").
-include_lib("gui/include/gui.hrl").
-include_lib("ctool/include/logging.hrl").

-export([route/1, data_backend/2, private_rpc_backend/0, public_rpc_backend/0]).
-export([session_details/0]).
-export([login_page_path/0, default_page_path/0]).
-export([error_404_html_file/0, error_500_html_file/0]).
-export([response_headers/0]).

%% Convenience macros for defining routes.

-define(LOGOUT, #gui_route{
    requires_session = ?SESSION_LOGGED_IN,
    html_file = undefined,
    page_backend = logout_backend
}).

-define(BASIC_LOGIN, #gui_route{
    requires_session = ?SESSION_NOT_LOGGED_IN,
    html_file = undefined,
    page_backend = basic_login_backend
}).

-define(OIDC_CONSUME_ENDPOINT, #gui_route{
    requires_session = ?SESSION_ANY,  % Can be used to log in or connect account
    html_file = undefined,
    page_backend = oidc_consume_backend
}).

-define(SAML_METADATA_BACKEND, #gui_route{
    requires_session = ?SESSION_ANY,  % Can be used to log in or connect account
    html_file = undefined,
    page_backend = saml_metadata_backend
}).

-define(SAML_CONSUME_BACKEND, #gui_route{
    requires_session = ?SESSION_ANY,  % Can be used to log in or connect account
    html_file = undefined,
    page_backend = saml_consume_backend
}).

-define(INDEX, #gui_route{
    requires_session = ?SESSION_ANY,
    websocket = ?SESSION_ANY,
    html_file = <<"index.html">>,
    page_backend = undefined
}).

-define(DEV_LOGIN, #gui_route{
    requires_session = ?SESSION_ANY,
    html_file = undefined,
    page_backend = dev_login_backend
}).

-define(VALIDATE_DEV_LOGIN, #gui_route{
    requires_session = ?SESSION_ANY,
    html_file = undefined,
    page_backend = validate_dev_login_backend
}).


%% ====================================================================
%% API
%% ====================================================================

%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback route/1.
%% @end
%%--------------------------------------------------------------------
-spec route(Path :: binary()) -> #gui_route{} | undefined.
route(<<"/do_logout">>) -> ?LOGOUT;
route(<<"/do_login">>) -> ?BASIC_LOGIN;
route(<<"/validate_login">>) -> ?OIDC_CONSUME_ENDPOINT;
route(<<?SAML_METADATA_PATH>>) -> ?SAML_METADATA_BACKEND;
route(<<?SAML_CONSUME_PATH>>) -> ?SAML_CONSUME_BACKEND;
route(<<"/dev_login">>) ->
    case oz_worker:get_env(dev_mode) of
        {ok, true} ->
            ?DEV_LOGIN;
        _ ->
            ?INDEX
    end;
route(<<"/validate_dev_login">>) ->
    case oz_worker:get_env(dev_mode) of
        {ok, true} ->
            ?VALIDATE_DEV_LOGIN;
        _ ->
            ?INDEX
    end;
route(<<"/">>) -> ?INDEX;
route(<<"/index.html">>) -> ?INDEX;
% Ember-style URLs also point to index file
route(<<"/#/", _/binary>>) -> ?INDEX;
route(_) -> undefined.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback data_backend/2
%% @end
%%--------------------------------------------------------------------
-spec data_backend(HasSession :: boolean(), Identifier :: binary()) ->
    HandlerModule :: module().
data_backend(true, <<"user">>) -> user_data_backend;
data_backend(true, <<"clienttoken">>) -> client_token_data_backend;
data_backend(true, <<"space">>) -> space_data_backend;
data_backend(true, <<"group">>) -> group_data_backend;
data_backend(true, <<"provider">>) -> provider_data_backend.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback private_rpc_backend/0
%% @end
%%--------------------------------------------------------------------
private_rpc_backend() -> private_rpc_backend.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback public_rpc_backend/0
%% @end
%%--------------------------------------------------------------------
public_rpc_backend() -> public_rpc_backend.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback get_session_details/0
%% @end
%%--------------------------------------------------------------------
-spec session_details() ->
    {ok, proplists:proplist()} | gui_error:error_result().
session_details() ->
    {_AppId, _AppName, AppVersion} = lists:keyfind(
        ?APP_NAME, 1, application:loaded_applications()
    ),
    Res = [
        {<<"userId">>, gui_session:get_user_id()},
        {<<"serviceVersion">>, str_utils:to_binary(AppVersion)}
    ],
    {ok, Res}.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback login_page_path/0
%% @end
%%--------------------------------------------------------------------
-spec login_page_path() -> Path :: binary().
login_page_path() ->
    <<"/login">>.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback default_page_path/0
%% @end
%%--------------------------------------------------------------------
-spec default_page_path() -> Path :: binary().
default_page_path() ->
    <<"/">>.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback error_404_html_file/0
%% @end
%%--------------------------------------------------------------------
-spec error_404_html_file() -> FileName :: binary().
error_404_html_file() ->
    <<"page404.html">>.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback error_500_html_file/0
%% @end
%%--------------------------------------------------------------------
-spec error_500_html_file() -> FileName :: binary().
error_500_html_file() ->
    <<"page500.html">>.


%%--------------------------------------------------------------------
%% @doc
%% {@link gui_route_plugin_behaviour} callback response_headers/0
%% @end
%%--------------------------------------------------------------------
-spec response_headers() -> [{Key :: binary(), Value :: binary()}].
response_headers() ->
    {ok, Headers} = oz_worker:get_env(gui_response_headers),
    Headers.
