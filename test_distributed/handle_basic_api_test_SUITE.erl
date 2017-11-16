%%%-------------------------------------------------------------------
%%% @author Bartosz Walkowicz
%%% @copyright (C) 2017 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This file contains tests concerning handle basic API (REST + logic + gs).
%%% @end
%%%-------------------------------------------------------------------
-module(handle_basic_api_test_SUITE).
-author("Bartosz Walkowicz").

-include("rest.hrl").
-include("entity_logic.hrl").
-include("registered_names.hrl").
-include("datastore/oz_datastore_models.hrl").
-include_lib("ctool/include/logging.hrl").
-include_lib("ctool/include/privileges.hrl").
-include_lib("ctool/include/test/test_utils.hrl").
-include_lib("ctool/include/test/assertions.hrl").
-include_lib("ctool/include/test/performance.hrl").
-include_lib("cluster_worker/include/api_errors.hrl").

-include("api_test_utils.hrl").


-export([
    all/0,
    init_per_suite/1, end_per_suite/1,
    init_per_testcase/2, end_per_testcase/2
]).
-export([
    create_test/1,
    list_test/1,
    get_test/1,
    update_test/1,
    delete_test/1
]).

all() ->
    ?ALL([
        create_test,
        list_test,
        get_test,
        update_test,
        delete_test
    ]).


%%%===================================================================
%%% Test functions
%%%===================================================================


create_test(Config) ->
    % create handle service with 2 users; give handle_service_register_handle
    % privilege for one of them and all but that for the second one
    {HService, U1, U2} = api_test_scenarios:create_basic_doi_hservice_env(
        Config, ?HANDLE_SERVICE_REGISTER_HANDLE
    ),
    {ok, NonAdmin} = oz_test_utils:create_user(Config, #od_user{}),

    {ok, S1} = oz_test_utils:create_space(Config, ?USER(U1), ?SPACE_NAME1),
    {ok, U2} = oz_test_utils:add_user_to_space(Config, S1, U2),
    oz_test_utils:space_set_user_privileges(Config, S1, U2, set,
        oz_test_utils:get_space_privileges(Config)
    ),
    {ok, ShareId} = oz_test_utils:create_share(
        Config, ?ROOT, ?SHARE_ID_1, ?SHARE_NAME1, ?ROOT_FILE_ID, S1
    ),

    VerifyFun = fun(HandleId) ->
        {ok, Handle} = oz_test_utils:get_handle(Config, HandleId),
        ?assertEqual(<<"Share">>, Handle#od_handle.resource_type),
        ?assertEqual(ShareId, Handle#od_handle.resource_id),
        ?assertEqual(?DC_METADATA, Handle#od_handle.metadata),
        ?assertEqual(HService, Handle#od_handle.handle_service),
        true
    end,

    ApiTestSpec = #api_test_spec{
        client_spec = #client_spec{
            correct = [
                root,
                {user, U2}
            ],
            unauthorized = [nobody],
            forbidden = [
                {user, U1},
                {user, NonAdmin}
            ]
        },
        rest_spec = #rest_spec{
            method = post,
            path = <<"/handles">>,
            expected_code = ?HTTP_201_CREATED,
            expected_headers = fun(#{<<"location">> := Location} = _Headers) ->
                <<"/handles/", HandleId/binary>> = Location,
                VerifyFun(HandleId)
            end
        },
        logic_spec = #logic_spec{
            module = handle_logic,
            function = create,
            args = [client, data],
            expected_result = ?OK_TERM(VerifyFun)
        },
        gs_spec = #gs_spec{
            operation = create,
            gri = #gri{type = od_handle, aspect = instance},
            auth_hint = ?AS_USER(client),
            expected_result = ?OK_MAP_CONTAINS(#{
                <<"handleServiceId">> => HService,
                <<"metadata">> => ?DC_METADATA,
                <<"resourceId">> => ShareId,
                <<"resourceType">> => <<"Share">>,
                <<"gri">> => fun(EncodedGri) ->
                    #gri{id = Id} = oz_test_utils:decode_gri(
                        Config, EncodedGri
                    ),
                    VerifyFun(Id)
                end
            })
        },
        data_spec = #data_spec{
            required = [
                <<"handleServiceId">>, <<"resourceType">>,
                <<"resourceId">>, <<"metadata">>
            ],
            correct_values = #{
                <<"handleServiceId">> => [HService],
                <<"resourceType">> => [<<"Share">>],
                <<"resourceId">> => [ShareId],
                <<"metadata">> => [?DC_METADATA]
            }
%%            bad_values = [
%%                {<<"name">>, <<"">>, ?ERROR_BAD_VALUE_EMPTY(<<"name">>)},
%%                {<<"name">>, 1234, ?ERROR_BAD_VALUE_BINARY(<<"name">>)},
%%                {<<"metadata">>, <<"">>, ?ERROR_BAD_VALUE_EMPTY(<<"metadata">>)},
%%                {<<"metadata">>, 1234, ?ERROR_BAD_VALUE_BINARY(<<"metadata">>)}
%%            ]
        }
    },
    ?assert(api_test_utils:run_tests(Config, ApiTestSpec)).


list_test(Config) ->
    % Make sure that handles created in other tests are deleted.
    oz_test_utils:delete_all_entities(Config),

    {ok, U1} = oz_test_utils:create_user(Config, #od_user{}),
    oz_test_utils:set_user_oz_privileges(Config, U1, set, [
        ?OZ_HANDLE_SERVICES_CREATE
    ]),
    {ok, NonAdmin} = oz_test_utils:create_user(Config, #od_user{}),
    {ok, Admin} = oz_test_utils:create_user(Config, #od_user{}),
    oz_test_utils:set_user_oz_privileges(Config, Admin, set, [
        ?OZ_HANDLES_LIST
    ]),

    {ok, HService} = oz_test_utils:create_handle_service(
        Config, ?USER(U1), ?DOI_SERVICE
    ),
    {ok, S1} = oz_test_utils:create_space(Config, ?USER(U1), ?SPACE_NAME1),

    ExpHandles = lists:map(
        fun(_) ->
            ShareId = ?UNIQUE_NAME(<<"share">>),
            {ok, ShareId} = oz_test_utils:create_share(
                Config, ?ROOT, ShareId, ?SHARE_NAME1, ?ROOT_FILE_ID, S1
            ),
            {ok, HandleId} = oz_test_utils:create_handle(
                Config, ?USER(U1), ?HANDLE(HService, ShareId)
            ),
            HandleId
        end, lists:seq(1, 5)
    ),

    ApiTestSpec = #api_test_spec{
        client_spec = #client_spec{
            correct = [
                root,
                {user, Admin}
            ],
            unauthorized = [nobody],
            forbidden = [
                {user, U1},
                {user, NonAdmin}
            ]
        },
        rest_spec = #rest_spec{
            method = get,
            path = <<"/handles">>,
            expected_code = ?HTTP_200_OK,
            expected_body = #{<<"handles">> => ExpHandles}
        },
        logic_spec = #logic_spec{
            module = handle_logic,
            function = list,
            args = [client],
            expected_result = ?OK_LIST(ExpHandles)
        }
        % TODO gs
    },
    ?assert(api_test_utils:run_tests(Config, ApiTestSpec)),

    % check also handle_logic:exist function
    lists:foreach(
        fun(Handle) ->
            ?assert(oz_test_utils:call_oz(
                Config, handle_logic, exists, [Handle])
            )
        end, ExpHandles
    ),
    ?assert(not oz_test_utils:call_oz(
        Config, handle_logic, exists, [<<"asdiucyaie827346w">>])
    ).


get_test(Config) ->
    {ok, U1} = oz_test_utils:create_user(Config, #od_user{}),
    oz_test_utils:set_user_oz_privileges(Config, U1, set, [
        ?OZ_HANDLE_SERVICES_CREATE
    ]),
    {ok, U2} = oz_test_utils:create_user(Config, #od_user{}),
    {ok, NonAdmin} = oz_test_utils:create_user(Config, #od_user{}),
    {ok, Admin} = oz_test_utils:create_user(Config, #od_user{}),
    oz_test_utils:set_user_oz_privileges(Config, Admin, set, [
        ?OZ_HANDLES_LIST
    ]),

    {ok, HService} = oz_test_utils:create_handle_service(
        Config, ?USER(U1), ?DOI_SERVICE
    ),
    {ok, S1} = oz_test_utils:create_space(Config, ?USER(U1), ?SPACE_NAME1),
    {ok, ShareId} = oz_test_utils:create_share(
        Config, ?ROOT, ?SHARE_ID_1, ?SHARE_NAME1, ?ROOT_FILE_ID, S1
    ),

    HandleDetails = #{
        <<"handleServiceId">> => HService,
        <<"resourceType">> => <<"Share">>,
        <<"resourceId">> => ShareId,
        <<"metadata">> => ?DC_METADATA
    },
    {ok, HandleId} = oz_test_utils:create_handle(
        Config, ?USER(U1), HandleDetails
    ),
    oz_test_utils:handle_set_user_privileges(Config, HandleId, U1, revoke, [
        ?HANDLE_VIEW
    ]),
    {ok, U2} = oz_test_utils:add_user_to_handle(Config, HandleId, U2),
    oz_test_utils:handle_set_user_privileges(Config, HandleId, U2, set, [
        ?HANDLE_VIEW
    ]),

    AllPrivs = oz_test_utils:get_handle_privileges(Config),
    AllPrivsBin = [atom_to_binary(Priv, utf8) || Priv <- AllPrivs],

    % Get and check private data
    GetPrivateDataApiTestSpec = #api_test_spec{
        client_spec = #client_spec{
            correct = [
                root,
                {user, U2}
            ],
            unauthorized = [nobody],
            forbidden = [
                {user, Admin},
                {user, NonAdmin},
                {user, U1}
            ]
        },
        logic_spec = #logic_spec{
            module = handle_logic,
            function = get,
            args = [client, HandleId],
            expected_result = ?OK_TERM(
                fun(#od_handle{
                    resource_type = <<"Share">>,

                    metadata = Metadata, resource_id = ResourceId,
                    handle_service = HServiceId,
                    users = Users, groups = #{},
                    eff_users = EffUsers, eff_groups = #{},

                    bottom_up_dirty = false
                }) ->
                    ?assertEqual(?DC_METADATA, Metadata),
                    ?assertEqual(ShareId, ResourceId),
                    ?assertEqual(HService, HServiceId),
                    ?assertEqual(Users, #{
                        U1 => AllPrivs -- [?HANDLE_VIEW], U2 => [?HANDLE_VIEW]}
                    ),
                    ?assertEqual(EffUsers, #{
                        U1 => {AllPrivs -- [?HANDLE_VIEW],
                            [{od_handle, HandleId}]},
                        U2 => {[?HANDLE_VIEW],
                            [{od_handle, HandleId}]}
                    })
                end
            )
        },
        gs_spec = #gs_spec{
            operation = get,
            gri = #gri{type = od_handle, id = HandleId, aspect = instance},
            expected_result = ?OK_MAP_CONTAINS(#{
                <<"effectiveUsers">> => #{
                    U1 => AllPrivsBin -- [<<"handle_view">>],
                    U2 => [<<"handle_view">>]
                },
                <<"effectiveGroups">> => #{},
                <<"handleServiceId">> => HService,
                <<"metadata">> => ?DC_METADATA,
                <<"resourceId">> => ShareId,
                <<"resourceType">> => <<"Share">>,
                <<"gri">> => fun(EncodedGri) ->
                    #gri{id = Id} = oz_test_utils:decode_gri(
                        Config, EncodedGri
                    ),
                    ?assertEqual(HandleId, Id)
                end
            })
        }
    },
    ?assert(api_test_utils:run_tests(Config, GetPrivateDataApiTestSpec)),

    % Get and check protected data
    GetSharedDataApiTestSpec = #api_test_spec{
        client_spec = #client_spec{
            correct = [
                root,
                {user, Admin},
                {user, U1},
                {user, U2}
            ],
            unauthorized = [nobody],
            forbidden = [
                {user, NonAdmin}
            ]
        },
        rest_spec = #rest_spec{
            method = get,
            path = [<<"/handles/">>, HandleId],
            expected_code = ?HTTP_200_OK,
            expected_body = {contains, HandleDetails#{
                <<"handleId">> => HandleId
            }}
        },
        logic_spec = #logic_spec{
            module = handle_logic,
            function = get_protected_data,
            args = [client, HandleId],
            expected_result = ?OK_MAP_CONTAINS(HandleDetails)
        }
        % TODO gs
    },
    ?assert(api_test_utils:run_tests(Config, GetSharedDataApiTestSpec)).


update_test(Config) ->
    {ok, U1} = oz_test_utils:create_user(Config, #od_user{}),
    {ok, U2} = oz_test_utils:create_user(Config, #od_user{}),
    {ok, NonAdmin} = oz_test_utils:create_user(Config, #od_user{}),

    {ok, HService} = oz_test_utils:create_handle_service(
        Config, ?ROOT, ?DOI_SERVICE
    ),
    {ok, S1} = oz_test_utils:create_space(Config, ?USER(U1), ?SPACE_NAME1),
    ShareId = ?UNIQUE_NAME(<<"share">>),
    {ok, ShareId} = oz_test_utils:create_share(
        Config, ?ROOT, ShareId, ?SHARE_NAME1, ?ROOT_FILE_ID, S1
    ),

    AllPrivs = oz_test_utils:get_handle_privileges(Config),
    EnvSetUpFun = fun() ->
        {ok, HandleId} = oz_test_utils:create_handle(
            Config, ?ROOT, ?HANDLE(HService, ShareId)
        ),

        {ok, U1} = oz_test_utils:add_user_to_handle(Config, HandleId, U1),
        oz_test_utils:handle_set_user_privileges(Config, HandleId, U1, set,
            AllPrivs -- [?HANDLE_UPDATE]
        ),
        {ok, U2} = oz_test_utils:add_user_to_handle(Config, HandleId, U2),
        oz_test_utils:handle_set_user_privileges(Config, HandleId, U2, set, [
            ?HANDLE_UPDATE
        ]),
        #{handleId => HandleId}
    end,
    VerifyEndFun = fun(ShouldSucceed, #{handleId := HandleId}, Data) ->
        {ok, Handle} = oz_test_utils:get_handle(Config, HandleId),
        ExpMetadata = case ShouldSucceed of
            false -> ?DC_METADATA;
            true -> maps:get(<<"metadata">>, Data)
        end,
        ?assertEqual(ExpMetadata, Handle#od_handle.metadata)
    end,

    ApiTestSpec = #api_test_spec{
        client_spec = #client_spec{
            correct = [
                root,
                {user, U2}
            ],
            unauthorized = [nobody],
            forbidden = [
                {user, U1},
                {user, NonAdmin}
            ]
        },
        rest_spec = #rest_spec{
            method = patch,
            path = [<<"/handles/">>, handleId],
            expected_code = ?HTTP_204_NO_CONTENT
        },
        logic_spec = #logic_spec{
            module = handle_logic,
            function = update,
            args = [client, handleId, data],
            expected_result = ?OK
        },
        gs_spec = #gs_spec{
            operation = update,
            gri = #gri{type = od_handle, id = handleId, aspect = instance},
            expected_result = ?OK
        },
        data_spec = #data_spec{
            required = [<<"metadata">>],
            correct_values = #{<<"metadata">> => [?DC_METADATA2]},
            bad_values = [
                {<<"metadata">>, <<"">>, ?ERROR_BAD_VALUE_EMPTY(<<"metadata">>)},
                {<<"metadata">>, 1234, ?ERROR_BAD_VALUE_BINARY(<<"metadata">>)}
            ]
        }
    },
    ?assert(api_test_utils:run_tests(
        Config, ApiTestSpec, EnvSetUpFun, undefined, VerifyEndFun
    )).


delete_test(Config) ->
    {ok, U1} = oz_test_utils:create_user(Config, #od_user{}),
    {ok, U2} = oz_test_utils:create_user(Config, #od_user{}),
    {ok, NonAdmin} = oz_test_utils:create_user(Config, #od_user{}),

    {ok, HService} = oz_test_utils:create_handle_service(
        Config, ?ROOT, ?DOI_SERVICE
    ),
    {ok, S1} = oz_test_utils:create_space(Config, ?USER(U1), ?SPACE_NAME1),
    ShareId = ?UNIQUE_NAME(<<"share">>),
    {ok, ShareId} = oz_test_utils:create_share(
        Config, ?ROOT, ShareId, ?SHARE_NAME1, ?ROOT_FILE_ID, S1
    ),

    AllPrivs = oz_test_utils:get_handle_privileges(Config),
    EnvSetUpFun = fun() ->
        {ok, HandleId} = oz_test_utils:create_handle(
            Config, ?ROOT, ?HANDLE(HService, ShareId)
        ),

        {ok, U1} = oz_test_utils:add_user_to_handle(Config, HandleId, U1),
        oz_test_utils:handle_set_user_privileges(Config, HandleId, U1, set,
            AllPrivs -- [?HANDLE_DELETE]
        ),
        {ok, U2} = oz_test_utils:add_user_to_handle(Config, HandleId, U2),
        oz_test_utils:handle_set_user_privileges(Config, HandleId, U2, set, [
            ?HANDLE_DELETE
        ]),
        #{handleId => HandleId}
    end,
    VerifyEndFun = fun(ShouldSucceed, #{handleId := HandleId} = _Env, _) ->
        {ok, Handles} = oz_test_utils:list_handles(Config),
        ?assertEqual(lists:member(HandleId, Handles), not ShouldSucceed)
    end,

    ApiTestSpec = #api_test_spec{
        client_spec = #client_spec{
            correct = [
                root,
                {user, U2}
            ],
            unauthorized = [nobody],
            forbidden = [
                {user, U1},
                {user, NonAdmin}
            ]
        },
        rest_spec = #rest_spec{
            method = delete,
            path = [<<"/handles/">>, handleId],
            expected_code = ?HTTP_202_ACCEPTED
        },
        logic_spec = #logic_spec{
            module = handle_logic,
            function = delete,
            args = [client, handleId],
            expected_result = ?OK
        },
        gs_spec = #gs_spec{
            operation = delete,
            gri = #gri{type = od_handle, id = handleId, aspect = instance},
            expected_result = ?OK
        }
    },
    ?assert(api_test_scenarios:run_scenario(delete_entity,
        [Config, ApiTestSpec, EnvSetUpFun, VerifyEndFun]
    )).


%%%===================================================================
%%% Setup/teardown functions
%%%===================================================================


init_per_suite(Config) ->
    ssl:start(),
    hackney:start(),
    [{?LOAD_MODULES, [oz_test_utils]} | Config].


end_per_suite(_Config) ->
    hackney:stop(),
    ssl:stop().


init_per_testcase(_, Config) ->
    oz_test_utils:mock_handle_proxy(Config),
    Config.


end_per_testcase(_, Config) ->
    oz_test_utils:delete_all_entities(Config),
    oz_test_utils:unmock_handle_proxy(Config).
