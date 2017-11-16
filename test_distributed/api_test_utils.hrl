%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @doc
%%% Definitions of macros and records used in API (logic + REST) tests.
%%% @end
%%%-------------------------------------------------------------------
-author("Lukasz Opiola").

-ifndef(API_TEST_UTILS_HRL).
-define(API_TEST_UTILS_HRL, 1).

%% @formatter:off
-type client() :: nobody | root | {user, UserId :: binary()} |
    {provider, ProviderId :: binary(), KeyFile :: string(), CertFile :: string()}.

-type data_error() :: bad | empty | bad_token | bad_token_type |
    id_not_found | id_occupied | relation_exists | relation_does_not_exist.

-type rest_expectation() :: undefined | #{} | {contains, #{}} |
    fun((Result :: term()) -> term()).

-type logic_expectation() :: undefined | ok | ok_binary | {ok_binary, binary()} |
    {ok_map, #{}} | {ok_map_contains, #{}} |
    {ok_list, [term()]} | {ok_list_contains, [term()]} |
    {ok_list_doesnt_contain, [term()]} |
    {ok_term, fun((Result :: term()) -> boolean())} |
    {ok_env, fun((Env :: #{}, Data :: #{}) -> term())} | {error_reason, term()}.

-type gs_expectation() :: ok | {ok_map, #{}} | {ok_map_contains, #{}} |
    {ok_term, fun((Result :: term()) -> boolean())} |
    {ok_env, fun((Env :: #{}, Data :: #{}) -> term())} | {error_reason, term()}.
%% @formatter:on

-record(client_spec, {
    correct = [] :: [client()],
    unauthorized = [] :: [client()],
    forbidden = [] :: [client()]
}).

-record(data_spec, {
    required = [] :: [Key :: binary()],
    optional = [] :: [Key :: binary()],
    at_least_one = [] :: [Key :: binary()],
    correct_values = #{} :: #{Key :: binary() => Values :: [binary()]},
    bad_values = [] :: [{Key :: binary(), Value :: term(), data_error()}]
}).

-record(rest_spec, {
    method = get :: get | patch | post | put | delete,
    path = <<"/">> :: binary() | [binary()],
    headers = undefined :: undefined | #{Key :: binary() => Value :: binary()},
    expected_code = undefined :: undefined | integer(),
    expected_headers = undefined :: undefined | rest_expectation(),
    expected_body = undefined :: undefined | rest_expectation()
}).

-record(logic_spec, {
    operation = get :: create | get | update | delete,
    module = undefined :: module(),
    function = undefined :: atom(),
    % In args, special atoms 'client' and 'data' can be used. In this case,
    % client and data will be automatically injected in these placeholders.
    args = [] :: [term()],
    expected_result = undefined :: undefined | logic_expectation()
}).

-record(gs_spec, {
    operation = get :: gs_protocol:operation(),
    gri :: gs_protocol:gri(),
    subscribe = false :: boolean(),
    auth_hint = undefined :: gs_protocol:auth_hint(),
    expected_result = undefined :: undefined | gs_expectation()
}).

-record(api_test_spec, {
    client_spec = undefined :: undefined | #client_spec{},
    rest_spec = undefined :: undefined | #rest_spec{},
    logic_spec = undefined :: undefined | #logic_spec{},
    gs_spec = undefined :: undefined | #gs_spec{},
    data_spec = undefined :: undefined | #data_spec{}
}).

% Convenience macros for expressing gs and/or logic result expectations
-define(OK, ok).
-define(OK_BINARY, ok_binary).
-define(OK_BINARY(__ExactValue), {ok_binary, __ExactValue}).
-define(OK_MAP(__ExactValue), {ok_map, __ExactValue}).
-define(OK_MAP_CONTAINS(__Contains), {ok_map_contains, __Contains}).
-define(OK_LIST(__ExpectedList), {ok_list, __ExpectedList}).
-define(OK_LIST_CONTAINS(__ExpectedList), {ok_list_contains, __ExpectedList}).
-define(OK_LIST_DOESNT_CONTAIN(__ExpectedList),
    {ok_list_doesnt_contain, __ExpectedList}).
-define(OK_TERM(__VerifyFun), {ok_term, __VerifyFun}).
-define(OK_ENV(__PrepareFun), {ok_env, __PrepareFun}).
-define(ERROR_REASON(__ExpectedError), {error_reason, __ExpectedError}).

%% Example test data
-define(UNIQUE_NAME(Prefix),
    <<
        Prefix/binary,
        (integer_to_binary(erlang:unique_integer([positive])))/binary
    >>
).

%% Example test data for users
-define(USER_NAME1, <<"user1">>).
-define(USER_NAME2, <<"user2">>).
-define(USER_NAME3, <<"user3">>).
% Default alias (= no alias set) is an empty string
-define(DEFAULT_USER_ALIAS, <<"">>).
-define(USER_ALIAS1, <<"alias1">>).
-define(USER_ALIAS2, <<"alias2">>).
-define(USER_LOGIN1, <<"login1">>).
-define(USER_LOGIN2, <<"login2">>).

%% Example test data for groups
-define(GROUP_NAME1, <<"group1">>).
-define(GROUP_NAME2, <<"group2">>).
-define(GROUP_TYPE1, unit).
-define(GROUP_TYPE1_BIN, <<"unit">>).
-define(GROUP_TYPE2, team).
-define(GROUP_TYPE2_BIN, <<"team">>).
-define(GROUP_TYPES, [organization,unit,team,role]).
-define(GROUP_DETAILS(GroupName),
    #{
        <<"name">> => GroupName,
        <<"type">> => lists:nth(rand:uniform(4), ?GROUP_TYPES)
    }
).

%% Example test data for spaces
-define(SPACE_NAME1, <<"space1">>).
-define(SPACE_NAME2, <<"space2">>).
-define(SPACE_SIZE1, <<"1024024024">>).
-define(SPACE_SIZE2, <<"4096096096">>).

%% Example test data for shares
-define(SHARE_NAME1, <<"share1">>).
-define(SHARE_NAME2, <<"share2">>).
-define(SHARE_ID_1, <<"shareId1">>).
-define(SHARE_ID_2, <<"shareId2">>).
-define(ROOT_FILE_ID, <<"root_file">>).
-define(SHARE_PUBLIC_URL(ZoneDomain, ShareId),
    str_utils:format_bin("https://~s/share/~s", [ZoneDomain, ShareId])
).

%% Example test data for providers
-define(LATITUDE, 23.10).
-define(LONGITUDE, 44.44).
-define(URLS1, [<<"127.0.0.1">>]).
-define(URLS2, [<<"127.0.0.2">>]).
-define(REDIRECTION_POINT1, <<"https://127.0.0.1:443">>).
-define(REDIRECTION_POINT2, <<"https://127.0.0.2:443">>).
-define(PROVIDER_NAME1, <<"provider1">>).
-define(PROVIDER_NAME2, <<"provider2">>).
-define(PROVIDER_DETAILS(ProviderName),
    #{
        <<"name">> => ProviderName,
        <<"urls">> => ?URLS1,
        <<"redirectionPoint">> => ?REDIRECTION_POINT1,
        <<"latitude">> => rand:uniform() * 90,
        <<"longitude">> => rand:uniform() * 180
    }
).

%% Example test data for handle services
-define(HANDLE_SERVICE_NAME1, <<"LifeWatch DataCite">>).
-define(HANDLE_SERVICE_NAME2, <<"iMarine EPIC">>).
-define(PROXY_ENDPOINT, <<"172.17.0.9:8080/api/v1">>).
-define(DOI_SERVICE_PROPERTIES,
    #{
        <<"type">> => <<"DOI">>,
        <<"host">> => <<"https://mds.test.datacite.org">>,
        <<"doiEndpoint">> => <<"/doi">>,
        <<"metadataEndpoint">> => <<"/metadata">>,
        <<"mediaEndpoint">> => <<"/media">>,
        <<"prefix">> => <<"10.5072">>,
        <<"username">> => <<"alice">>,
        <<"password">> => <<"*******">>,
        <<"identifierTemplate">> => <<"{{space.name}}-{{space.guid}}">>,
        <<"allowTemplateOverride">> => false
    }
).
-define(DOI_SERVICE,
    #{
        <<"name">> => ?HANDLE_SERVICE_NAME1,
        <<"proxyEndpoint">> => ?PROXY_ENDPOINT,
        <<"serviceProperties">> => ?DOI_SERVICE_PROPERTIES
    }
).
-define(PID_SERVICE_PROPERTIES,
    #{
        <<"type">> => <<"PID">>,
        <<"endpoint">> => <<"https://epic.grnet.gr/api/v2/handles">>,
        <<"prefix">> => <<"11789">>,
        <<"suffixGeneration">> => <<"auto">>,
        <<"suffixPrefix">> => <<"{{space.name}}">>,
        <<"suffixSuffix">> => <<"{{user.name}}">>,
        <<"username">> => <<"alice">>,
        <<"password">> => <<"*******">>,
        <<"identifierTemplate">> => <<"{{space.name}}-{{space.guid}}">>,
        <<"allowTemplateOverride">> => false
    }
).
-define(PID_SERVICE,
    #{
        <<"name">> => ?HANDLE_SERVICE_NAME2,
        <<"proxyEndpoint">> => ?PROXY_ENDPOINT,
        <<"serviceProperties">> => ?PID_SERVICE_PROPERTIES
    }
).

%% Example test data for handles
-define(DC_METADATA, <<"<?xml version=\"1.0\"?>",
    "<metadata xmlns:xsi=\"http:\/\/www.w3.org\/2001\/XMLSchema-instance\" xmlns:dc=\"http:\/\/purl.org\/dc\/elements\/1.1\/\">"
    "<dc:title>Test dataset<\/dc:title>",
    "<dc:creator>John Johnson<\/dc:creator>",
    "<dc:creator>Jane Doe<\/dc:creator>",
    "<dc:subject>Test of datacite<\/dc:subject>",
    "<dc:description>Lorem ipsum lorem ipusm<\/dc:description>",
    "<dc:publisher>Onedata<\/dc:publisher>",
    "<dc:publisher>EGI<\/dc:publisher>",
    "<dc:date>2016<\/dc:date>",
    "<dc:format>application\/pdf<\/dc:format>",
    "<dc:identifier>onedata:LKJHASKFJHASLKDJHKJHuah132easd<\/dc:identifier>",
    "<dc:language>eng<\/dc:language>",
    "<dc:rights>CC-0<\/dc:rights>",
    "<\/metadata>">>).

-define(DC_METADATA2, <<"<?xml version=\"1.0\"?>",
    "<metadata xmlns:xsi=\"http:\/\/www.w3.org\/2001\/XMLSchema-instance\" xmlns:dc=\"http:\/\/purl.org\/dc\/elements\/1.1\/\">"
    "<dc:title>Test dataset<\/dc:title>",
    "<dc:creator>Jane Johnson<\/dc:creator>",
    "<dc:creator>John Doe<\/dc:creator>",
    "<dc:subject>Test of datacite<\/dc:subject>",
    "<dc:description>Dolor sit amet<\/dc:description>",
    "<dc:publisher>Onedata<\/dc:publisher>",
    "<dc:publisher>EGI<\/dc:publisher>",
    "<dc:date>2017<\/dc:date>",
    "<dc:format>application\/pdf<\/dc:format>",
    "<dc:identifier>onedata:LKJHASKFJHASLKDJHKJHuah132easd<\/dc:identifier>",
    "<dc:language>eng<\/dc:language>",
    "<dc:rights>CC-0<\/dc:rights>",
    "<\/metadata>">>).

-define(HANDLE(HandleServiceId, ResourceId),
    #{
        <<"handleServiceId">> => HandleServiceId,
        <<"resourceType">> => <<"Share">>,
        <<"resourceId">> => ResourceId,
        <<"metadata">> => ?DC_METADATA
    }
).

-endif.
