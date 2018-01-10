%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2017 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module handles translation of request results to REST
%%% responses, designed to match entity logic API.
%%% @end
%%%-------------------------------------------------------------------
-module(rest_translator).
-author("Lukasz Opiola").

-include("rest.hrl").
-include("registered_names.hrl").

-export([response/2]).

%% Convenience functions for rest translators
-export([
    created_reply/1,
    ok_no_content_reply/0,
    ok_body_reply/1,
    updated_reply/0,
    deleted_reply/0
]).

%%%===================================================================
%%% API
%%%===================================================================

response(_, {error, _} = Err) ->
    error_rest_translator:response(Err);
response(#el_req{operation = create}, ok) ->
    % No need for translation, 'ok' means success with no response data
    rest_translator:ok_no_content_reply();
response(#el_req{operation = create} = ElReq, {ok, Result}) ->
    #el_req{gri = GRI = #gri{type = Model}, auth_hint = AuthHint} = ElReq,
    Translator = entity_type_to_translator(Model),
    Translator:create_response(GRI, AuthHint, Result);
response(#el_req{operation = get} = ElReq, {ok, Data}) ->
    #el_req{gri = GRI = #gri{type = Model}} = ElReq,
    Translator = entity_type_to_translator(Model),
    Translator:get_response(GRI, Data);
response(#el_req{operation = update}, ok) ->
    updated_reply();
response(#el_req{operation = delete}, ok) ->
    deleted_reply().


%%--------------------------------------------------------------------
%% @doc
%% REST reply that should be used for successful REST operations that send
%% a body in response.
%% @end
%%--------------------------------------------------------------------
-spec ok_body_reply(Body :: jiffy:json_value()) -> #rest_resp{}.
ok_body_reply(Body) ->
    #rest_resp{code = ?HTTP_200_OK, body = Body}.


%%--------------------------------------------------------------------
%% @doc
%% REST reply that should be used for successful REST operations that do not
%% send any body in response.
%% @end
%%--------------------------------------------------------------------
-spec ok_no_content_reply() -> #rest_resp{}.
ok_no_content_reply() ->
    #rest_resp{code = ?HTTP_204_NO_CONTENT}.


%%--------------------------------------------------------------------
%% @doc
%% REST reply that should be used for successful create REST calls.
%% Returns 201 CREATED with proper location headers.
%% @end
%%--------------------------------------------------------------------
-spec created_reply(PathTokens :: [binary()]) -> #rest_resp{}.
% Make sure there is no leading slash (so filename can be used for joining path)
created_reply([<<"/", Path/binary>> | Tail]) ->
    created_reply([Path | Tail]);
created_reply(PathTokens) ->
    {ok, Domain} = application:get_env(?APP_NAME, http_domain),
    DomainBin = list_to_binary(Domain),
    {ok, RestPrefix} = application:get_env(?APP_NAME, rest_api_prefix),
    % Make sure there is no leading slash (so path can be used for joining url)
    FullPath = case filename:join([RestPrefix | PathTokens]) of
        <<"/", Path/binary>> -> Path;
        Path -> Path
    end,
    Location = <<"https://", DomainBin/binary, "/", FullPath/binary>>,
    LocationHeader = #{<<"Location">> => Location},
    #rest_resp{code = ?HTTP_201_CREATED, headers = LocationHeader}.


%%--------------------------------------------------------------------
%% @doc
%% REST reply that should be used for successful REST updates.
%% @end
%%--------------------------------------------------------------------
-spec updated_reply() -> #rest_resp{}.
updated_reply() ->
    #rest_resp{code = ?HTTP_204_NO_CONTENT}.


%%--------------------------------------------------------------------
%% @doc
%% REST reply that should be used for successful REST deletions.
%% @end
%%--------------------------------------------------------------------
-spec deleted_reply() -> #rest_resp{}.
deleted_reply() ->
    #rest_resp{code = ?HTTP_204_NO_CONTENT}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns rest translator for given entity type.
%% @end
%%--------------------------------------------------------------------
-spec entity_type_to_translator(atom()) -> module().
entity_type_to_translator(od_user) -> user_rest_translator;
entity_type_to_translator(od_group) -> group_rest_translator;
entity_type_to_translator(od_space) -> space_rest_translator;
entity_type_to_translator(od_share) -> share_rest_translator;
entity_type_to_translator(od_provider) -> provider_rest_translator;
entity_type_to_translator(od_handle_service) -> handle_service_rest_translator;
entity_type_to_translator(od_handle) -> handle_rest_translator;
entity_type_to_translator(owned_identity) -> identity_rest_translator.