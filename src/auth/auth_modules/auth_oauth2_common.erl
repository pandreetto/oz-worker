%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc: This module implements common logic for integration with standard
%%% oauth2 servers.
%%% @end
%%%-------------------------------------------------------------------
-module(auth_oauth2_common).

-include_lib("ctool/include/logging.hrl").
-include("auth_common.hrl").
-include("datastore/oz_datastore_models_def.hrl").

%% API
-export([
    get_redirect_url/3,
    validate_login/2,
    get_user_info/2, get_user_info/3
]).

%%%===================================================================
%%% API functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Returns full URL, where the user will be redirected for authorization.
%% See function specification in auth_module_behaviour.
%% @end
%%--------------------------------------------------------------------
-spec get_redirect_url(boolean(), ProviderName :: atom(),
    HandlerModule :: atom()) -> {ok, binary()} | {error, term()}.
get_redirect_url(ConnectAccount, ProviderName, HandlerModule) ->
    try
        ParamsProplist = [
            {<<"client_id">>,
                auth_config:get_provider_app_id(ProviderName)},
            {<<"response_type">>,
                <<"code">>},
            {<<"scope">>,
                <<"openid email profile">>},
            {<<"redirect_uri">>,
                auth_utils:local_auth_endpoint()},
            {<<"state">>,
                auth_logic:generate_state_token(HandlerModule, ConnectAccount)}
        ],
        Params = http_utils:proplist_to_url_params(ParamsProplist),
        AuthorizeEndpoint = authorize_endpoint(get_xrds(ProviderName)),
        {ok, <<AuthorizeEndpoint/binary, "?", Params/binary>>}
    catch
        Type:Message ->
            ?error_stacktrace("Cannot get redirect URL for ~p",
                [ProviderName]),
            {error, {Type, Message}}
    end.


%%--------------------------------------------------------------------
%% @doc Validates login request that came back from the provider.
%% See function specification in auth_module_behaviour.
%% @end
%%--------------------------------------------------------------------
-spec validate_login(ProviderName :: atom(),
    SecretSendMethod :: secret_over_http_basic | secret_over_http_post) ->
    {ok, #oauth_account{}} | {error, term()}.
validate_login(ProviderName, SecretSendMethod) ->
    try
        % Retrieve URL params
        ParamsProplist = gui_ctx:get_url_params(),
        % Parse out code parameter
        Code = proplists:get_value(<<"code">>, ParamsProplist),
        ClientId = auth_config:get_provider_app_id(ProviderName),
        ClientSecret = auth_config:get_provider_app_secret(ProviderName),
        % Form access token request
        % Check which way we should send secret - HTTP Basic or POST
        SecretPostParams = case SecretSendMethod of
            secret_over_http_post ->
                [
                    {<<"client_id">>, ClientId},
                    {<<"client_secret">>, ClientSecret}
                ];
            secret_over_http_basic ->
                []
        end,
        SecretHeaders = case SecretSendMethod of
            secret_over_http_post ->
                #{};
            secret_over_http_basic ->
                B64 = base64:encode(
                    <<ClientId/binary, ":", ClientSecret/binary>>
                ),
                #{<<"Authorization">> => <<"Basic ", B64/binary>>}
        end,
        NewParamsProplist = SecretPostParams ++ [
            {<<"code">>, Code},
            {<<"redirect_uri">>, auth_utils:local_auth_endpoint()},
            {<<"grant_type">>, <<"authorization_code">>}
        ],
        % Convert proplist to params string
        Params = http_utils:proplist_to_url_params(NewParamsProplist),
        % Prepare headers
        Headers = SecretHeaders#{
            <<"Content-Type">> => <<"application/x-www-form-urlencoded">>
        },
        % Send request to access token endpoint
        XRDS = get_xrds(ProviderName),
        {ok, 200, _, ResponseBinary} = http_client:post(
            access_token_endpoint(XRDS),
            Headers,
            Params,
            [{ssl_lib, erlang}]
        ),

        % Parse out received access token and form a user info request
        Response = json_utils:decode(ResponseBinary),
        AccessToken = proplists:get_value(<<"access_token">>, Response),

        io:format("~nT = <<\"~s\">>.~n~n", [AccessToken]),

        get_user_info(ProviderName, AccessToken, XRDS)
    catch
        Type:Message ->
            ?debug_stacktrace("Error in OpenID validate_login (~p) - ~p:~p",
                [ProviderName, Type, Message]),
            {error, {Type, Message}}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Retrieves user info for given OpenID provider and access token.
%% @end
%%--------------------------------------------------------------------
-spec get_user_info(ProviderName :: atom(), AccessToken :: binary()) ->
    {ok, #oauth_account{}} | {error, term()}.
get_user_info(ProviderName, AccessToken) ->
    XRDS = get_xrds(ProviderName),
    get_user_info(ProviderName, AccessToken, XRDS).


%%--------------------------------------------------------------------
%% @doc
%% Retrieves user info for given OpenID provider and access token.
%% Allows to specify XRDS proplist (useful when it has been already obtained to
%% avoid repeating requests).
%% @end
%%--------------------------------------------------------------------
-spec get_user_info(ProviderName :: atom(), AccessToken :: binary()) ->
    {ok, #oauth_account{}} | {error, bad_access_token}.
get_user_info(ProviderName, AccessToken, XRDS) ->
    UserInfoEndpoint = user_info_endpoint(XRDS),

    URL = <<UserInfoEndpoint/binary, "?access_token=", AccessToken/binary>>,

    % Send request to user info endpoint
    Response = http_client:get(
        URL,
        #{<<"Content-Type">> => <<"application/x-www-form-urlencoded">>},
        <<"">>,
        [{ssl_lib, erlang}]
    ),

    case Response of
        {ok, 200, _, Body} ->
            % Parse JSON with user info
            JSONProplist = json_utils:decode(Body),
            ProvUserInfo = #oauth_account{
                provider_id = ProviderName,
                user_id = auth_utils:get_value_binary(<<"sub">>, JSONProplist),
                email_list = auth_utils:extract_emails(JSONProplist),
                name = auth_utils:get_value_binary(<<"name">>, JSONProplist),
                login = auth_utils:get_value_binary(<<"login">>, JSONProplist)
            },
            {ok, ProvUserInfo};
        _ ->
            {error, bad_access_token}
    end.


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Get XRDS file and parse it. It contains entries well known configuration
%% of openid provider (endpoints etc).
%% @end
%%--------------------------------------------------------------------
-spec get_xrds(ProviderName :: atom()) -> proplists:proplist().
get_xrds(ProviderName) ->
    ProviderConfig = auth_config:get_auth_config(ProviderName),
    XRDSEndpoint = proplists:get_value(xrds_endpoint, ProviderConfig),
    Opts = [{ssl_lib, erlang}, {follow_redirect, true}, {max_redirect, 5}],
    {ok, 200, _, XRDS} = http_client:get(XRDSEndpoint, #{}, <<>>, Opts),
    json_utils:decode(XRDS).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Provider endpoint, where users are redirected for authorization.
%% @end
%%--------------------------------------------------------------------
-spec authorize_endpoint(XRDS :: proplists:proplist()) -> binary().
authorize_endpoint(XRDS) ->
    proplists:get_value(<<"authorization_endpoint">>, XRDS).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Provider endpoint, where access token is acquired.
%% @end
%%--------------------------------------------------------------------
-spec access_token_endpoint(XRDS :: proplists:proplist()) -> binary().
access_token_endpoint(XRDS) ->
    proplists:get_value(<<"token_endpoint">>, XRDS).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Provider endpoint, where user info is acquired.
%% @end
%%--------------------------------------------------------------------
-spec user_info_endpoint(XRDS :: proplists:proplist()) -> binary().
user_info_endpoint(XRDS) ->
    proplists:get_value(<<"userinfo_endpoint">>, XRDS).
