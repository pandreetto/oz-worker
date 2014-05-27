%% ===================================================================
%% @author Lukasz Opiola
%% @copyright (C): 2014 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc: This file contains n2o website code
%% @end
%% ===================================================================

-module(page_login).
-compile(export_all).
-include("gui_common.hrl").

%% Template points to the template file, which will be filled with content
main() -> #dtl{file = "bare", app = veil_cluster_node, bindings = [{title, title()}, {body, body()}]}.

%% Page title
title() -> <<"Login page">>.

%% This will be placed in the template instead of {{body}} tag
body() ->
    case gui_utils:user_logged_in() of
        true ->
            wf:redirect(<<"/">>);
        false ->
            Buttons = lists:map(
                fun(Provider) ->
                    ButtonText = <<"Sign in with ", (auth_utils:get_provider_name(Provider))/binary>>,
                    ButtonIcon = auth_utils:get_provider_button_icon(Provider),
                    ButtonColor = auth_utils:get_provider_button_color(Provider),
                    HandlerModule = auth_utils:get_provider_module(Provider),
                    #link{class = <<"btn btn-small">>, postback = {auth, HandlerModule},
                        style = <<"margin: 10px; text-align: left; width: 200px; background-color: ", ButtonColor/binary>>,
                        body = [
                            #span{style = <<"display: inline-block; line-height: 32px;">>, body = [
                                #image{image = ButtonIcon, style = <<"margin-right: 10px;">>},
                                ButtonText
                            ]}
                        ]}
                end, auth_utils:get_auth_providers()),

            ErrorPanelStyle = case wf:q(<<"x">>) of
                                  undefined -> <<"display: none;">>;
                                  _ -> <<"">>
                              end,

            #panel{style = <<"position: relative;">>, body = [
                #panel{id = <<"error_message">>, style = ErrorPanelStyle, class = <<"dialog dialog-danger">>, body = #p{
                    body = <<"Session error or session expired. Please log in again.">>}},
                #panel{class = <<"alert alert-success login-page">>, body = [
                    #h3{body = <<"Welcome to OneData">>},
                    #p{class = <<"login-info">>, body = <<"You can sign in using one of your existing accounts.">>},
                    #panel{style = <<"">>, body = Buttons}
                ]}
            ] ++ gui_utils:logotype_footer(120)}
    end.



event(init) -> ok;
% Login event handling

event({auth, HandlerModule}) ->
    {ok, URL} = HandlerModule:get_redirect_url(false),
    wf:redirect(URL).