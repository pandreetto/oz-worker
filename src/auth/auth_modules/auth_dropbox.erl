%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2014 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc: This module implements auth_module_behaviour and handles signing in
%%% via Dropbox OpenID.
%%% @end
%%%-------------------------------------------------------------------
-module(auth_dropbox).
-behaviour(auth_module_behaviour).

-include_lib("ctool/include/logging.hrl").
-include("auth_common.hrl").
-include("datastore/oz_datastore_models.hrl").

-define(IDENTITY_PROVIDER, dropbox).

%% API
-export([get_redirect_url/1, validate_login/0, get_user_info/1]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Returns full URL, where the user will be redirected for authorization.
%% See function specification in auth_module_behaviour.
%% @end
%%--------------------------------------------------------------------
-spec get_redirect_url(boolean()) -> {ok, binary()} | {error, term()}.
get_redirect_url(ConnectAccount) ->
    try
        ParamsProplist = [
            {<<"client_id">>, auth_config:get_provider_app_id(?IDENTITY_PROVIDER)},
            {<<"redirect_uri">>, auth_utils:local_auth_endpoint()},
            {<<"response_type">>, <<"code">>},
            {<<"state">>, auth_logic:generate_state_token(?MODULE, ConnectAccount)}
        ],
        Params = http_utils:proplist_to_url_params(ParamsProplist),
        {ok, <<(authorize_endpoint())/binary, "?", Params/binary>>}
    catch
        Type:Message ->
            ?error_stacktrace("Cannot get redirect URL for ~p", [?IDENTITY_PROVIDER]),
            {error, {Type, Message}}
    end.

%%--------------------------------------------------------------------
%% @doc Validates login request that came back from the provider.
%% See function specification in auth_module_behaviour.
%% @end
%%--------------------------------------------------------------------
-spec validate_login() ->
    {ok, #linked_account{}} | {error, term()}.
validate_login() ->
    try
        % Retrieve URL params
        ParamsProplist = gui_ctx:get_url_params(),
        % Parse out code parameter
        Code = proplists:get_value(<<"code">>, ParamsProplist),
        % Prepare basic auth code
        AuthEncoded = base64:encode(<<(auth_config:get_provider_app_id(?IDENTITY_PROVIDER))/binary, ":",
            (auth_config:get_provider_app_secret(?IDENTITY_PROVIDER))/binary>>),
        % Form access token request
        NewParamsProplist = [
            {<<"code">>, <<Code/binary>>},
            {<<"grant_type">>, <<"authorization_code">>},
            {<<"redirect_uri">>, auth_utils:local_auth_endpoint()}
        ],
        % Convert proplist to params string
        Params = http_utils:proplist_to_url_params(NewParamsProplist),
        % Send request to Dropbox endpoint
        {ok, 200, _, Response} = http_client:post(access_token_endpoint(), #{
            <<"Content-Type">> => <<"application/x-www-form-urlencoded">>,
            <<"Authorization">> => <<"Basic ", AuthEncoded/binary>>
        }, Params),

        JSONProplist = json_utils:decode(Response),
        AccessToken = proplists:get_value(<<"access_token">>, JSONProplist),

        get_user_info(AccessToken)
    catch
        Type:Message ->
            ?debug_stacktrace("Error in ~p:validate_login - ~p:~p", [?MODULE, Type, Message]),
            {error, {Type, Message}}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Retrieves user info from oauth provider based on access token.
%% @end
%%--------------------------------------------------------------------
-spec get_user_info(AccessToken :: binary()) ->
    {ok, #linked_account{}} | {error, bad_access_token}.
get_user_info(AccessToken) ->
    % Send request to Dropbox endpoint
    {ok, 200, _, JSON} = http_client:get(user_info_endpoint(), #{
        <<"Authorization">> => <<"Bearer ", AccessToken/binary>>
    }, <<"">>),

    % Parse received JSON
    UserInfoProplist = json_utils:decode(JSON),
    ProvUserInfo = #linked_account{
        idp = ?IDENTITY_PROVIDER,
        subject_id = auth_utils:get_value_binary(<<"uid">>, UserInfoProplist),
        email_list = auth_utils:extract_emails(UserInfoProplist),
        name = auth_utils:get_value_binary(<<"display_name">>, UserInfoProplist),
        login = auth_utils:get_value_binary(<<"login">>, UserInfoProplist),
        groups = []
    },
    {ok, ProvUserInfo}.


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc Provider endpoint, where users are redirected for authorization.
%% @end
%%--------------------------------------------------------------------
-spec authorize_endpoint() -> binary().
authorize_endpoint() ->
    proplists:get_value(authorize_endpoint, auth_config:get_auth_config(?IDENTITY_PROVIDER)).

%%--------------------------------------------------------------------
%% @private
%% @doc Provider endpoint, where access token is acquired.
%% @end
%%--------------------------------------------------------------------
-spec access_token_endpoint() -> binary().
access_token_endpoint() ->
    proplists:get_value(access_token_endpoint, auth_config:get_auth_config(?IDENTITY_PROVIDER)).

%%--------------------------------------------------------------------
%% @private
%% @doc Provider endpoint, where user info is acquired.
%% @end
%%--------------------------------------------------------------------
-spec user_info_endpoint() -> binary().
user_info_endpoint() ->
    proplists:get_value(user_info_endpoint, auth_config:get_auth_config(?IDENTITY_PROVIDER)).
