%%%-------------------------------------------------------------------
%%% @author Jakub Kudzia
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @doc
%%% WRITEME
%%% @end
%%%-------------------------------------------------------------------
-module(oai_handler).
-author("Jakub Kudzia").

-include_lib("ctool/include/logging.hrl").
-include("http/handlers/oai.hrl").
-include("http/handlers/rest_handler.hrl").


%% API
-export([init/3, terminate/3, rest_init/2, allowed_methods/2,
    content_types_accepted/2, content_types_provided/2, resource_exists/2, accept_resource/2, provide_resource/2]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Cowboy callback function.
%% Upgrade the protocol to cowboy_rest.
%% @end
%%--------------------------------------------------------------------
init({_, http}, _Req, _Opts) ->
    {upgrade, protocol, cowboy_rest}.

%%--------------------------------------------------------------------
%% @doc Cowboy callback function.
%% Initialize the state for this request.
%% @end
%%--------------------------------------------------------------------
rest_init(Req, Opts) ->
    {ok, Req, Opts}.

%%--------------------------------------------------------------------
%% @doc Cowboy callback function.
%% Return the list of allowed methods.
%% @end
%%--------------------------------------------------------------------
allowed_methods(Req, State) ->
    {?ALLOWED_METHODS, Req, State}.


%% TODO malformed_request ???
%% TODO valid_entity_length ???


%% @doc Cowboy callback function.
%% Return the list of content-types the resource provides.
%% @end
%%--------------------------------------------------------------------
content_types_provided(Req, State) ->
    {[{?RESPONSE_CONTENT_TYPE, provide_resource}], Req, State}.


%% TODO charsets_provided ????

%%--------------------------------------------------------------------
%% @doc Cowboy callback function.
%% Return the list of content-types the resource accepts.
%% @end
%%--------------------------------------------------------------------
content_types_accepted(Req, State) ->
    {[{?REQUEST_CONTENT_TYPE, accept_resource}], Req, State}.


%%--------------------------------------------------------------------
%% @doc Cowboy callback function.
%% Return whether the resource exists.
%% @end
%%--------------------------------------------------------------------
resource_exists(Req, State) ->
%%    TODO
    {true, Req, State}.


%%--------------------------------------------------------------------
%% @doc
%% Cowboy handler callback, no cleanup needed
%%--------------------------------------------------------------------
-spec terminate(term(), term(), term()) -> ok.
terminate(_Reason, _Req, _State) ->
%%    TODO needed ?
    ok.


%%--------------------------------------------------------------------
%% @doc Cowboy callback function.
%% Process the request body.
%% @end
%%--------------------------------------------------------------------
-spec provide_resource(Req :: cowboy_req:req(), State :: any()) ->
    {iodata(), cowboy_req:req(), any()}.
provide_resource(Req, State) ->
    {QS, Req1} = cowboy_req:qs_vals(Req),
    {ResponseBody, Req2} = handle_request(QS, Req1),
    {ResponseBody, Req2, State}. % should return response_body


    %%--------------------------------------------------------------------
%% @doc Cowboy callback function.
%% Process the request body of application/x-www-form-urlencoded content type.
%% @end
%%--------------------------------------------------------------------
-spec accept_resource(Req :: cowboy_req:req(), State :: any()) ->
    boolean() | {{true, URL :: binary()} | boolean(), cowboy_req:req(), any()}.
accept_resource(Req, State) ->
    {ok, QS, Req1} = cowboy_req:body_qs(Req),
    {ResponseBody, Req2} = handle_request(QS, Req1),
    Req3 = cowboy_req:set_resp_body(ResponseBody, Req2),
    {true, Req3, State}.


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% WRITEME
%% @end
%%--------------------------------------------------------------------
-spec binary_to_verb(binary()) -> oai_verb().
binary_to_verb(<<"Identify">>) -> identify;
binary_to_verb(<<"GetRecord">>) -> getRecord;
binary_to_verb(<<"ListIdentifiers">>) -> listIdentifiers;
binary_to_verb(<<"ListMedatadaFormats">>) -> listMedatadaFormats;
binary_to_verb(<<"ListRecords">>) -> listRecords;
binary_to_verb(<<"ListSets">>) -> listSets.



handle_request(Args, Req) ->
    case proplists:get_value(<<"verb">>, Args) of
        undefined -> error; % todo handle bad verb error;
        Verb -> io:format("handle_request: ~nVerb=~p~nData=~p~n", [Verb, Args]),
            Module = binary_to_verb(Verb),
            XML = Module:process_request(Args, Req),
            io:format(lists:flatten(xmerl:export_simple([XML], xmerl_xml))),
            Req2 = cowboy_req:set_resp_header(<<"content-type">>, ?RESPONSE_CONTENT_TYPE, Req),
            {XML, Req2}
    end.

