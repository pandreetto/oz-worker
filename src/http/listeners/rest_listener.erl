%%%--------------------------------------------------------------------
%%% @author Michal Zmuda
%%% @copyright (C) 2015 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%--------------------------------------------------------------------
%%% @doc This module is responsible for REST listener starting and stopping.
%%% @end
%%%--------------------------------------------------------------------
-module(rest_listener).
-author("Michal Zmuda").

-include("rest.hrl").
-include("registered_names.hrl").
-include("graph_sync/oz_graph_sync.hrl").
-include_lib("ctool/include/logging.hrl").

-behaviour(listener_behaviour).

%% listener_behaviour callbacks
-export([port/0, start/0, stop/0, healthcheck/0]).

%% API
-export([routes/0]).

%%%===================================================================
%%% listener_behaviour callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% {@link listener_behaviour} callback port/0.
%% @end
%%--------------------------------------------------------------------
-spec port() -> integer().
port() ->
    {ok, RestPort} = application:get_env(?APP_NAME, rest_port),
    RestPort.


%%--------------------------------------------------------------------
%% @doc
%% {@link listener_behaviour} callback start/0.
%% @end
%%--------------------------------------------------------------------
-spec start() -> ok | {error, Reason :: term()}.
start() ->
    try
        % Get rest config
        RestPort = port(),
        {ok, RestHttpsAcceptors} = application:get_env(?APP_NAME, rest_https_acceptors),


        % Get cert paths
        {ok, KeyFile} = application:get_env(?APP_NAME, web_key_file),
        {ok, CertFile} = application:get_env(?APP_NAME, web_cert_file),
        {ok, CaCertsDir} = application:get_env(?APP_NAME, cacerts_dir),
        ZoneCaCertDer = cert_utils:load_der(ozpca:oz_ca_path()),
        CaCerts = [ZoneCaCertDer | cert_utils:load_ders_in_dir(CaCertsDir)],

        auth_logic:start(),

%%        {ok, Hostname} = application:get_env(oz_worker, http_domain),
        Dispatch = cowboy_router:compile([
            % TODO VFS-2873 Currently unused
            % Redirect requests in form: alias.onedata.org
%%            {":alias." ++ Hostname, [{'_', client_redirect_handler, [RestPort]}]},
            {'_', [
                {?GRAPH_SYNC_WS_PATH ++ "[...]", gs_ws_handler, [provider_gs_translator]}
            ] ++ routes()}
        ]),

        {ok, _} = ranch:start_listener(?REST_LISTENER, RestHttpsAcceptors,
            ranch_ssl, [
                {port, RestPort},
                {keyfile, KeyFile},
                {certfile, CertFile},
                {cacerts, CaCerts},
                {verify, verify_peer},
                {ciphers, ssl:cipher_suites() -- ssl_utils:weak_ciphers()}
            ], cowboy_protocol,
            [
                {env, [{dispatch, Dispatch}]}
            ]),
        ok
    catch
        _Type:Error ->
            ?error_stacktrace("Could not start rest, error: ~p", [Error]),
            {error, Error}
    end.

%%--------------------------------------------------------------------
%% @doc
%% {@link listener_behaviour} callback stop/0.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, Reason :: term()}.
stop() ->
    case catch ranch:stop_listener(?REST_LISTENER) of
        (ok) ->
            ok;
        (Error) ->
            ?error("Error on stopping listener ~p: ~p", [?REST_LISTENER, Error]),
            {error, redirector_stop_error}
    end.


%%--------------------------------------------------------------------
%% @doc
%% {@link listener_behaviour} callback healthcheck/0.
%% @end
%%--------------------------------------------------------------------
-spec healthcheck() -> ok | {error, server_not_responding}.
healthcheck() ->
    Endpoint = str_utils:format_bin("https://127.0.0.1:~B", [port()]),
    {ok, CaCertsDir} = application:get_env(?APP_NAME, cacerts_dir),
    CaCerts = cert_utils:load_ders_in_dir(CaCertsDir),
    Opts = [{ssl_options, [{secure, only_verify_peercert}, {cacerts, CaCerts}]}],
    case http_client:get(Endpoint, #{}, <<>>, Opts) of
        {ok, _, _, _} -> ok;
        _ -> {error, server_not_responding}
    end.

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Returns a Cowboy-understandable PathList of routes.
%% @end
%%--------------------------------------------------------------------
-spec routes() -> [{Path :: binary(), Module :: module(), State :: term()}].
routes() ->
    [
        {<<"/crl.pem">>, cowboy_static, {file, ozpca:crl_path()}} |
        rest_handler:rest_routes()
    ].
