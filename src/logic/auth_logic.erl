%% ===================================================================
%% @author Konrad Zemek
%% @copyright (C): 2014 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc The module implementing the business logic for OpenID Connect end-user
%% authentication and authorization.
%% @end
%% ===================================================================
-module(auth_logic).
-author("Konrad Zemek").

-include("dao/dao_types.hrl").
-include("auth_common.hrl").
-include_lib("ctool/include/logging.hrl").

-define(AUTH_CODE, aUTH_CODE).
-define(ACCESS_TOKEN, access_token).
-define(REFRESH_TOKEN, refresh_token).
-define(STATE_TOKEN, state_token).

-define(TABLES, [?AUTH_CODE, ?ACCESS_TOKEN, ?REFRESH_TOKEN, ?STATE_TOKEN]).

%% @todo: config
-define(AUTH_CODE_EXPIRATION_SECS, 600).
-define(ACCESS_TOKEN_EXPIRATION_SECS, 36000).
-define(REFRESH_TOKEN_EXPIRATION_SECS, 36000).
-define(STATE_TOKEN_EXPIRATION_SECS, 60).
-define(ISSUER_URL, "https://onedata.org").


%% ====================================================================
%% API
%% ====================================================================
-export([start/0, stop/0, get_redirection_uri/2, grant_token/2, validate_token/2]).

%% ====================================================================
%% Handling state tokens
%% ====================================================================
-export([generate_state_token/2, lookup_state_token/1, clear_expired_tokens/0]).


%% ====================================================================
%% API functions
%% ====================================================================


%% start/0
%% ====================================================================
%% @doc Initializes temporary storage for OpenID tokens.
%% ====================================================================
-spec start() -> ok.
%% ====================================================================
start() ->
    lists:foreach(fun(Table) -> ets:new(Table, [named_table, public]) end, ?TABLES),
    ok.


%% stop/0
%% ====================================================================
%% @doc Deinitializes temporary storage for OpenID tokens.
%% ====================================================================
-spec stop() -> ok.
%% ====================================================================
stop() ->
    lists:foreach(fun(Table) -> ets:delete(Table) end, ?TABLES),
    ok.


%% get_redirection_uri/2
%% ====================================================================
%% @doc Returns provider hostname and a full URI to which the user should be redirected from
%% the global registry. The redirection is part of the OpenID flow and the URI
%% contains an Authorization token. The provider hostname is useful to check connectivity
%% before redirecting.
%% @end
%% ====================================================================
-spec get_redirection_uri(UserId :: binary(), ProviderId :: binary()) ->
    {ProviderHostname :: binary(), RedirectionUri :: binary()}.
%% ====================================================================
get_redirection_uri(UserId, ProviderId) ->
    AuthCode = random_token(),
    ExpirationTime = now_s() + ?AUTH_CODE_EXPIRATION_SECS,
    ets:insert(?AUTH_CODE, {AuthCode, {ProviderId, UserId, ExpirationTime}}),
    {ok, ProviderData} = provider_logic:get_data(ProviderId),
    {redirectionPoint, RedirectURL} = lists:keyfind(redirectionPoint, 1, ProviderData),
    {RedirectURL, <<RedirectURL/binary, ?provider_auth_endpoint, "?code=", AuthCode/binary>>}.


%% grant_token/2
%% ====================================================================
%% @doc Grants ID, Access and Refresh tokens to the provider identifying
%% itself with a valid Authorization token.
%% @end
%% ====================================================================
-spec grant_token(ProviderId :: binary(), AuthCode :: binary()) ->
    [proplists:property()].
%% ====================================================================
grant_token(ProviderId, AuthCode) ->
    [{AuthCode, {ProviderId, UserId, _ExpirationTime}}] = ets:lookup(?AUTH_CODE, AuthCode),
    ets:delete(?AUTH_CODE, AuthCode),

    AccessToken = random_token(),
    RefreshToken = random_token(),
    AccessTokenExpirationTime = now_s() + ?ACCESS_TOKEN_EXPIRATION_SECS,
    RefreshTokenExpirationTime = now_s() + ?REFRESH_TOKEN_EXPIRATION_SECS,
    ets:insert(?ACCESS_TOKEN, {AccessToken, {ProviderId, UserId, AccessTokenExpirationTime}}),
    ets:insert(?REFRESH_TOKEN, {RefreshToken, {ProviderId, UserId, RefreshTokenExpirationTime}}),

    {ok, #user{name = Name, email_list = Emails}} = user_logic:get_user(UserId),
    EmailsList = lists:map(fun(Email) -> {struct, [{email, Email}]} end, Emails),
    [
        {access_token, AccessToken},
        {token_type, bearer},
        {expires_in, ?ACCESS_TOKEN_EXPIRATION_SECS},
        {refresh_token, RefreshToken},
        {scope, openid},
        {id_token, jwt_encode([
            {iss, ?ISSUER_URL},
            {sub, UserId},
            {aud, ProviderId},
            {name, Name},
            {email, EmailsList},
            {exp, wut}, %% @todo: expiration time
            {iat, now} %% @todo: now
        ])}
    ].


%% @todo:
%% validate_authorization_request(ProviderId, AuthCode) ->
%%     SavedData = ets:lookup(?AUTH_CODE, AuthCode),
%%     validate_authorization_request(ProviderId, AuthCode, SavedData).
%%
%% validate_authorization_request(ProviderId, AuthCode, []) -> [{error, invalid_grant}];
%% validate_authorization_request(ProviderId, AuthCode, [{IntendedProviderId, UserId}])
%%     when IntendedProviderId =/= ProviderId -> [{error, invalid_request}]


%% validate_token/2
%% ====================================================================
%% @doc Validates an access token for a Provider and returns a UserId of the
%% user who authorized the Provider.
%% @end
%% ====================================================================
-spec validate_token(ProviderId :: binary(), AccessToken :: binary()) ->
    UserId :: binary() | no_return().
%% ====================================================================
validate_token(ProviderId, AccessToken) ->
    [{AccessToken, {ProviderId, UserId, _ExpirationTime}}] = ets:lookup(?ACCESS_TOKEN, AccessToken),
    UserId.


%% generate_state_token/2
%% ====================================================================
%% @doc Generates a state token and retuns it. In the process, it stores the token
%% and associates some login info, that can be later retrieved given the token.
%% For example, where to redirect the user after login.
%% @end
-spec generate_state_token(HandlerModule :: atom(), ConnectAccount :: boolean()) -> [tuple()] | error.
%% ====================================================================
generate_state_token(HandlerModule, ConnectAccount) ->
    clear_expired_tokens(),
    Token = random_token(),
    {M, S, N} = now(),
    Time = M * 1000000000000 + S * 1000000 + N,

    RedirectAfterLogin = case gui_ctx:url_param(<<"x">>) of
                             undefined -> <<"/">>;
                             TargetPage -> TargetPage
                         end,

    StateInfo = [
        {module, HandlerModule},
        {connect_account, ConnectAccount},
        {redirect_after_login, RedirectAfterLogin},
        % PROBABLY DEVELOPER-ONLY FUNCTIONALITY
        % If this value was set on login page, the user will be redirected to
        % this certain provider if he click "go to your files"
        {referer, gui_ctx:get(referer)}
    ],

    ets:insert(?STATE_TOKEN, {Token, Time, StateInfo}),
    Token.


%% lookup_state_token/1
%% ====================================================================
%% @doc Checks if the given state token exists and returns login info
%% associated with it or error otherwise.
%% @end
-spec lookup_state_token(Token :: binary()) -> [tuple()] | error.
%% ====================================================================
lookup_state_token(Token) ->
    clear_expired_tokens(),
    case ets:lookup(?STATE_TOKEN, Token) of
        [{Token, Time, LoginInfo}] ->
            ets:delete_object(?STATE_TOKEN, {Token, Time, LoginInfo}),
            LoginInfo;
        _ ->
            error
    end.


%% clear_expired_tokens/0
%% ====================================================================
%% @doc Removes all state tokens that are no longer valid from ETS.
%% @end
-spec clear_expired_tokens() -> ok.
%% ====================================================================
clear_expired_tokens() ->
    {M, S, N} = now(),
    Now = M * 1000000000000 + S * 1000000 + N,

    ExpiredSessions = ets:select(?STATE_TOKEN, [{{'$1', '$2', '$3'}, [{'<', '$2', Now - (?STATE_TOKEN_EXPIRATION_SECS * 1000000)}], ['$_']}]),
    lists:foreach(
        fun({Token, Time, LoginInfo}) ->
            ets:delete_object(?STATE_TOKEN, {Token, Time, LoginInfo})
        end, ExpiredSessions).


%% ====================================================================
%% Internal functions
%% ====================================================================


%% jwt_encode/1
%% ====================================================================
%% @doc Encodes OpenID claims as an unsigned, unencrypted
%% <a href="tools.ietf.org/html/draft-ietf-oauth-json-web-token">JWT</a>
%% structure.
%% @end
%% ====================================================================
-spec jwt_encode(Claims :: [proplists:property()]) -> JWT :: binary().
%% ====================================================================
jwt_encode(Claims) ->
    Header = mochijson2:encode([{typ, 'JWT'}, {alg, none}]),
    Payload = mochijson2:encode(Claims),
    Header64 = mochiweb_base64url:encode(Header),
    Payload64 = mochiweb_base64url:encode(Payload),
    <<Header64/binary, ".", Payload64/binary, ".">>.


%% random_token/0
%% ====================================================================
%% @doc Generates a globally unique random token.
%% ====================================================================
-spec random_token() -> binary().
%% ====================================================================
random_token() ->
    binary:list_to_bin(
        mochihex:to_hex(
            crypto:hash(sha,
                term_to_binary({make_ref(), node(), now()})))).


%% now_s/0
%% ====================================================================
%% @doc Returns the time in seconds since epoch.
%% ====================================================================
-spec now_s() -> integer().
%% ====================================================================
now_s() ->
    {MegaSecs, Secs, _} = erlang:now(),
    MegaSecs * 1000000 + Secs.
