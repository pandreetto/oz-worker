%% ===================================================================
%% @author Lukasz Opiola
%% @copyright (C): 2014 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc: This module provides functionalities used in authentication flow
%% and convenience functions that can be used from auth modules.
%% @end
%% ===================================================================
-module(auth_utils).

-include("logging.hrl").
-include("dao/dao_types.hrl").
-include("auth_common.hrl").
-include_lib("ibrowse/include/ibrowse.hrl").

%% API
-export([proplist_to_params/1, fully_qualified_url/1, normalize_email/1]).

-export([local_auth_endpoint/0, validate_login/0]).

-export([load_auth_config/0, get_auth_config/1, get_auth_providers/0]).

-export([init_state_memory/0, generate_state_token/2, lookup_state_token/1, clear_expired_tokens/0, generate_uuid/0]).

-export([get_provider_module/1, get_provider_app_id/1, get_provider_app_secret/1, get_provider_name/1]).
-export([get_provider_button_icon/1, get_provider_button_color/1]).

-define(STATE_TTL, 60).
-define(STATE_ETS, auth_state_ets).


proplist_to_params(List) ->
    lists:foldl(
        fun(Tuple, Acc) ->
            {KeyEncoded, ValueEncoded} = case Tuple of
                                             {Key, Value, no_encode} ->
                                                 {Key, Value};
                                             {Key, Value} ->
                                                 {gui_utils:to_binary(wf:url_encode(Key)),
                                                     gui_utils:to_binary(wf:url_encode(Value))}
                                         end,
            Suffix = case Acc of
                         <<"">> -> <<"">>;
                         _ -> <<Acc/binary, "&">>
                     end,
            <<Suffix/binary, KeyEncoded/binary, "=", ValueEncoded/binary>>
        end, <<"">>, List).


fully_qualified_url(Binary) ->
    case Binary of
        <<"https://www.", Rest/binary>> -> <<"https://", Rest/binary>>;
        <<"https://", _/binary>> -> Binary;
        <<"www.", Rest/binary>> -> <<"https://", Rest/binary>>;
        _ -> <<"https://", Binary/binary>>
    end.


normalize_email(Email) ->
    case binary:split(Email, [<<"@">>], [global]) of
        [Account, Domain] ->
            <<(binary:replace(Account, <<".">>, <<"">>, [global]))/binary, "@", Domain/binary>>;
        _ ->
            Email
    end.


local_auth_endpoint() ->
    <<(auth_utils:fully_qualified_url(gui_utils:get_requested_hostname()))/binary, ?local_auth_endpoint>>.


validate_login() ->
    try
        % Check url params for state parameter
        ParamsProplist = gui_utils:get_request_params(),
        State = proplists:get_value(<<"state">>, ParamsProplist),
        StateInfo = auth_utils:lookup_state_token(State),
        case StateInfo of
            error ->
                % This state token was not generated by us, invalid
                ?alert("Security breach attempt spotted. Request params:~n~p", [ParamsProplist]),
                {error, ?error_auth_invalid_request};

            Props ->
                % State token ok, get handler module and redirect address connected with this request
                Module = proplists:get_value(module, Props),
                Redirect = proplists:get_value(redirect_after_login, Props),
                % Validate the request and gather user info
                case Module:validate_login(proplists:delete(<<"state">>, ParamsProplist)) of
                    {error, Reason} ->
                        % The request could not be validated
                        ?alert("Security breach attempt spotted. Reason:~p~nRequest params:~n~p", [Reason, ParamsProplist]),
                        {error, ?error_auth_invalid_request};

                    {ok, OriginalOAuthAccount = #oauth_account{provider_id = ProviderID, user_id = UserID, email_list = OriginalEmails, name = Name}} ->
                        Emails = lists:map(fun(Email) -> auth_utils:normalize_email(Email) end, OriginalEmails),
                        OAuthAccount = OriginalOAuthAccount#oauth_account{email_list = Emails},
                        case proplists:get_value(connect_account, Props) of
                            false ->
                                % Standard login, check if there is an account belonging to the user
                                case user_logic:get_user({connected_account_user_id, {ProviderID, UserID}}) of
                                    {ok, #veil_document{uuid = UserIdString}} ->
                                        UserId = list_to_binary(UserIdString),
                                        % The account already exists
                                        wf:user(UserId),
                                        {redirect, Redirect};
                                    _ ->
                                        % Error
                                        % This is a first login
                                        % Check if any of emails is in use
                                        EmailUsed = lists:foldl(
                                            fun(Email, Acc) ->
                                                case Acc of
                                                    true -> true;
                                                    _ ->
                                                        case user_logic:get_user({email, Email}) of
                                                            {ok, _} -> true;
                                                            _ -> false
                                                        end
                                                end
                                            end, false, Emails),

                                        case EmailUsed of
                                            true ->
                                                % At least one email is in database, cannot create account
                                                {error, ?error_auth_new_email_occupied};
                                            false ->
                                                % All email are available, proceed
                                                UserInfo = #user{email_list = Emails, name = Name, connected_accounts = [
                                                    OAuthAccount
                                                ]},
                                                {ok, UserId} = user_logic:create(UserInfo),
                                                wf:user(UserId),
                                                new_user
                                        end
                                end;

                            true ->
                                % Account adding flow
                                % Check if this account isn't connected to other profile
                                case user_logic:get_user({connected_account_user_id, {ProviderID, UserID}}) of
                                    {ok, _} ->
                                        % The account is used on some other profile, cannot proceed
                                        {error, ?error_auth_account_already_connected};
                                    _ ->
                                        % Not found, ok
                                        % Check if any of emails is in use
                                        EmailUsed = lists:foldl(
                                            fun(Email, Acc) ->
                                                case Acc of
                                                    true -> true;
                                                    _ ->
                                                        case user_logic:get_user({email, Email}) of
                                                            {ok, _} -> true;
                                                            _ -> false
                                                        end
                                                end
                                            end, false, Emails),

                                        case EmailUsed of
                                            true ->
                                                % At least one email is in database, cannot create account
                                                {error, ?error_auth_connect_email_occupied};
                                            false ->
                                                % Everything ok, get the user and add new provider info
                                                UserId = wf:user(),
                                                {ok, #veil_document{record = UserRecord}} = user_logic:get_user(UserId),
                                                ModificationProplist = merge_connected_accounts(OAuthAccount, UserRecord),
                                                user_logic:modify(UserId, ModificationProplist),
                                                {redirect, <<"/manage_account">>}
                                        end
                                end
                        end
                end
        end
    catch
        T:M ->
            ?error_stacktrace("Error in validate_login - ~p:~p", [T, M]),
            {error, ?error_auth_invalid_request}
    end.

merge_connected_accounts(OAuthAccount, UserInfo) ->
    #user{name = Name, email_list = Emails, connected_accounts = ConnectedAccounts} = UserInfo,
    #oauth_account{name = ProvName, email_list = ConnAccEmails} = OAuthAccount,
    % If no name is specified, take the one provided with new info
    NewName = case Name of
                  <<"">> -> ProvName;
                  _ -> Name
              end,
    % Add emails from provider that are not yet added to account
    NewEmails = lists:foldl(
        fun(Email, Acc) ->
            case lists:member(Email, Acc) of
                true -> Acc;
                false -> Acc ++ [Email]
            end
        end, Emails, ConnAccEmails),
    [
        {name, NewName},
        {email_list, NewEmails},
        {connected_accounts, ConnectedAccounts ++ [OAuthAccount]}
    ].


init_state_memory() ->
    ets:new(?STATE_ETS, [named_table, public, bag, {read_concurrency, true}]),
    ok.


generate_state_token(HandlerModule, ConnectAccount) ->
    clear_expired_tokens(),
    {Token, Time} = generate_uuid(),

    RedirectAfterLogin = case wf:q(<<"x">>) of
                             undefined -> <<"/">>;
                             TargetPage -> TargetPage
                         end,

    StateInfo = [
        {module, HandlerModule},
        {connect_account, ConnectAccount},
        {redirect_after_login, RedirectAfterLogin}
    ],

    ets:insert(?STATE_ETS, {Token, Time, StateInfo}),
    Token.

generate_uuid() ->
    {A_SEED, B_SEED, C_SEED} = now(),
    L_SEED = atom_to_list(node()),
    {_, Sum_SEED} = lists:foldl(fun(Elem_SEED, {N_SEED, Acc_SEED}) ->
        {N_SEED * 137, Acc_SEED + Elem_SEED * N_SEED} end, {1, 0}, L_SEED),
    random:seed(Sum_SEED * 10000 + A_SEED, B_SEED, C_SEED),
    {M, S, N} = now(),
    Time = M * 1000000000000 + S * 1000000 + N,
    TimeHex = string:right(integer_to_list(Time, 16), 14, $0),
    Rand = [lists:nth(1, integer_to_list(random:uniform(16) - 1, 16)) || _ <- lists:seq(1, 18)],
    UUID = list_to_binary(string:to_lower(string:concat(TimeHex, Rand))),
    {UUID, Time}.


lookup_state_token(Token) ->
    clear_expired_tokens(),
    case ets:lookup(?STATE_ETS, Token) of
        [{Token, Time, LoginInfo}] ->
            ets:delete_object(?STATE_ETS, {Token, Time, LoginInfo}),
            LoginInfo;
        _ ->
            error
    end.


clear_expired_tokens() ->
    {M, S, N} = now(),
    Time = M * 1000000000000 + S * 1000000 + N,
    ets:select_delete(?STATE_ETS, [{{'$1', '$2', '$3'}, [{'<', '$2', Time - (?STATE_TTL * 1000000)}], ['$_']}]).


load_auth_config() ->
    {ok, [Config]} = file:consult("gui_static/auth.config"),
    application:set_env(veil_cluster_node, auth_config, Config).


get_auth_providers() ->
    {ok, Config} = application:get_env(veil_cluster_node, auth_config),
    lists:map(
        fun({Provider, _}) ->
            Provider
        end, Config).


get_auth_config(Provider) ->
    {ok, Config} = application:get_env(veil_cluster_node, auth_config),
    proplists:get_value(Provider, Config).


get_provider_module(Provider) ->
    proplists:get_value(auth_module, get_auth_config(Provider)).


get_provider_app_id(Provider) ->
    proplists:get_value(app_id, get_auth_config(Provider)).


get_provider_app_secret(Provider) ->
    proplists:get_value(app_secret, get_auth_config(Provider)).


get_provider_name(Provider) ->
    proplists:get_value(name, get_auth_config(Provider)).


get_provider_button_icon(Provider) ->
    proplists:get_value(button_icon, get_auth_config(Provider)).


get_provider_button_color(Provider) ->
    proplists:get_value(button_color, get_auth_config(Provider)).