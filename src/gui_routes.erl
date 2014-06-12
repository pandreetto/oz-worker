%% ===================================================================
%% @author Tomasz Lichon
%% @copyright (C): 2014 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc This module provides mapping of globalregistry paths to modules
%% that will render the pages.
%% @end
%% ===================================================================
-module(gui_routes).
-author("Tomasz Lichon").

%% Includes
-include_lib("n2o/include/wf.hrl").

%% API
-export([init/2, finish/2]).

finish(State, Ctx) -> {ok, State, Ctx}.

init(State, Ctx) ->
	Path = wf:path(Ctx#context.req),
	RequestedPage = case Path of
		                <<"/ws", Rest/binary>> -> Rest;
		                Other -> Other
	                end,
	{ok, State, Ctx#context{path = Path, module = route(RequestedPage)}}.

route(<<"/">>) -> page_hello;
route(_) -> page_404.