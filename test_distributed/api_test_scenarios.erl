%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2017 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @doc
%%% Framework test scenarios used across different api SUITES.
%%% @end
%%%-------------------------------------------------------------------
-module(api_test_scenarios).
-author("Lukasz Opiola").

-include("registered_names.hrl").
-include("api_test_utils.hrl").
-include("rest.hrl").
-include("entity_logic.hrl").
-include("errors.hrl").
-include_lib("datastore/oz_datastore_models_def.hrl").
-include_lib("ctool/include/test/test_utils.hrl").

-export([run_scenario/2]).
-export([get_privileges/5]).

run_scenario(Function, Args) ->
    try
        erlang:apply(?MODULE, Function, Args),
        true
    catch
        throw:fail ->
            false;
        Type:Message ->
            ct:print(
                "Unexpected error in ~p:run_scenario - ~p:~p~nStacktrace: ~p",
                [?MODULE, Type, Message, erlang:get_stacktrace()]
            )
    end.


%% AllPrivs :: [atom()].
get_privileges(Config, ApiTestSpec, SetPrivsFun, InitialPrivs, AllPrivs) ->
    % Function that returns api_test_spec with given expected privileges.
    ExpectPrivileges = fun(TypeOfExpectation, PrivilegesAtoms) ->
        PrivilegesBin = [atom_to_binary(P, utf8) || P <- PrivilegesAtoms],
        {RestExpectation, LogicExpectation} = case TypeOfExpectation of
            exact -> {
                #{<<"privileges">> => PrivilegesBin},
                ?OK_LIST(PrivilegesAtoms)
            };
            contains -> {
                #{<<"privileges">> => {list_contains, PrivilegesBin}},
                ?OK_LIST_CONTAINS(PrivilegesAtoms)
            };
            doesnt_contain -> {
                #{<<"privileges">> => {list_doesnt_contain, PrivilegesBin}},
                ?OK_LIST_DOESNT_CONTAIN(PrivilegesAtoms)
            }
        end,
        #api_test_spec{
            rest_spec = RestSpec, logic_spec = LogicSpec
        } = ApiTestSpec,
        ApiTestSpec#api_test_spec{
            rest_spec = RestSpec#rest_spec{
                expected_body = RestExpectation
            },
            logic_spec = LogicSpec#logic_spec{
                expected_result = LogicExpectation
            }
        }
    end,
    % Check if endpoint returns InitialPrivileges as expected.
    assert(api_test_utils:run_tests(
        Config, ExpectPrivileges(exact, InitialPrivs))
    ),
    % Try SETing all possible sublists of privileges and check if they are
    % correctly returned.
    Sublists = [lists:sublist(AllPrivs, I) || I <- lists:seq(1, length(AllPrivs))],
    lists:foreach(
        fun(PrivsSublist) ->
            SetPrivsFun(set, PrivsSublist),
            assert(api_test_utils:run_tests(
                Config, ExpectPrivileges(exact, PrivsSublist))
            )
        end, Sublists),
    % Try GRANTing all sublists of privileges and check if they are included
    % in privileges.
    lists:foreach(
        fun(PrivsSublist) ->
            % First set random privileges and then grant a sublist of privileges
            % (it should not matter what privileges were set before, after
            % GRANTing new ones they should all be present)
            SetPrivsFun(set, lists:sublist(AllPrivs, rand:uniform(length(AllPrivs)))),
            SetPrivsFun(grant, PrivsSublist),
            assert(api_test_utils:run_tests(
                Config, ExpectPrivileges(contains, PrivsSublist))
            )
        end, Sublists),
    % Try REVOKing all sublists of privileges and check if they are not included
    % in privileges.
    lists:foreach(
        fun(PrivsSublist) ->
            % First set random privileges and then revoke a sublist of privileges
            % (it should not matter what privileges were set before, after
            % REVOKing new ones they should all be absent)
            SetPrivsFun(set, lists:sublist(AllPrivs, rand:uniform(length(AllPrivs)))),
            SetPrivsFun(revoke, PrivsSublist),
            assert(api_test_utils:run_tests(
                Config, ExpectPrivileges(doesnt_contain, PrivsSublist))
            )
        end, Sublists).


assert(true) ->
    ok;
assert(_) ->
    throw(fail).


