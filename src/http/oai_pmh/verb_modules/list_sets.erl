%%%-------------------------------------------------------------------
%%% @author Jakub Kudzia
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @doc
%%% WRITEME
%%% @end
%%%-------------------------------------------------------------------
-module(list_sets).
-author("Jakub Kudzia").

%% API
-export([required_arguments/0, optional_arguments/0, exclusive_arguments/0,
    required_response_elements/0, optional_response_elements/0, get_element/1]).

-include("registered_names.hrl").


required_arguments() -> [].

optional_arguments() -> [].

exclusive_arguments() -> [<<"resumptionToken">>].

required_response_elements() -> [set].

optional_response_elements() -> [].

get_element(set) ->
    erlang:error(not_implemented).
