%%% @author Wojciech Geisler
%%% @copyright (C): 2017 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This file contains tests concerning DNS server shipped with OneZone
%%% and OneProvider subdomain delegation.
%%% @end
%%%-------------------------------------------------------------------
-module(dns_test_SUITE).
-author("Wojciech Geisler").

-include("registered_names.hrl").
-include("datastore/oz_datastore_models.hrl").
-include_lib("cluster_worker/include/api_errors.hrl").
-include_lib("ctool/include/test/test_utils.hrl").
-include_lib("ctool/include/logging.hrl").
-include_lib("ctool/include/test/assertions.hrl").
-include_lib("ctool/include/test/performance.hrl").
-include_lib("ctool/include/global_definitions.hrl").

-type config() :: [{atom(), term()}].

%% API
-export([all/0, init_per_suite/1, end_per_suite/1, end_per_testcase/2]).
-export([
    dns_server_resolves_oz_domain_test/1,
    dns_state_stores_provider_data_test/1,
    dns_server_resolves_delegated_subdomain_test/1,
    dns_server_resolves_changed_subdomain_test/1,
    update_fails_on_duplicated_subdomain_test/1,
    dns_server_resolves_ns_records_test/1,
    dns_server_duplicates_ns_records_test/1,
    dns_server_resolves_static_subdomains_test/1,
    static_subdomain_does_not_shadow_provider_subdomain_test/1,
    dns_server_does_not_resolve_removed_subdomain_test/1
]).


all() -> ?ALL([
    dns_server_resolves_oz_domain_test,
    dns_state_stores_provider_data_test,
    dns_server_resolves_delegated_subdomain_test,
    dns_server_resolves_changed_subdomain_test,
    update_fails_on_duplicated_subdomain_test,
    dns_server_resolves_ns_records_test,
    dns_server_duplicates_ns_records_test,
    dns_server_resolves_static_subdomains_test,
    static_subdomain_does_not_shadow_provider_subdomain_test,
    dns_server_does_not_resolve_removed_subdomain_test
]).

-define(DNS_ASSERT_RETRY_COUNT, 7).
-define(DNS_ASSERT_RETRY_DELAY, timer:seconds(5)).

%%%===================================================================
%%% Example data
%%%===================================================================
-define(PROVIDER_NAME1, <<"test_provider">>).
-define(PROVIDER_NAME2, <<"second_provider">>).
-define(PROVIDER_IPS1, lists:sort([{240,1,1,0}, {240,1,1,1}, {240,1,1,2}])).
-define(PROVIDER_IPS2, lists:sort([{241,1,1,0}, {241,1,1,1}, {241,1,1,2}])).
-define(STATIC_SUBDOMAIN_IPS1, lists:sort([{1,2,3,4}, {5,6,7,8}])).
-define(STATIC_SUBDOMAIN_IPS2, lists:sort([{122, 255, 255, 32}])).
-define(PROVIDER_SUBDOMAIN1, "provsub").
-define(PROVIDER_SUBDOMAIN2, "other-provsub").
-define(EXTERNAL_DOMAIN1, "domain.org").


%%%===================================================================
%%% Setup/Teardown functions
%%%===================================================================

-spec init_per_suite(config()) -> config().
init_per_suite(Config) ->
    Posthook = fun(NewConfig) ->
        Nodes = ?config(oz_worker_nodes, NewConfig),
        IPstrings = lists:map(fun binary_to_list/1,
                              lists:map(fun test_utils:get_docker_ip/1,
                                        Nodes)),
        IPs = lists:map(fun(IPstring) ->
            {ok, IP} = inet:parse_ipv4strict_address(IPstring),
            IP
        end, IPstrings),

        {ok, ZoneDomain} = oz_test_utils:get_oz_domain(NewConfig),
        [{oz_domain, ZoneDomain}, {oz_ips, lists:sort(IPs)} | NewConfig]
    end,
    [{env_up_posthook, Posthook}, {?LOAD_MODULES, [oz_test_utils]}| Config].


end_per_suite(_Config) ->
    ok.

end_per_testcase(static_subdomain_does_not_shadow_provider_subdomain_test, Config) ->
    set_dns_config(Config, static_entries, []),
    oz_test_utils:delete_all_entities(Config),
    ok;

end_per_testcase(_, Config) ->
    % prevent "subdomain occupied" errors
    oz_test_utils:delete_all_entities(Config),
    ok.


%%%===================================================================
%%% API functions
%%%===================================================================


%%--------------------------------------------------------------------
%% @doc
%% OneZone dns, working on every node, should respond with IPs of all OneZone
%% nodes.
%% @end
%%--------------------------------------------------------------------
dns_server_resolves_oz_domain_test(Config) ->
    OZ_IPs = ?config(oz_ips, Config),
    OZ_Domain = ?config(oz_domain, Config),

    assert_dns_answer(OZ_IPs, OZ_Domain, a, OZ_IPs).


%%--------------------------------------------------------------------
%% @doc
%% When subdomain delegation is enabled for a provider, dns_state provides
%% information about its subdomain.
%% @end
%%--------------------------------------------------------------------
dns_state_stores_provider_data_test(Config) ->
    %% given
    ProviderName = ?PROVIDER_NAME1,
    SubdomainBin = <<?PROVIDER_SUBDOMAIN1>>,
    ProviderIPs = ?PROVIDER_IPS1,

    %% when
    {ok, {ProviderId, _, _}} = oz_test_utils:create_provider_and_certs(
        Config, ProviderName),
    oz_test_utils:enable_subdomain_delegation(
        Config, ProviderId, SubdomainBin, ProviderIPs),

    %% then
    ?assertEqual({ok, SubdomainBin, ProviderIPs}, oz_test_utils:call_oz(Config,
        dns_state, get_delegation_config, [ProviderId])),

    StIP = oz_test_utils:call_oz(Config,
        dns_state, get_subdomains_to_ips, []),
    ?assertEqual(ProviderIPs, lists:sort(maps:get(SubdomainBin, StIP))).


%%--------------------------------------------------------------------
%% @doc
%% DNS on all OZ nodes should resolve provider domain built from subdomain
%% and oz domain
%% @end
%%--------------------------------------------------------------------
dns_server_resolves_delegated_subdomain_test(Config) ->
    %% given
    Name = ?PROVIDER_NAME1,
    ProviderIPs = ?PROVIDER_IPS1,
    OZIPs = ?config(oz_ips, Config),

    Subdomain = ?PROVIDER_SUBDOMAIN1,
    SubdomainBin = <<?PROVIDER_SUBDOMAIN1>>,
    OZDomain = ?config(oz_domain, Config),
    FullDomain = Subdomain ++ "." ++ OZDomain,

    %% when
    {ok, {ProviderId, _, _}} = oz_test_utils:create_provider_and_certs(Config, Name),
    oz_test_utils:enable_subdomain_delegation(
        Config, ProviderId, SubdomainBin, ProviderIPs),

    %% then
    {ok, ProviderDoc} = oz_test_utils:get_provider(Config, ProviderId),
    ?assertEqual(list_to_binary(FullDomain), ProviderDoc#od_provider.domain),
    assert_dns_answer(OZIPs, FullDomain, a, ProviderIPs).


%%--------------------------------------------------------------------
%% @doc
%% When subdomain delegation is set with a different subdomain, dns server
%% should stop resolving old subdomain and start resolving new.
%% @end
%%--------------------------------------------------------------------
dns_server_resolves_changed_subdomain_test(Config) ->
    %% given
    Name = ?PROVIDER_NAME1,
    ProviderIPs = ?PROVIDER_IPS1,
    OZIPs = ?config(oz_ips, Config),

    OZDomain = ?config(oz_domain, Config),
    Subdomain1 = ?PROVIDER_SUBDOMAIN1,
    SubdomainBin1 = <<?PROVIDER_SUBDOMAIN1>>,
    FullDomain1 = Subdomain1 ++ "." ++ OZDomain,

    Subdomain2 = ?PROVIDER_SUBDOMAIN2,
    SubdomainBin2 = <<?PROVIDER_SUBDOMAIN2>>,
    FullDomain2 = Subdomain2 ++ "." ++ OZDomain,

    %% when
    {ok, {ProviderId, _, _}} = oz_test_utils:create_provider_and_certs(Config, Name),
    oz_test_utils:enable_subdomain_delegation(
        Config, ProviderId, SubdomainBin1, ProviderIPs),

    assert_dns_answer(OZIPs, FullDomain1, a, ProviderIPs),

    oz_test_utils:enable_subdomain_delegation(
        Config, ProviderId, SubdomainBin2, ProviderIPs),

    %% then
    assert_dns_answer(OZIPs, FullDomain1, a, []),
    assert_dns_answer(OZIPs, FullDomain2, a, ProviderIPs).


%%--------------------------------------------------------------------
%% @doc
%% DNS zone should have a number of NS records pointing to nsX subdomains.
%% Those subdomains should be resolved to OZ nodes ips.
%% Their number is limited by config.
%% @end
%%--------------------------------------------------------------------
dns_server_resolves_ns_records_test(Config) ->
    OZIPs = ?config(oz_ips, Config),
    OZDomain = ?config(oz_domain, Config),

    Maximum = 2,
    set_dns_config(Config, ns_max_entries, Maximum),
    set_dns_config(Config, ns_min_entries, 1), % the basic case

    % force dns update
    ?assertEqual(ok, oz_test_utils:call_oz(Config,
        node_manager_plugin, reconcile_dns_config, [])),

    % number of nodes based on env_desc
    [IP1, IP2, IP3] = NSIPs = lists:sort(OZIPs),
    NSDomainsIPs = [{"ns1." ++ OZDomain, [IP1]}, {"ns2." ++ OZDomain, [IP2]}],
    {NSDomains, _} = lists:unzip(NSDomainsIPs),

    assert_dns_answer(OZIPs, OZDomain, ns, NSDomains),
    % all NS records have associated A records
    lists:foreach(fun({Domain, IPs}) ->
        assert_dns_answer(OZIPs, Domain, a, IPs)
    end, NSDomainsIPs).


%%--------------------------------------------------------------------
%% @doc
%% Configuration variable can be used to force resolving more
%% nsX domains than there are nodes.
%% @end
%%--------------------------------------------------------------------
dns_server_duplicates_ns_records_test(Config) ->
    OZIPs = ?config(oz_ips, Config),
    OZDomain = ?config(oz_domain, Config),

    Minimum = 4,
    Maximum = 5,
    set_dns_config(Config, ns_max_entries, Maximum),
    set_dns_config(Config, ns_min_entries, Minimum),

    % force dns update
    ?assertEqual(ok, oz_test_utils:call_oz(Config,
        node_manager_plugin, reconcile_dns_config, [])),

    % number of nodes based on env_desc
    [IP1, IP2, IP3] = NSIPs = lists:sort(OZIPs),
    NSDomainsIPs = [{"ns1." ++ OZDomain, [IP1]}, {"ns2." ++ OZDomain, [IP2]},
        {"ns3." ++ OZDomain, [IP3]}, {"ns4." ++ OZDomain, [IP1]}],
    {NSDomains, _} = lists:unzip(NSDomainsIPs),

    assert_dns_answer(OZIPs, OZDomain, ns, NSDomains),
    % all NS records have associated A records
    lists:foreach(fun({Domain, IPs}) ->
        assert_dns_answer(OZIPs, Domain, a, IPs)
    end, NSDomainsIPs).



%%--------------------------------------------------------------------
%% @doc
%% A subdomain must not be set for a provider if the subdomain is
%% already in use elsewhere.
%% @end
%%--------------------------------------------------------------------
update_fails_on_duplicated_subdomain_test(Config) ->
    Name1 = ?PROVIDER_NAME1,
    Name2 = ?PROVIDER_NAME2,
    SubdomainBin = <<?PROVIDER_SUBDOMAIN1>>,
    StaticSubdomain = <<"test">>,

    set_dns_config(Config, static_entries, [{StaticSubdomain, [{1,1,1,1}]}]),
    {ok, {P1, _, _}} = oz_test_utils:create_provider_and_certs(Config, Name1),
    {ok, {P2, _, _}} = oz_test_utils:create_provider_and_certs(Config, Name2),


    oz_test_utils:enable_subdomain_delegation(Config, P1, SubdomainBin, []),

    Data = #{
      <<"subdomainDelegation">> => true,
      <<"subdomain">> => SubdomainBin,
      <<"ipList">> => []},

    % subdomain used by another provider
    ?assertMatch(?ERROR_BAD_VALUE_IDENTIFIER_OCCUPIED(<<"subdomain">>),
        oz_test_utils:call_oz(Config,
            provider_logic, update_domain_config, [#client{type = root}, P2, Data])
    ),

    % subdomain reserved for nameserver
    Data2 = Data#{<<"subdomain">> := <<"ns19">>},
    ?assertMatch(?ERROR_BAD_VALUE_IDENTIFIER_OCCUPIED(<<"subdomain">>),
        oz_test_utils:call_oz(Config,
            provider_logic, update_domain_config, [#client{type = root}, P2, Data2])
    ),

    % subdomain configured in app config
    Data3 = Data#{<<"subdomain">> := StaticSubdomain},
    ?assertMatch(?ERROR_BAD_VALUE_IDENTIFIER_OCCUPIED(<<"subdomain">>),
        oz_test_utils:call_oz(Config,
            provider_logic, update_domain_config, [#client{type = root}, P2, Data3])
    ).


%%--------------------------------------------------------------------
%% @doc
%% DNS server should resolve subdomains configured in application config.
%% @end
%%--------------------------------------------------------------------
dns_server_resolves_static_subdomains_test(Config) ->
    OZIPs = ?config(oz_ips, Config),
    OZDomain = ?config(oz_domain, Config),

    Subdomains = ["mail", "test"],
    StaticIPs = [?STATIC_SUBDOMAIN_IPS1, ?STATIC_SUBDOMAIN_IPS2],
    SubdomainsIPs = lists:zipwith(fun(Domain, IPs) ->
        {list_to_binary(Domain), IPs}
    end, Subdomains, StaticIPs),
    DomainsIPs  = lists:zipwith(fun(Domain, IPs) ->
        {Domain ++ "." ++ OZDomain, IPs}
    end, Subdomains, StaticIPs),

    set_dns_config(Config, static_entries, SubdomainsIPs),

    % force dns update
    ?assertEqual(ok, oz_test_utils:call_oz(Config,
        node_manager_plugin, reconcile_dns_config, [])),

    lists:foreach(fun({Domain, IPs}) ->
        assert_dns_answer(OZIPs, Domain, a, IPs)
    end, DomainsIPs).



%%--------------------------------------------------------------------
%% @doc
%% When a static subdomain entry is set after a provider has registered
%% with the same subdomain the provider subdomain should take precedence.
%% @end
%%--------------------------------------------------------------------
static_subdomain_does_not_shadow_provider_subdomain_test(Config) ->
    %% given
    ProviderName = ?PROVIDER_NAME1,
    ProviderIPs1 = ?PROVIDER_IPS1,
    StaticIPs = ?STATIC_SUBDOMAIN_IPS1,

    OZIPs = ?config(oz_ips, Config),

    Subdomain = ?PROVIDER_SUBDOMAIN1,
    SubdomainBin = <<?PROVIDER_SUBDOMAIN1>>,
    OZDomain = ?config(oz_domain, Config),
    FullDomain = Subdomain ++ "." ++ OZDomain,

    % provider uses a subdomain
    {ok, {ProviderId, _, _}} = oz_test_utils:create_provider_and_certs(Config,
        ProviderName),
    oz_test_utils:enable_subdomain_delegation(
        Config, ProviderId, SubdomainBin, ProviderIPs1),

    % subdomain is set as static entry statically
    set_dns_config(Config, static_entries, [{SubdomainBin, StaticIPs}]),

    % DNS update is sent
    ?assertEqual(ok, oz_test_utils:call_oz(Config,
        node_manager_plugin, reconcile_dns_config, [])),

    % provider IPs are still resolved
    assert_dns_answer(OZIPs, FullDomain, a, ProviderIPs1).


%%--------------------------------------------------------------------
%% @doc
%% When subdomain delegation is disabled, dns server should stop resolving old
%% subdomain.
%% @end
%%--------------------------------------------------------------------
dns_server_does_not_resolve_removed_subdomain_test(Config) ->
    %% given
    Name = ?PROVIDER_NAME1,
    ProviderIPs = ?PROVIDER_IPS1,
    OZIPs = ?config(oz_ips, Config),

    OZDomain = ?config(oz_domain, Config),
    Subdomain = ?PROVIDER_SUBDOMAIN1,
    SubdomainBin = <<?PROVIDER_SUBDOMAIN1>>,
    FullDomain = Subdomain ++ "." ++ OZDomain,

    Domain = ?EXTERNAL_DOMAIN1,
    DomainBin = list_to_binary(Domain),

    %% when
    {ok, {ProviderId, _, _}} = oz_test_utils:create_provider_and_certs(Config, Name),
    oz_test_utils:enable_subdomain_delegation(
        Config, ProviderId, SubdomainBin, ProviderIPs),

    assert_dns_answer(OZIPs, FullDomain, a, ProviderIPs),

    % disable subdomain delegation
    oz_test_utils:set_provider_domain(Config, ProviderId, DomainBin),

    %% then
    assert_dns_answer(OZIPs, FullDomain, a, []),
    % this domain should not be handled by OZ dns
    assert_dns_answer(OZIPs, DomainBin, a, []).


%%%===================================================================
%%% Utils
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Verifies that all provided dns servers respond with expected
%% set of values. Does not verify order of received data.
%% @end
%%--------------------------------------------------------------------
-spec assert_dns_answer(Servers :: [inet:ip4_address()],
    Query :: string(), Type :: inet_res:rr_type(),
    Expected :: [inet_res:dns_data()]) ->
    ok | no_return().
assert_dns_answer(Servers, Query, Type, Expected) ->
    assert_dns_answer(Servers, Query, Type, Expected, ?DNS_ASSERT_RETRY_COUNT).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Verifies that all provided dns servers respond with expected
%% set of values. Does not verify order of received data.
%% Allows custom retries count.
%% @end
%%--------------------------------------------------------------------
-spec assert_dns_answer(Servers :: [inet:ip4_address()],
    Query :: string(), Type :: inet_res:r_type(),
    Expected :: [inet_res:dns_data()], Retries :: integer()) ->
    ok | no_return().
assert_dns_answer(Servers, Query, Type, Expected, Attempts) ->
    SortedExpected = lists:sort(Expected),
    lists:foreach(fun(Server) ->
        Opts = [{nameservers, [{Server, 53}]}],

        % there are multiple, delayed attempts because inet_res:lookup
        % displays ~20 seconds delay before returning updated results
        try
            ?assertEqual(SortedExpected,
                         lists:sort(inet_res:lookup(Query, any, Type, Opts)),
                         Attempts, ?DNS_ASSERT_RETRY_DELAY)
        catch error:{assertEqual_failed, _} = Error ->
            ct:print("DNS query type ~p to server ~p for name ~p "
                     "returned incorrect results in ~p attempts.",
                     [Type, Server, Query, Attempts]),
            erlang:error(Error)
        end
    end, Servers).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Adds property to the dns config proplist.
%% @end
%%--------------------------------------------------------------------
-spec set_dns_config(Config :: term(), Key :: term(), Value :: term()) -> ok.
set_dns_config(Config, Key, Value) ->
    OldConfig = oz_test_utils:call_oz(Config,
        application, get_env, [?APP_NAME, dns, []]),
    Nodes = ?config(oz_worker_nodes, Config),
    test_utils:set_env(Nodes, ?APP_NAME, dns,
        lists:keystore(Key, 1, OldConfig, {Key, Value})).