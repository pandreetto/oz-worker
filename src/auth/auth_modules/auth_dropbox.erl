%% ===================================================================
%% @author Lukasz Opiola
%% @copyright (C): 2014 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc: This module implements auth_module_behaviour and handles singning in
%% via Dropbox.
%% @end
%% ===================================================================
-module(auth_dropbox).
-behaviour(auth_module_behaviour).

-include_lib("ctool/include/logging.hrl").
-include("auth_common.hrl").
-include("dao/dao_types.hrl").

-define(PROVIDER_NAME, dropbox).

%% API
-export([get_redirect_url/1, validate_login/0]).


%% ====================================================================
%% API functions
%% ====================================================================

%% get_redirect_url/1
%% ====================================================================
%% @doc Returns full URL, where the user will be redirected for authorization.
%% See function specification in auth_module_behaviour.
%% @end
%% ====================================================================
-spec get_redirect_url(boolean()) -> {ok, binary()} | {error, term()}.
%% ====================================================================
get_redirect_url(ConnectAccount) ->
    try
        ParamsProplist = [
            {<<"client_id">>, auth_config:get_provider_app_id(?PROVIDER_NAME)},
            {<<"redirect_uri">>, auth_utils:local_auth_endpoint()},
            {<<"response_type">>, <<"code">>},
            {<<"state">>, auth_logic:generate_state_token(?MODULE, ConnectAccount)}
        ],
        Params = gui_utils:proplist_to_url_params(ParamsProplist),
        {ok, <<(authorize_endpoint())/binary, "?", Params/binary>>}
    catch
        Type:Message ->
            ?error_stacktrace("Cannot get redirect URL for ~p", [?PROVIDER_NAME]),
            {error, {Type, Message}}
    end.


%% validate_login/1
%% ====================================================================
%% @doc Validates login request that came back from the provider.
%% See function specification in auth_module_behaviour.
%% @end
%% ====================================================================
-spec validate_login() ->
    {ok, #oauth_account{}} | {error, term()}.
%% ====================================================================
validate_login() ->
    try
        % Retrieve URL params
        ParamsProplist = gui_ctx:get_request_params(),
        % Parse out code parameter
        Code = proplists:get_value(<<"code">>, ParamsProplist),
        % Prepare basic auth code
        AuthEncoded = base64:encode(<<(auth_config:get_provider_app_id(?PROVIDER_NAME))/binary, ":",
        (auth_config:get_provider_app_secret(?PROVIDER_NAME))/binary>>),
        % Form access token request
        NewParamsProplist = [
            {<<"code">>, <<Code/binary>>},
            {<<"grant_type">>, <<"authorization_code">>},
            {<<"redirect_uri">>, auth_utils:local_auth_endpoint()}
        ],
        % Convert proplist to params string
        Params = gui_utils:proplist_to_url_params(NewParamsProplist),
        % Send request to Dropbox endpoint
        {ok, Response} = gui_utils:https_post(access_token_endpoint(),
            [
                {"Content-Type", "application/x-www-form-urlencoded"},
                {"Authorization", "Basic " ++ gui_str:to_list(AuthEncoded)}
            ], Params),

        {struct, JSONProplist} = n2o_json:decode(Response),
        AccessToken = proplists:get_value(<<"access_token">>, JSONProplist),
        UserID = proplists:get_value(<<"uid">>, JSONProplist),

        % Send request to Dropbox endpoint
        {ok, JSON} = gui_utils:https_get(user_info_endpoint(), [{"Authorization", "Bearer " ++ gui_str:to_list(AccessToken)}]),

        % Parse received JSON
        {struct, UserInfoProplist} = n2o_json:decode(JSON),
        ProvUserInfo = #oauth_account{
            provider_id = ?PROVIDER_NAME,
            user_id = UserID,
            email_list = lists:flatten([proplists:get_value(<<"email">>, UserInfoProplist, [])]),
            name = proplists:get_value(<<"display_name">>, UserInfoProplist, <<"">>),
            login = proplists:get_value(<<"login">>, UserInfoProplist, <<"">>)
        },
        {ok, ProvUserInfo}
    catch
        Type:Message ->
            ?debug_stacktrace("Error in ~p:validate_login - ~p:~p", [?MODULE, Type, Message]),
            {error, {Type, Message}}
    end.


%% ====================================================================
%% Internal functions
%% ====================================================================

%% authorize_endpoint/0
%% ====================================================================
%% @doc Provider endpoint, where users are redirected for authorization.
%% @end
%% ====================================================================
-spec authorize_endpoint() -> binary().
%% ====================================================================
authorize_endpoint() ->
    proplists:get_value(authorize_endpoint, auth_config:get_auth_config(?PROVIDER_NAME)).


%% access_token_endpoint/0
%% ====================================================================
%% @doc Provider endpoint, where access token is aquired.
%% @end
%% ====================================================================
-spec access_token_endpoint() -> binary().
%% ====================================================================
access_token_endpoint() ->
    proplists:get_value(access_token_endpoint, auth_config:get_auth_config(?PROVIDER_NAME)).


%% user_info_endpoint/0
%% ====================================================================
%% @doc Provider endpoint, where user info is aquired.
%% @end
%% ====================================================================
-spec user_info_endpoint() -> binary().
%% ====================================================================
user_info_endpoint() ->
    proplists:get_value(user_info_endpoint, auth_config:get_auth_config(?PROVIDER_NAME)).
