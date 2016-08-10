%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc Integration tests of privileges REST module in onezone.
%%% @end
%%%-------------------------------------------------------------------
-module(rest_privileges_test_SUITE).
-author("Lukasz Opiola").

-include("registered_names.hrl").
-include("datastore/oz_datastore_models_def.hrl").
-include_lib("ctool/include/logging.hrl").
-include_lib("ctool/include/test/test_utils.hrl").
-include_lib("ctool/include/test/assertions.hrl").
-include_lib("ctool/include/test/performance.hrl").


-export([all/0, init_per_suite/1, end_per_suite/1, end_per_testcase/2]).
-export([
    view_privileges_test/1,
    set_privileges_test/1,
    list_spaces_test/1,
    list_providers_test/1,
    list_providers_of_space_test/1,
    modify_space_members_test/1
]).


%%%===================================================================
%%% API functions
%%%===================================================================

all() ->
    % Below tests check all OZ API privileges
    ?ALL([
        % test case               % tested_privileges
        % ---------------------------------------------------
        view_privileges_test,     % view_privileges
        set_privileges_test,      % set_privileges
        list_spaces_test,         % list_spaces
        list_providers_test,      % list_providers
        list_providers_of_space_test, % list_providers_of_space
        modify_space_members_test % add_member_to_space,remove_member_from_space
    ]).


%%%===================================================================
%%% Test functions
%%%===================================================================

view_privileges_test(Config) ->
    put_config(Config),
    User1 = create_user(),
    % Unauthenticated requests should be discarded (401)
    ?assert(check_rest_call(#{
        request => #{
            method => get,
            path => [<<"/privileges/users/">>, User1]
        },
        expect => #{
            code => 401
        }
    })),
    % User without permissions cannot view the OZ API privileges (403)
    ?assert(check_rest_call(#{
        request => #{
            method => get,
            path => [<<"/privileges/users/">>, User1],
            auth => {user, User1}
        },
        expect => #{
            code => 403
        }
    })),
    % Give the user view privileges and check again
    set_privileges(User1, onedata_user, [view_privileges]),
    ?assert(check_rest_call(#{
        request => #{
            method => get,
            path => [<<"/privileges/users/">>, User1],
            auth => {user, User1}
        },
        expect => #{
            code => 200,
            body => #{<<"privileges">> => [
                <<"view_privileges">>
            ]}
        }
    })),
    % New users and groups should have no permissions by default
    User2 = create_user(),
    Group2 = create_group_for_user(User2),
    ?assert(check_rest_call(#{
        request => #{
            method => get,
            path => [<<"/privileges/users/">>, User2],
            auth => {user, User1}
        },
        expect => #{
            code => 200,
            body => #{<<"privileges">> => []}
        }
    })),
    ?assert(check_rest_call(#{
        request => #{
            method => get,
            path => [<<"/privileges/groups/">>, Group2],
            auth => {user, User1}
        },
        expect => #{
            code => 200,
            body => #{<<"privileges">> => []}
        }
    })),
    % Checking the privileges of nonexistent user or group should return 404
    ?assert(check_rest_call(#{
        request => #{
            method => get,
            path => [<<"/privileges/users/">>, <<"nonexistent_user">>],
            auth => {user, User1}
        },
        expect => #{
            code => 404
        }
    })),
    ?assert(check_rest_call(#{
        request => #{
            method => get,
            path => [<<"/privileges/groups/">>, <<"nonexistent_group">>],
            auth => {user, User1}
        },
        expect => #{
            code => 404
        }
    })).


set_privileges_test(Config) ->
    put_config(Config),
    User1 = create_user(),
    % Give the user perms to view and set privileges
    set_privileges(User1, onedata_user, [view_privileges, set_privileges]),
    % First try some wrong perms
    ?assert(check_rest_call(#{
        request => #{
            method => put,
            path => [<<"/privileges/users/">>, User1],
            body => #{
                <<"privileges">> => [
                    inexistent,
                    permissions
                ]
            },
            auth => {user, User1}
        },
        expect => #{
            code => 400
        }
    })),
    % And now a nonexistent user
    ?assert(check_rest_call(#{
        request => #{
            method => put,
            path => [<<"/privileges/users/">>, <<"nonexistent_user">>],
            body => #{
                <<"privileges">> => []
            },
            auth => {user, User1}
        },
        expect => #{
            code => 404
        }
    })),
    % Create a user and a group for testing
    User2 = create_user(),
    Group2 = create_group_for_user(User2),
    AllPrivileges = get_all_privileges(),
    % Fun that chooses a random subset of privileges from all possible
    GenerateRandomPrivs = fun() ->
        random:seed(erlang:timestamp()),
        Shuffled = [X || {_, X} <-
            lists:sort([{random:uniform(), N} || N <- AllPrivileges])],
        Len = random:uniform(length(AllPrivileges)),
        RandomizedAtoms = lists:sublist(Shuffled, Len),
        % Return a list of binaries
        [atom_to_binary(Atom, utf8) || Atom <- RandomizedAtoms]
    end,
    % Generate 30 test cases by trying to set a random subset of privileges and
    % check if it was set correctly, both for User2 and Group2.
    lists:foreach(
        fun(_) ->
            RandomPrivs = GenerateRandomPrivs(),
            % Set the privileges
            ?assert(check_rest_call(#{
                request => #{
                    method => put,
                    path => [<<"/privileges/users/">>, User2],
                    body => #{<<"privileges">> => RandomPrivs},
                    auth => {user, User1}
                },
                expect => #{
                    code => 204
                }
            })),
            % View the privileges
            ?assert(check_rest_call(#{
                request => #{
                    method => get,
                    path => [<<"/privileges/users/">>, User2],
                    auth => {user, User1}
                },
                expect => #{
                    code => 200,
                    body => #{<<"privileges">> => RandomPrivs}
                }
            }))
        end, lists:seq(1, 30)), % 30 times
    % Now for Group2
    lists:foreach(
        fun(_) ->
            RandomPrivs = GenerateRandomPrivs(),
            % Set the privileges
            ?assert(check_rest_call(#{
                request => #{
                    method => put,
                    path => [<<"/privileges/groups/">>, Group2],
                    body => #{<<"privileges">> => RandomPrivs},
                    auth => {user, User1}
                },
                expect => #{
                    code => 204
                }
            })),
            % View the privileges
            ?assert(check_rest_call(#{
                request => #{
                    method => get,
                    path => [<<"/privileges/groups/">>, Group2],
                    auth => {user, User1}
                },
                expect => #{
                    code => 200,
                    body => #{<<"privileges">> => RandomPrivs}
                }
            }))
        end, lists:seq(1, 30)), % 30 times
    ok.


list_spaces_test(Config) ->
    put_config(Config),
    % Create some spaces belonging to some users
    UserWithSpaces1 = create_user(),
    UserWithSpaces2 = create_user(),
    UserWithSpaces3 = create_user(),
    Space1 = create_space_for_user(UserWithSpaces1),
    Space2 = create_space_for_user(UserWithSpaces1),
    Space3 = create_space_for_user(UserWithSpaces2),
    Space4 = create_space_for_user(UserWithSpaces3),
    ExpectedBody = #{
        <<"spaces">> => [
            Space1,
            Space2,
            Space3,
            Space4
        ]
    },
    list_privilege_scenario(
        Config,
        <<"/spaces">>,
        <<"list_spaces">>,
        ExpectedBody
    ).


list_providers_test(Config) ->
    put_config(Config),
    Provider1 = create_provider(),
    Provider2 = create_provider(),
    Provider3 = create_provider(),
    ExpectedBody = #{
        <<"providers">> => [
            Provider1,
            Provider2,
            Provider3
        ]
    },
    list_privilege_scenario(
        Config,
        <<"/providers">>,
        <<"list_providers">>,
        ExpectedBody
    ).


list_providers_of_space_test(Config) ->
    put_config(Config),
    TestUser = create_user(),
    Provider1 = create_provider(),
    Provider2 = create_provider(),
    Space1 = create_space_for_user(TestUser),
    support_space(Space1, TestUser, Provider1),
    support_space(Space1, TestUser, Provider2),
    ExpectedBody = #{
        <<"providers">> => [
            Provider1,
            Provider2
        ]
    },
    list_privilege_scenario(
        Config,
        [<<"/spaces/">>, Space1, <<"/providers">>],
        <<"list_providers_of_space">>,
        ExpectedBody
    ).


% Runs a fixed scenario against given privilege, checking if giving and revoking
% privileges to user/group has effect on his rights to perform certain
% operations. The operations concern viewing system entities.
% The scenario is as follows:
% 1) Make sure user cannot perform tested operation by default
% 2) Give him the privilege and make sure that now he can
% 3) Revoke the privilege and check if he cannot
% 4) Give the privilege to a group user belongs to and check if he can
% 5) Revoke the privilege from the group and check if he cannot
% 6) Give the privilege to a parent of his group and check if he can
% 7) Revoke the privilege from the group and check if he cannot
list_privilege_scenario(Config, PathToCheck, Privilege, BodyOnSuccess) ->
    put_config(Config),
    % Admin will be used to grant or revoke privileges
    Admin = create_user(),
    set_privileges(Admin, onedata_user, [set_privileges]),
    % User will be used to test the functionality
    TestUser = create_user(),
    % Define some functions that will be used repeatedly
    % Set privileges for given entity as admin
    SetPrivileges = fun(EntityId, EntityType, Privileges) ->
        Path = case EntityType of
            onedata_user ->
                [<<"/privileges/users/">>, EntityId];
            user_group ->
                [<<"/privileges/groups/">>, EntityId]
        end,
        check_rest_call(#{
            request => #{
                method => put,
                path => Path,
                body => #{<<"privileges">> => Privileges},
                auth => {user, Admin}
            },
            expect => #{
                code => 204
            }
        })
    end,
    % Make sure user cannot get given resource
    CannotGetResource = fun() ->
        check_rest_call(#{
            request => #{
                method => get,
                path => PathToCheck,
                auth => {user, TestUser}
            },
            expect => #{
                code => 403
            }
        })
    end,
    % Make sure user can get given resource
    CanGetResource = fun() ->
        check_rest_call(#{
            request => #{
                method => get,
                path => PathToCheck,
                auth => {user, TestUser}
            },
            expect => #{
                code => 200,
                body => BodyOnSuccess
            }
        })
    end,

    %% PRIVILEGES AS A USER

    % TestUser should not be able to perform the operation
    % as he does not yet have privs
    ?assert(CannotGetResource()),
    % Lets grant privileges to the user
    ?assert(SetPrivileges(TestUser, onedata_user, [Privilege])),
    % Now he should be able to perform the operation
    ?assert(CanGetResource()),
    % Revoke the privileges again
    ?assert(SetPrivileges(TestUser, onedata_user, [])),
    % He should no longer be able to perform the operation
    ?assert(CannotGetResource()),

    %% PRIVILEGES VIA GROUP

    % Add the user to a group and give it privileges, see if the user can
    % perform the operation.
    TestGroup = create_group_for_user(TestUser),
    % The user should still not be able to perform the operation as the group
    % does not have privileges.
    ?assert(CannotGetResource()),
    % But when we grant privileges to TestGroup, he should be able to
    % perform the operation
    ?assert(SetPrivileges(TestGroup, user_group, [Privilege])),
    % Try multiple times, because group graph takes a while to update
    ?assertEqual(true, CanGetResource(), 10), % Try 10 times
    % Revoke the privileges and check again
    ?assert(SetPrivileges(TestGroup, user_group, [])),
    % Try multiple times, because group graph takes a while to update
    ?assertEqual(true, CannotGetResource(), 10), % Try 10 times

    %% PRIVILEGES VIA NESTED GROUPS

    % Add him to a nested group, which belongs to a group, which belongs to a
    % group that has the privileges and check if he can perform the operation.
    GrandChildGroup = create_group_for_user(TestUser),
    ChildGroup = create_group_for_group(GrandChildGroup),
    ParentGroup = create_group_for_group(ChildGroup),
    % The user should still not be able to perform the operation as the group
    % does not have privileges.
    ?assert(CannotGetResource()),
    % But when we grant privileges to ParentGroup, he should be able to
    % perform the operation
    ?assert(SetPrivileges(ParentGroup, user_group, [Privilege])),
    % Try multiple times, because group graph takes a while to update
    ?assertEqual(true, CanGetResource(), 10), % Try 10 times
    % Revoke the privileges and check again
    ?assert(SetPrivileges(ParentGroup, user_group, [])),
    % Try multiple times, because group graph takes a while to update
    ?assertEqual(true, CannotGetResource(), 10), % Try 10 times
    ok.


modify_space_members_test(Config) ->
    try
        put_config(Config),
        % Admin will be used to grant or revoke privileges
        Admin = create_user(),
        set_privileges(Admin, onedata_user, [set_privileges]),
        % TestUser will be used to test the privileges
        TestUser = create_user(),
        % AddedUser will be added to spaces and removed by TestUser
        AddedUser = create_user(),
        % AddedGroup will be added to spaces and removed by TestUser
        AddedGroup = create_group_for_user(create_user()),
        % Create a space
        SpaceOwner = create_user(),
        TestSpace = create_space_for_user(SpaceOwner),

        % Define some functions that will be used repeatedly
        % Set privileges for given entity as admin
        SetPrivileges = fun(EntityId, EntityType, Privileges) ->
            Path = case EntityType of
                onedata_user ->
                    [<<"/privileges/users/">>, EntityId];
                user_group ->
                    [<<"/privileges/groups/">>, EntityId]
            end,
            check_rest_call(#{
                request => #{
                    method => put,
                    path => Path,
                    body => #{<<"privileges">> => Privileges},
                    auth => {user, Admin}
                },
                expect => #{
                    code => 204
                }
            })
        end,
        % Make sure user CANNOT add users or groups to spaces
        CannotAddEntity = fun(EntityId, EntityType) ->
            {Path, Body} = case EntityType of
                onedata_user -> {
                    [<<"/spaces/">>, TestSpace, <<"/users">>],
                    #{<<"userId">> => EntityId}
                };
                user_group -> {
                    [<<"/spaces/">>, TestSpace, <<"/groups">>],
                    #{<<"groupId">> => EntityId}
                }
            end,
            check_rest_call(#{
                request => #{
                    method => put,
                    path => Path,
                    body => Body,
                    auth => {user, TestUser}
                },
                expect => #{
                    code => 403
                }
            })
        end,
        % Make sure user CAN add users or groups to spaces
        CanAddEntity = fun(EntityId, EntityType) ->
            {Path, Body} = case EntityType of
                onedata_user -> {
                    [<<"/spaces/">>, TestSpace, <<"/users">>],
                    #{<<"userId">> => EntityId}
                };
                user_group -> {
                    [<<"/spaces/">>, TestSpace, <<"/groups">>],
                    #{<<"groupId">> => EntityId}
                }
            end,
            check_rest_call(#{
                request => #{
                    method => put,
                    path => Path,
                    body => Body,
                    auth => {user, TestUser}
                },
                expect => #{
                    code => 204
                }
            })
        end,
        % Make sure user CANNOT delete users or groups to spaces
        CannotDeleteEntity = fun(EntityId, EntityType) ->
            Path = case EntityType of
                onedata_user ->
                    [<<"/spaces/">>, TestSpace, <<"/users/">>, EntityId];
                user_group ->
                    [<<"/spaces/">>, TestSpace, <<"/groups/">>, EntityId]

            end,
            check_rest_call(#{
                request => #{
                    method => delete,
                    path => Path,
                    auth => {user, TestUser}
                },
                expect => #{
                    code => 403
                }
            })
        end,
        % Make sure user CAN delete users or groups to spaces
        CanDeleteEntity = fun(EntityId, EntityType) ->
            Path = case EntityType of
                onedata_user ->
                    [<<"/spaces/">>, TestSpace, <<"/users/">>, EntityId];
                user_group ->
                    [<<"/spaces/">>, TestSpace, <<"/groups/">>, EntityId]

            end,
            check_rest_call(#{
                request => #{
                    method => delete,
                    path => Path,
                    auth => {user, TestUser}
                },
                expect => #{
                    code => 202
                }
            })
        end,

        %% PRIVILEGES AS A USER

        % TestUser should not be able to perform add operations
        % as he does not yet have privs
        ?assert(CannotAddEntity(AddedUser, onedata_user)),
        ?assert(CannotAddEntity(AddedGroup, user_group)),
        % Give him the privileges and check again
        ?assert(SetPrivileges(TestUser, onedata_user, [<<"add_member_to_space">>])),
        ?assert(CanAddEntity(AddedUser, onedata_user)),
        ?assert(CanAddEntity(AddedGroup, user_group)),
        % Revoke the privileges and make sure he cannot
        ?assert(SetPrivileges(TestUser, onedata_user, [])),
        ?assert(CannotAddEntity(AddedUser, onedata_user)),
        ?assert(CannotAddEntity(AddedGroup, user_group)),
        % The user should not be able to delete users/groups without privileges
        ?assert(CannotDeleteEntity(AddedUser, onedata_user)),
        ?assert(CannotDeleteEntity(AddedGroup, user_group)),
        % Give him the privileges and check again
        ?assert(SetPrivileges(TestUser, onedata_user,
            [<<"remove_member_from_space">>])),
        ?assert(CanDeleteEntity(AddedUser, onedata_user)),
        ?assert(CanDeleteEntity(AddedGroup, user_group)),
        % Revoke the privileges and make sure he cannot
        ?assert(SetPrivileges(TestUser, onedata_user, [])),
        ?assert(CannotDeleteEntity(AddedUser, onedata_user)),
        ?assert(CannotDeleteEntity(AddedGroup, user_group)),

        %% PRIVILEGES VIA GROUP

        % Add the user to a group and give it privileges, see if the user can
        % perform the operation.
        TestGroup = create_group_for_user(TestUser),
        % TestUser should not be able to perform add operations
        % as he does not yet have privs
        ?assert(CannotAddEntity(AddedUser, onedata_user)),
        ?assert(CannotAddEntity(AddedGroup, user_group)),
        % Give the privileges to his group and check again
        ?assert(SetPrivileges(TestGroup, user_group, [<<"add_member_to_space">>])),
        % Try multiple times, because group graph takes a while to update
        ?assertEqual(true, CanAddEntity(AddedUser, onedata_user), 10),% Try 10 times
        ?assertEqual(true, CanAddEntity(AddedGroup, user_group), 10), % Try 10 times
        % Revoke the privileges and make sure he cannot
        ?assert(SetPrivileges(TestGroup, user_group, [])),
        % Try multiple times, because group graph takes a while to update
        ?assertEqual(true, CannotAddEntity(AddedUser, onedata_user), 10),% 10 times
        ?assertEqual(true, CannotAddEntity(AddedGroup, user_group), 10), % 10 times
        % The user should not be able to delete users/groups without privileges
        ?assert(CannotDeleteEntity(AddedUser, onedata_user)),
        ?assert(CannotDeleteEntity(AddedGroup, user_group)),
        % Give him the privileges and check again
        ?assert(SetPrivileges(TestGroup, user_group,
            [<<"remove_member_from_space">>])),
        % Try multiple times, because group graph takes a while to update
        ?assertEqual(true, CanDeleteEntity(AddedUser, onedata_user), 10),% 10 times
        ?assertEqual(true, CanDeleteEntity(AddedGroup, user_group), 10), % 10 times
        % Revoke the privileges and make sure he cannot
        ?assert(SetPrivileges(TestGroup, user_group, [])),
        % Try multiple times, because group graph takes a while to update
        ?assertEqual(true, CannotDeleteEntity(AddedUser, onedata_user), 10),% 10 tms
        ?assertEqual(true, CannotDeleteEntity(AddedGroup, user_group), 10), % 10 tms

        %% PRIVILEGES VIA NESTED GROUPS

        % Add him to a nested group, which belongs to a group, which belongs to a
        % group that has the privileges and check if he can perform the operation.
        GrandChildGroup = create_group_for_user(TestUser),
        ChildGroup = create_group_for_group(GrandChildGroup),
        ParentGroup = create_group_for_group(ChildGroup),
        % TestUser should not be able to perform add operations
        % as he does not yet have privs
        ?assert(CannotAddEntity(AddedUser, onedata_user)),
        ?assert(CannotAddEntity(AddedGroup, user_group)),
        % Give the privileges to his group and check again
        ?assert(SetPrivileges(ParentGroup, user_group, [<<"add_member_to_space">>])),
        % Try multiple times, because group graph takes a while to update
        ?assertEqual(true, CanAddEntity(AddedUser, onedata_user), 10),% Try 10 times
        ?assertEqual(true, CanAddEntity(AddedGroup, user_group), 10), % Try 10 times
        % Revoke the privileges and make sure he cannot
        ?assert(SetPrivileges(ParentGroup, user_group, [])),
        % Try multiple times, because group graph takes a while to update
        ?assertEqual(true, CannotAddEntity(AddedUser, onedata_user), 10),% 10 times
        ?assertEqual(true, CannotAddEntity(AddedGroup, user_group), 10), % 10 times
        % The user should not be able to delete users/groups without privileges
        ?assert(CannotDeleteEntity(AddedUser, onedata_user)),
        ?assert(CannotDeleteEntity(AddedGroup, user_group)),
        % Give him the privileges and check again
        ?assert(SetPrivileges(ParentGroup, user_group,
            [<<"remove_member_from_space">>])),
        % Try multiple times, because group graph takes a while to update
        ?assertEqual(true, CanDeleteEntity(AddedUser, onedata_user), 10),% 10 times
        ?assertEqual(true, CanDeleteEntity(AddedGroup, user_group), 10), % 10 times
        % Revoke the privileges and make sure he cannot
        ?assert(SetPrivileges(ParentGroup, user_group, [])),
        % Try multiple times, because group graph takes a while to update
        ?assertEqual(true, CannotDeleteEntity(AddedUser, onedata_user), 10),% 10 tms
        ?assertEqual(true, CannotDeleteEntity(AddedGroup, user_group), 10), % 10 tms
        ok
    catch T:M ->
        ct:print("~p", [{T, M, erlang:get_stacktrace()}])
    end,
    ok.


%%%===================================================================
%%% Helper functions
%%%===================================================================

%%--------------------------------------------------------------------
%% Performs a REST call and check the output if it matches the expected.
%% Returns true when id does and mismatch details when it does not, so
%% it is strongly recommended to wrap the call to this function in an assertion.
%% Args map looks like following:
%% #{
%%    request => #{
%%      method => get, % Optional, default: get
%%      path => [<<"/parts">>, <<"/to/be">>, <<"/concatenated">>], % Mandatory
%%      headers => [{<<"key">>, <<"value">>}], % Optional, default: ct=app/json
%%      body => <<"body content">>, % Optional, default: <<"">>
%%      auth => {user, <<"uid">>} orelse none, % Optional, default: none
%%      opts => [http_client_option] % Optional, default: []
%%    },
%%    expect => #{
%%      code => 200, % Optional, by default not validated
%%      headers => [{<<"key">>, <<"value">>}], % Optional, by def. not validated
%%      body => <<"binary">> orelse #{} % Optional, by default not validated
%%      % Specifying a map here will cause validation of JSON content-wise
%%      % (if the JSON object specified by map is equal to the one in reply)
%%    }
%% }
%%--------------------------------------------------------------------
check_rest_call(ArgsMap) ->
    try
        RequestMap = maps:get(request, ArgsMap),
        ExpectMap = maps:get(expect, ArgsMap),

        ReqMethod = maps:get(method, RequestMap, get),
        ReqPath = case maps:get(path, RequestMap) of
            Bin when is_binary(Bin) ->
                [Bin];
            List ->
                List
        end,
        ReqHeaders = maps:get(headers, RequestMap, [
            {<<"content-type">>, <<"application/json">>}
        ]),
        ReqBody = case maps:get(body, RequestMap, <<"">>) of
            Bin2 when is_binary(Bin2) ->
                Bin2;
            Map2 when is_map(Map2) ->
                json_utils:encode_map(Map2)
        end,
        ReqAuth = maps:get(auth, RequestMap, none),
        ReqOpts = maps:get(opts, RequestMap, []),

        ExpCode = maps:get(code, ExpectMap, undefined),
        ExpHeaders = maps:get(headers, ExpectMap, undefined),
        ExpBody = maps:get(body, ExpectMap, undefined),

        URL = str_utils:join_binary([get_oz_url() | ReqPath], <<"">>),
        HeadersPlusAuth = case ReqAuth of
            none ->
                ReqHeaders;
            {user, UserId} ->
                [{<<"macaroon">>, get_user_auth(UserId)} | ReqHeaders]
        end,
        % Add insecure option - we do not want the GR server cert to be checked.
        {ok, RespCode, RespHeaders, RespBody} = http_client:request(
            ReqMethod, URL, HeadersPlusAuth, ReqBody, [insecure | ReqOpts]
        ),

        % Check response code if specified
        case ExpCode of
            undefined ->
                ok;
            _ ->
                case RespCode of
                    ExpCode ->
                        ok;
                    _ ->
                        throw({code, RespCode, ExpCode})
                end
        end,

        % Check response headers if specified
        case ExpHeaders of
            undefined ->
                ok;
            _ ->
                NormExpHeaders = normalize_headers(ExpHeaders),
                NormRespHeaders = normalize_headers(RespHeaders),
                case NormRespHeaders of
                    NormExpHeaders ->
                        ok;
                    _ ->
                        throw({headers, NormRespHeaders, NormExpHeaders})
                end
        end,

        % Check response body if specified
        case ExpBody of
            undefined ->
                ok;
            Bin3 when is_binary(Bin3) ->
                case RespBody of
                    ExpBody ->
                        ok;
                    _ ->
                        throw({body, RespBody, ExpBody})
                end;
            Map3 when is_map(Map3) ->
                RespBodyMap = json_utils:decode_map(RespBody),
                case compare_maps(RespBodyMap, ExpBody) of
                    true ->
                        ok;
                    false ->
                        throw({body, RespBodyMap, ExpBody})
                end
        end,

        % Everything OK, return true
        true
    catch
        % Something wrong, return details. If assert is used, the test will fail
        % and properly display the point of failure.
        {Type, Actual, Expected} ->
            {
                Type,
                {got, Actual},
                {expected, Expected}
            }
    end.


create_user() ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    {ok, UserId} = rpc:call(
        Node, user_logic, create, [#onedata_user{name = <<"whatever">>}]
    ),
    UserId.


create_group_for_user(UserId) ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    {ok, GroupId} = rpc:call(
        Node, group_logic, create, [UserId, <<"whatever">>, role]
    ),
    GroupId.


create_group_for_group(ChildGroupId) ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    % Create temp user that will create new group
    TempUser = create_user(),
    % Create a new group for TempUser
    {ok, ParentGroupId} = rpc:call(
        Node, group_logic, create, [
            TempUser, <<"whatever">>, role
        ]),
    % Get join group token
    Client = #client{type = user, id = TempUser},
    {ok, MacaroonBin} = rpc:call(
        Node, token_logic, create, [
            Client, group_invite_group_token, {group, ParentGroupId}
        ]
    ),
    {ok, Macaroon} = rpc:call(
        Node, token_utils, deserialize, [MacaroonBin]
    ),
    % Consume the token to add ChildGroup as a nested group to ParentGroup
    {ok, ParentGroupId} = rpc:call(
        Node, group_logic, join_group, [ChildGroupId, Macaroon]
    ),
    ParentGroupId.


create_space_for_user(UserId) ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    {ok, SpaceId} = rpc:call(
        Node, space_logic, create, [{user, UserId}, <<"whatever">>]
    ),
    SpaceId.


create_provider() ->
    [Node | _] = ?config(oz_worker_nodes, get_config()),
    % Generate CSR file
    Prefix = "provider" ++ integer_to_list(random:uniform(123345123)),
    KeyFile = filename:join(?TEMP_DIR, Prefix ++ "_key.pem"),
    CSRFile = filename:join(?TEMP_DIR, Prefix ++ "_csr.pem"),
    os:cmd("openssl genrsa -out " ++ KeyFile ++ " 2048"),
    os:cmd("openssl req -new -batch -key " ++ KeyFile ++ " -out " ++ CSRFile),
    {ok, CSR} = file:read_file(CSRFile),
    {ok, ProviderId, _} = rpc:call(
        Node, provider_logic, create, [
            <<"whatever">>,
            [<<"127.0.0.1">>],
            <<"127.0.0.1">>,
            CSR
        ]
    ),
    ProviderId.


remove_provider(ProviderId) ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    true = rpc:call(
        Node, provider_logic, remove, [ProviderId]
    ).


remove_space(SpaceId) ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    true = rpc:call(
        Node, space_logic, remove, [SpaceId]
    ).


remove_group(GroupId) ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    true = rpc:call(
        Node, group_logic, remove, [GroupId]
    ).


remove_user(UserId) ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    true = rpc:call(
        Node, user_logic, remove, [UserId]
    ).


remove_test_entities() ->
    Config = get_config(),
    [Node | _] = ?config(oz_worker_nodes, Config),
    % Delete all providers
    {ok, ProviderDocs} = rpc:call(Node, provider, list, []),
    [true = remove_provider(PId) || #document{key = PId} <- ProviderDocs],
    % Delete all spaces
    {ok, SpaceDocs} = rpc:call(Node, space, list, []),
    [true = remove_space(SId) || #document{key = SId} <- SpaceDocs],
    % Delete all groups
    {ok, GroupDocs} = rpc:call(Node, user_group, list, []),
    [true = remove_group(GId) || #document{key = GId} <- GroupDocs],
    % Delete all users
    {ok, UserDocs} = rpc:call(Node, onedata_user, list, []),
    [true = remove_user(UId) || #document{key = UId} <- UserDocs],
    ok.


support_space(SpaceId, UserId, ProviderId) ->
    [Node | _] = ?config(oz_worker_nodes, get_config()),
    Client = #client{type = user, id = UserId},
    {ok, MacaroonBin} = rpc:call(
        Node, token_logic, create, [
            Client, space_support_token, {space, SpaceId}
        ]
    ),
    {ok, Macaroon} = rpc:call(
        Node, token_utils, deserialize, [MacaroonBin]
    ),
    {ok, SpaceId} = rpc:call(
        Node, space_logic, support, [ProviderId, Macaroon, 10000000]
    ),
    SpaceId.


set_privileges(EntityId, EntityType, Privs) ->
    [Node | _] = ?config(oz_worker_nodes, get_config()),
    rpc:call(
        Node, oz_api_privileges_logic, modify, [EntityId, EntityType, Privs]
    ).


get_all_privileges() ->
    [Node | _] = ?config(oz_worker_nodes, get_config()),
    rpc:call(Node, oz_api_privileges, all_privileges, []).


get_user_auth(UserId) ->
    % Cache user auth tokens, if none in cache create a new one.
    case get({macaroon, UserId}) of
        undefined ->
            [Node | _] = ?config(oz_worker_nodes, get_config()),
            Macaroon = rpc:call(
                Node, auth_logic, gen_token, [UserId]
            ),
            put({macaroon, UserId}, Macaroon),
            Macaroon;
        Macaroon ->
            Macaroon
    end.


get_oz_url() ->
    Config = get_config(),
    RestURLs = ?config(restURLs, Config),
    random:seed(erlang:timestamp()),
    lists:nth(random:uniform(length(RestURLs)), RestURLs).


get_node_ip(Node) ->
    CMD = string:join([
        "docker inspect",
        "--format '{{ .NetworkSettings.IPAddress }}'",
        utils:get_host(Node)
    ], " "),
    re:replace(os:cmd(CMD), "\\s+", "", [global, {return, binary}]).


% Convert all header keys to lowercase so comparing is easier
normalize_headers(Headers) ->
    lists:sort(
        lists:map(fun({Key, Value}) ->
            KeyLower = list_to_binary(string:to_lower(binary_to_list(Key))),
            {KeyLower, Value}
        end, Headers)
    ).


% Returns true if two maps have the same contents
compare_maps(Map1, Map2) ->
    sort_map(Map1) =:= sort_map(Map2).


% Sorts all nested lists in a map and returns the result map
sort_map(OriginalMap) ->
    lists:foldl(
        fun(Key, MapAcc) ->
            case maps:get(Key, MapAcc) of
                List when is_list(List) ->
                    maps:put(Key, lists:sort(List), MapAcc);
                Map when is_map(Map) ->
                    maps:put(Key, sort_map(Map), MapAcc);
                _ ->
                    MapAcc
            end
        end, OriginalMap, maps:keys(OriginalMap)).


put_config(Config) ->
    put(config, Config).


get_config() ->
    get(config).

%%%===================================================================
%%% Setup/teardown functions
%%%===================================================================

init_per_suite(Config) ->
    application:start(etls),
    hackney:start(),
    NewConfig = ?TEST_INIT(Config, ?TEST_FILE(Config, "env_desc.json")),
    Nodes = ?config(oz_worker_nodes, NewConfig),
    RestURLs = lists:map(fun(Node) ->
        NodeIP = get_node_ip(Node),
        {ok, RestPort} = rpc:call(
            Node, application, get_env, [?APP_Name, rest_port]
        ),
        {ok, RestAPIPrefix} = rpc:call(
            Node, application, get_env, [?APP_Name, rest_api_prefix]
        ),
        str_utils:format_bin(
            "https://~s:~B~s", [NodeIP, RestPort, RestAPIPrefix]
        )
    end, Nodes),
    [{restURLs, RestURLs} | NewConfig].

end_per_suite(Config) ->
    hackney:stop(),
    application:stop(etls),
    test_node_starter:clean_environment(Config).

end_per_testcase(_, Config) ->
    % Remove everything that was created during a testcase
    put_config(Config),
    remove_test_entities().