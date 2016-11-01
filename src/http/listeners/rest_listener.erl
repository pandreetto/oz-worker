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

-include("rest_config.hrl").
-include("registered_names.hrl").
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
    {ok, RestPort} = application:get_env(?APP_Name, rest_port),
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
        {ok, RestHttpsAcceptors} = application:get_env(?APP_Name, rest_https_acceptors),

        % Get cert paths
        {ok, ZoneCADir} = application:get_env(?APP_Name, ozpca_dir),
        {ok, ZoneKeyFile} = application:get_env(?APP_Name, oz_key_file),
        {ok, ZoneCertFile} = application:get_env(?APP_Name, oz_cert_file),
        {ok, ZoneCertDomain} = application:get_env(?APP_Name, http_domain),
        {ok, ZoneCaCert} = file:read_file(ozpca:cacert_path(ZoneCADir)),

        {ok, KeyFile} = application:get_env(?APP_Name, web_key_file),
        {ok, CertFile} = application:get_env(?APP_Name, web_cert_file),
        {ok, CaCertsDir} = application:get_env(?APP_Name, cacerts_dir),
        {ok, CaCerts} = file_utils:read_files({dir, CaCertsDir}),

        ozpca:start(ZoneCADir, ZoneCertFile, ZoneKeyFile, ZoneCertDomain),
        auth_logic:start(),

        Hostname = dns_query_handler:get_canonical_hostname(),
        Dispatch = cowboy_router:compile([
            % Redirect requests in form: alias.onedata.org
            {":alias." ++ Hostname, [{'_', client_redirect_handler, [RestPort]}]},
            {'_', routes()}
        ]),

        {ok, _} = ranch:start_listener(?rest_listener, RestHttpsAcceptors,
            ranch_etls, [
                {port, RestPort},
                % @todo Use gui cert files rather than certs generated by GR, since
                % we don't yet have a mechanism of distributing the CA cert.
                {keyfile, KeyFile},
                {certfile, CertFile},
                {cacerts, [ZoneCaCert | CaCerts]},
                {verify_type, verify_peer},
                {ciphers, ssl:cipher_suites() -- ssl_utils:weak_ciphers()},
                {versions, ['tlsv1.2', 'tlsv1.1']}
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
    case catch ranch:stop_listener(?rest_listener) of
        (ok) ->
            ok;
        (Error) ->
            ?error("Error on stopping listener ~p: ~p", [?rest_listener, Error]),
            {error, redirector_stop_error}
    end.


%%--------------------------------------------------------------------
%% @doc
%% {@link listener_behaviour} callback healthcheck/0.
%% @end
%%--------------------------------------------------------------------
-spec healthcheck() -> ok | {error, server_not_responding}.
healthcheck() ->
    Endpoint = "https://127.0.0.1:" ++ integer_to_list(port()),
    case http_client:get(Endpoint, [], <<>>, [insecure]) of
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
    {ok, PrefixStr} = application:get_env(?APP_Name, rest_api_prefix),
    Prefix = str_utils:to_binary(PrefixStr),
    Routes = lists:map(fun({Path, Module, InitialState}) ->
        {<<Prefix/binary, Path/binary>>, Module, InitialState}
    end, lists:append([
        identities_rest_module:routes(),
        user_rest_module:routes(),
        provider_rest_module:routes(),
        spaces_rest_module:routes(),
        shares_rest_module:routes(),
        groups_rest_module:routes(),
        handle_services_rest_module:routes(),
        handles_rest_module:routes()
    ])),
    {ok, ZoneCADir} = application:get_env(?APP_Name, ozpca_dir),
    [
        {<<"/crl.pem">>, cowboy_static, {file, filename:join(ZoneCADir, "crl.pem")}} |
        Routes
    ].
