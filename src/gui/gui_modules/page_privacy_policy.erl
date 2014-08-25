%% ===================================================================
%% @author Krzysztof Trzepla
%% @copyright (C): 2013 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc: This file contains n2o website code.
%% The page contains the privacy policy.
%% @end
%% ===================================================================

-module(page_privacy_policy).

-include("gui/common.hrl").

% n2o API
-export([main/0, event/1]).

-define(PRIVACY_POLICY_FILE, "releases/data/PRIVACY_POLICY.html").

%% Template points to the template file, which will be filled with content
main() ->
    #dtl{file = "bare", app = veil_cluster_node, bindings = [{title, title()}, {body, body()}, {custom, <<"">>}]}.


%% Page title
title() -> <<"Privacy policy">>.


%% This will be placed in the template instead of {{body}} tag
body() ->
    #panel{style = <<"padding: 20px 50px;">>, body = [
        #h3{style = <<"margin-bottom: 30px;">>, body = <<"Privacy policy - onedata.org">>},
        #panel{body = read_privacy_policy_file()},
        #link{class = <<"btn btn-success btn-wide">>, style = <<"float: right; margin: 30px 0 15px;">>, url = <<"/">>, body = <<"Main page">>}
    ]}.


% content of PRIVACY_POLICY.html file
read_privacy_policy_file() ->
    case file:read_file(?PRIVACY_POLICY_FILE) of
        {ok, File} -> File;
        {error, _Error} -> <<"">>
    end.


event(init) -> ok;
event(terminate) -> ok.
