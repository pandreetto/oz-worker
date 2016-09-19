%%%-------------------------------------------------------------------
%%% @author Jakub Kudzia
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @doc
%%% This module is responsible for handling OAI-PMH "GetRecord" request.
%%% @end
%%%-------------------------------------------------------------------
-module(get_record).
-author("Jakub Kudzia").

-include("http/handlers/oai.hrl").

-behaviour(oai_verb_behaviour).

%% API
-export([required_arguments/0, optional_arguments/0, exclusive_arguments/0,
    required_response_elements/0, optional_response_elements/0, get_response/2]).


%%%-------------------------------------------------------------------
%%% @doc
%%% {@link oai_verb_behaviour} callback required_arguments/0
%%% @end
%%%-------------------------------------------------------------------
-spec required_arguments() -> [binary()].
required_arguments() -> [<<"identifier">>, <<"metadataPrefix">>].


%%%-------------------------------------------------------------------
%%% @doc
%%% {@link oai_verb_behaviour} callback optional_arguments/0
%%% @end
%%%-------------------------------------------------------------------
-spec optional_arguments() -> [binary()].
optional_arguments() -> [].


%%%-------------------------------------------------------------------
%%% @doc
%%% {@link oai_verb_behaviour} callback exclusive_arguments/0
%%% @end
%%%--------------------------------------------------------------------
-spec exclusive_arguments() -> [binary()].
exclusive_arguments() -> [].

%%%-------------------------------------------------------------------
%%% @doc
%%% {@link oai_verb_behaviour} callback required_response_elements/0
%%% @end
%%%-------------------------------------------------------------------
-spec required_response_elements() -> [binary()].
required_response_elements() -> [<<"record">>].

%%%-------------------------------------------------------------------
%%% @doc
%%% {@link oai_verb_behaviour} callback optional_response_elements/0
%%% @end
%%%-------------------------------------------------------------------
-spec optional_response_elements() -> [binary()].
optional_response_elements() -> [].

%%%-------------------------------------------------------------------
%%% @doc
%%% {@link oai_verb_behaviour} callback get_response/2
%%% @end
%%%-------------------------------------------------------------------
-spec get_response(binary(), proplist()) -> oai_response().
get_response(<<"record">>, Args) ->
    Id = proplists:get_value(<<"identifier">>, Args),
    MetadataPrefix = proplists:get_value(<<"metadataPrefix">>, Args),
    Metadata = get_metadata(Id),
    MetadataValue = proplists:get_value(<<"metadata">>, Metadata),
    DateTime = proplists:get_value(<<"metadata_timestamp">>, Metadata),
    SupportedMetadataFormats = proplists:get_value(<<"metadata_formats">>, Metadata),
    case lists:member(MetadataPrefix, SupportedMetadataFormats) of
        true ->
            #oai_record{
                header = #oai_header{
                    identifier = Id,
                    datestamp = oai_utils:datetime_to_oai_datestamp(DateTime)
                },
                metadata = #oai_metadata{
                    metadata_format = #oai_metadata_format{metadataPrefix = MetadataPrefix},
                    value = MetadataValue
                }
            };
        false ->
            throw({cannotDisseminateFormat, str_utils:format(
                "Metadata format ~s is not supported by this repository",
                [MetadataPrefix])})
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%%-------------------------------------------------------------------
%%% @private
%%% @doc
%%% Returns given share metadata.
%%% If it fails, throws idDoesNotExist
%%% @end
%%%--------
-spec get_metadata(any()) -> any().
get_metadata(Id) ->
    try
        {ok, Metadata} = share_logic:get_metadata(Id),
        Metadata
    catch
        _:_ ->
            throw({idDoesNotExist, str_utils:format(
                "The value of the identifier argument \"~s\" "
                "is unknown in this repository.", [Id])})
    end.