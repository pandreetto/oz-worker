%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module implements entity logic plugin behaviour and handles
%%% entity logic operations corresponding to od_provider model.
%%% @end
%%%-------------------------------------------------------------------
-module(provider_logic_plugin).
-author("Lukasz Opiola").
-behaviour(entity_logic_plugin_behaviour).

-include("tokens.hrl").
-include("entity_logic.hrl").
-include("datastore/oz_datastore_models.hrl").
-include_lib("ctool/include/logging.hrl").
-include_lib("ctool/include/privileges.hrl").
-include_lib("cluster_worker/include/api_errors.hrl").

-export([fetch_entity/1, operation_supported/3]).
-export([create/1, get/2, update/1, delete/1]).
-export([exists/2, authorize/2, validate/1]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Retrieves an entity from datastore based on its EntityId.
%% Should return ?ERROR_NOT_FOUND if the entity does not exist.
%% @end
%%--------------------------------------------------------------------
-spec fetch_entity(entity_logic:entity_id()) ->
    {ok, entity_logic:entity()} | entity_logic:error().
fetch_entity(ProviderId) ->
    case od_provider:get(ProviderId) of
        {ok, #document{value = Provider}} ->
            {ok, Provider};
        _ ->
            ?ERROR_NOT_FOUND
    end.


%%--------------------------------------------------------------------
%% @doc
%% Determines if given operation is supported based on operation, aspect and
%% scope (entity type is known based on the plugin itself).
%% @end
%%--------------------------------------------------------------------
-spec operation_supported(entity_logic:operation(), entity_logic:aspect(),
    entity_logic:scope()) -> boolean().
operation_supported(create, instance, private) -> true;
operation_supported(create, instance_dev, private) -> true;
operation_supported(create, support, private) -> true;
operation_supported(create, check_my_ports, private) -> true;
operation_supported(create, map_idp_group, private) -> true;

operation_supported(get, list, private) -> true;

operation_supported(get, instance, private) -> true;
operation_supported(get, instance, protected) -> true;

operation_supported(get, eff_users, private) -> true;
operation_supported(get, eff_groups, private) -> true;
operation_supported(get, spaces, private) -> true;
operation_supported(get, {check_my_ip, _}, private) -> true;
operation_supported(get, domain_config, private) -> true;

operation_supported(update, instance, private) -> true;
operation_supported(update, {space, _}, private) -> true;
operation_supported(update, domain_config, private) -> true;

operation_supported(delete, instance, private) -> true;
operation_supported(delete, {space, _}, private) -> true;

operation_supported(_, _, _) -> false.


%%--------------------------------------------------------------------
%% @doc
%% Creates a resource (aspect of entity) based on entity logic request.
%% @end
%%--------------------------------------------------------------------
-spec create(entity_logic:req()) -> entity_logic:create_result().
create(Req = #el_req{gri = #gri{id = undefined, aspect = instance} = GRI}) ->
    Data = Req#el_req.data,
    Name = case maps:get(<<"name">>, Data, undefined) of
        undefined ->
            maps:get(<<"clientName">>, Data);
        N ->
            N
    end,
    CSR = maps:get(<<"csr">>, Data),
    Latitude = maps:get(<<"latitude">>, Data, 0.0),
    Longitude = maps:get(<<"longitude">>, Data, 0.0),
    SubdomainDelegation = maps:get(<<"subdomainDelegation">>, Data),

    ProviderId = datastore_utils:gen_key(),
    case worker_proxy:call(ozpca_worker, {sign_provider_req, ProviderId, CSR}) of
        {error, bad_csr} ->
            ?ERROR_BAD_DATA(<<"csr">>);
        {ok, {ProviderCertPem, Serial}} ->
            {Domain, Subdomain} = case SubdomainDelegation of
                false ->
                    {maps:get(<<"domain">>, Data), undefined};
                true ->
                    ReqSubdomain = maps:get(<<"subdomain">>, Data),
                    IPs = maps:get(<<"ipList">>, Data),
                    case dns_state:set_delegation_config(ProviderId, ReqSubdomain, IPs) of
                        ok ->
                            {dns_config:build_fqdn_from_subdomain(ReqSubdomain),
                             ReqSubdomain};
                        {error, subdomain_exists} ->
                            throw(?ERROR_BAD_VALUE_IDENTIFIER_OCCUPIED(<<"subdomain">>))
                    end
                end,

            Provider = #od_provider{
                name = Name, subdomain_delegation = SubdomainDelegation,
                domain = Domain, subdomain = Subdomain,
                serial = Serial, latitude = Latitude, longitude = Longitude},

            case od_provider:create(#document{key = ProviderId, value = Provider}) of
                {ok, _} -> ok;
                Error ->
                    dns_state:remove_delegation_config(ProviderId),
                    throw(?ERROR_INTERNAL_SERVER_ERROR)
            end,
            {ok, {fetched, GRI#gri{id = ProviderId}, {Provider, ProviderCertPem}}}
    end;

create(Req = #el_req{gri = #gri{id = undefined, aspect = instance_dev} = GRI}) ->
    Data = Req#el_req.data,
    Name = case maps:get(<<"name">>, Data, undefined) of
        undefined ->
            maps:get(<<"clientName">>, Data);
        N ->
            N
    end,
    CSR = maps:get(<<"csr">>, Data),
    Latitude = maps:get(<<"latitude">>, Data, undefined),
    Longitude = maps:get(<<"longitude">>, Data, undefined),
    SubdomainDelegation = maps:get(<<"subdomainDelegation">>, Data),
    UUID = maps:get(<<"uuid">>, Data, undefined),

    ProviderId = UUID,
    case worker_proxy:call(ozpca_worker, {sign_provider_req, ProviderId, CSR}) of
        {error, bad_csr} ->
            ?ERROR_BAD_DATA(<<"csr">>);
        {ok, {ProviderCertPem, Serial}} ->

            {Domain, Subdomain} = case SubdomainDelegation of
                false ->
                    {maps:get(<<"domain">>, Data), undefined};
                true ->
                    ReqSubdomain = maps:get(<<"subdomain">>, Data),
                    IPs = maps:get(<<"ipList">>, Data),
                    case dns_state:set_delegation_config(ProviderId, ReqSubdomain, IPs) of
                        ok ->
                            {dns_config:build_fqdn_from_subdomain(ReqSubdomain),
                             ReqSubdomain};
                        {error, subdomain_exists} ->
                            throw(?ERROR_BAD_VALUE_IDENTIFIER_OCCUPIED(<<"subdomain">>))
                    end
                end,

            Provider = #od_provider{
                name = Name, subdomain_delegation = SubdomainDelegation,
                domain = Domain, subdomain = Subdomain,
                serial = Serial, latitude = Latitude, longitude = Longitude},

            case od_provider:create(#document{key = ProviderId, value = Provider}) of
                {ok, _} -> ok;
                Error ->
                    dns_state:remove_delegation_config(ProviderId),
                    throw(Error)
            end,
            {ok, {fetched, GRI#gri{id = ProviderId}, {Provider, ProviderCertPem}}}
    end;

create(#el_req{gri = #gri{id = ProviderId, aspect = support}, data = Data}) ->
    SupportSize = maps:get(<<"size">>, Data),
    Macaroon = maps:get(<<"token">>, Data),
    {ok, {od_space, SpaceId}} = token_logic:consume(Macaroon),
    entity_graph:add_relation(
        od_space, SpaceId, od_provider, ProviderId, SupportSize
    ),
    NewGRI = #gri{type = od_space, id = SpaceId, aspect = instance, scope = protected},
    {ok, {not_fetched, NewGRI}};

create(Req = #el_req{gri = #gri{aspect = check_my_ports}}) ->
    try
        {ok, {data, test_connection(Req#el_req.data)}}
    catch _:_ ->
        ?ERROR_INTERNAL_SERVER_ERROR
    end;

create(#el_req{gri = #gri{aspect = map_idp_group}, data = Data}) ->
    ProviderId = maps:get(<<"idp">>, Data),
    GroupId = maps:get(<<"groupId">>, Data),
    MembershipSpec = auth_utils:normalize_membership_spec(
        binary_to_atom(ProviderId, latin1), GroupId),
    GroupSpec = idp_group_mapping:membership_spec_to_group_spec(MembershipSpec),
    {ok, {data, idp_group_mapping:group_spec_to_db_id(GroupSpec)}}.


%%--------------------------------------------------------------------
%% @doc
%% Retrieves a resource (aspect of entity) based on entity logic request and
%% prefetched entity.
%% @end
%%--------------------------------------------------------------------
-spec get(entity_logic:req(), entity_logic:entity()) ->
    entity_logic:get_result().
get(#el_req{gri = #gri{aspect = list}}, _) ->
    {ok, ProviderDocs} = od_provider:list(),
    {ok, [ProviderId || #document{key = ProviderId} <- ProviderDocs]};

get(#el_req{gri = #gri{aspect = instance, scope = private}}, Provider) ->
    {ok, Provider};
get(#el_req{gri = #gri{aspect = instance, scope = protected}}, Provider) ->
    #od_provider{
        name = Name, domain = Domain,
        latitude = Latitude, longitude = Longitude
    } = Provider,
    {ok, #{
        <<"name">> => Name, <<"domain">> => Domain,
        <<"latitude">> => Latitude, <<"longitude">> => Longitude,
        % TODO VFS-2918
        <<"clientName">> => Name
    }};


get(#el_req{gri = #gri{aspect = domain_config, id = ProviderId}}, Provider) ->
    #od_provider{
        domain = Domain, subdomain_delegation = SubdomainDelegation
    } = Provider,
    Response = #{
        <<"domain">> => Domain,
        <<"subdomainDelegation">> => SubdomainDelegation
    },
    case SubdomainDelegation of
        true ->
            {ok, Subdomain, IPs} = dns_state:get_delegation_config(ProviderId),
            {ok, Response#{
                <<"subdomain">> => Subdomain,
                <<"ipList">> => IPs
            }};
        false ->
            {ok, Response}
    end;

get(#el_req{gri = #gri{aspect = eff_users}}, Provider) ->
    {ok, maps:keys(Provider#od_provider.eff_users)};
get(#el_req{gri = #gri{aspect = eff_groups}}, Provider) ->
    {ok, maps:keys(Provider#od_provider.eff_groups)};

get(#el_req{gri = #gri{aspect = spaces}}, Provider) ->
    {ok, maps:keys(Provider#od_provider.spaces)};

get(#el_req{gri = #gri{aspect = {check_my_ip, ClientIP}}}, _) ->
    {ok, ClientIP}.


%%--------------------------------------------------------------------
%% @doc
%% Updates a resource (aspect of entity) based on entity logic request.
%% @end
%%--------------------------------------------------------------------
-spec update(entity_logic:req()) -> entity_logic:update_result().
update(#el_req{gri = #gri{id = ProviderId, aspect = instance}, data = Data}) ->
    {ok, _} = od_provider:update(ProviderId, fun(Provider) ->
        #od_provider{
            name = Name, latitude = Latitude, longitude = Longitude
        } = Provider,
        {ok, Provider#od_provider{
            % TODO VFS-2918
            name = maps:get(<<"name">>, Data, maps:get(<<"clientName">>, Data, Name)),
            latitude = maps:get(<<"latitude">>, Data, Latitude),
            longitude = maps:get(<<"longitude">>, Data, Longitude)
        }}
    end),
    ok;

update(#el_req{gri = #gri{id = ProviderId, aspect = domain_config}, data = Data}) ->
    Result = od_provider:update(ProviderId, fun(Provider) ->
        case maps:get(<<"subdomainDelegation">>, Data) of
            false ->
                Domain = maps:get(<<"domain">>, Data),
                dns_state:remove_delegation_config(ProviderId),
                {ok, Provider#od_provider{
                    subdomain_delegation = false,
                    domain = Domain,
                    subdomain = undefined
                }};
            true ->
                Subdomain = maps:get(<<"subdomain">>, Data),
                IPs = maps:get(<<"ipList">>, Data),
                case dns_state:set_delegation_config(ProviderId, Subdomain, IPs) of
                    ok ->
                        FQDN = dns_config:build_fqdn_from_subdomain(Subdomain),
                        {ok, Provider#od_provider{
                            subdomain_delegation = true,
                            domain = FQDN,
                            subdomain = Subdomain
                        }};
                    {error, subdomain_exists} ->
                        ?ERROR_BAD_VALUE_IDENTIFIER_OCCUPIED(<<"subdomain">>)
                end
        end
    end),
    case Result of
        {ok, _} ->
            ok;
        ?ERROR_BAD_VALUE_IDENTIFIER_OCCUPIED(<<"subdomain">>) = Error ->
            Error
    end;

update(Req = #el_req{gri = #gri{id = ProviderId, aspect = {space, SpaceId}}}) ->
    NewSupportSize = maps:get(<<"size">>, Req#el_req.data),
    entity_graph:update_relation(
        od_space, SpaceId, od_provider, ProviderId, NewSupportSize
    ).


%%--------------------------------------------------------------------
%% @doc
%% Deletes a resource (aspect of entity) based on entity logic request.
%% @end
%%--------------------------------------------------------------------
-spec delete(entity_logic:req()) -> entity_logic:delete_result().
delete(#el_req{gri = #gri{id = ProviderId, aspect = instance}}) ->
    ok = dns_state:remove_delegation_config(ProviderId),
    entity_graph:delete_with_relations(od_provider, ProviderId),
    % Force disconnect the provider (if connected)
    case provider_connection:get_connection_ref(ProviderId) of
        {ok, ConnRef} -> gs_server:terminate_connection(ConnRef);
        _ -> ok
    end;

delete(#el_req{gri = #gri{id = ProviderId, aspect = {space, SpaceId}}}) ->
    entity_graph:remove_relation(
        od_space, SpaceId, od_provider, ProviderId
    ).


%%--------------------------------------------------------------------
%% @doc
%% Determines if given resource (aspect of entity) exists, based on entity
%% logic request and prefetched entity.
%% @end
%%--------------------------------------------------------------------
-spec exists(entity_logic:req(), entity_logic:entity()) -> boolean().
exists(Req = #el_req{gri = #gri{aspect = instance, scope = protected}}, Provider) ->
    case Req#el_req.auth_hint of
        ?THROUGH_USER(UserId) ->
            provider_logic:has_eff_user(Provider, UserId);
        ?THROUGH_GROUP(GroupId) ->
            provider_logic:has_eff_group(Provider, GroupId);
        ?THROUGH_SPACE(SpaceId) ->
            provider_logic:supports_space(Provider, SpaceId);
        undefined ->
            true
    end;

exists(#el_req{gri = #gri{aspect = {space, SpaceId}}}, Provider) ->
    maps:is_key(SpaceId, Provider#od_provider.spaces);

% All other aspects exist if provider record exists.
exists(#el_req{gri = #gri{id = Id}}, #od_provider{}) ->
    Id =/= undefined.


%%--------------------------------------------------------------------
%% @doc
%% Determines if requesting client is authorized to perform given operation,
%% based on entity logic request and prefetched entity.
%% @end
%%--------------------------------------------------------------------
-spec authorize(entity_logic:req(), entity_logic:entity()) -> boolean().
authorize(#el_req{operation = create, gri = #gri{aspect = check_my_ports}}, _) ->
    true;

authorize(#el_req{operation = create, gri = #gri{aspect = map_idp_group}}, _) ->
    true;

authorize(#el_req{operation = create, gri = #gri{aspect = instance}}, _) ->
    true;

authorize(#el_req{operation = create, gri = #gri{aspect = instance_dev}}, _) ->
    true;

authorize(Req = #el_req{operation = create, gri = #gri{aspect = support}}, _) ->
    auth_by_self(Req);

authorize(#el_req{operation = get, gri = #gri{aspect = {check_my_ip, _}}}, _) ->
    true;

authorize(Req = #el_req{operation = get, gri = #gri{aspect = list}}, _) ->
    user_logic_plugin:auth_by_oz_privilege(Req, ?OZ_PROVIDERS_LIST);

authorize(Req = #el_req{operation = get, gri = #gri{aspect = instance, scope = private}}, _) ->
    auth_by_self(Req);

authorize(Req = #el_req{operation = get, gri = #gri{aspect = instance, scope = protected}}, Provider) ->
    case {Req#el_req.client, Req#el_req.auth_hint} of
        {?USER(UserId), ?THROUGH_USER(UserId)} ->
            % User's membership in this provider is checked in 'exists'
            true;

        {?USER(_UserId), ?THROUGH_USER(_OtherUserId)} ->
            false;

        {?USER(UserId), ?THROUGH_GROUP(GroupId)} ->
            % Groups's membership in this provider is checked in 'exists'
            group_logic:has_eff_user(GroupId, UserId);

        {?PROVIDER(_ProvId), ?THROUGH_SPACE(_SpaceId)} ->
            % Space's support by this provider is checked in 'exists'
            true;

        {?USER(UserId), ?THROUGH_SPACE(SpaceId)} ->
            % Space's support by this provider is checked in 'exists'
            user_logic:has_eff_space(UserId, SpaceId) orelse
                user_logic_plugin:auth_by_oz_privilege(UserId, ?OZ_SPACES_LIST_PROVIDERS);

        {?PROVIDER(_), _} ->
            % Providers are allowed to view each other's protected data
            true;

        {?USER(UserId), _} ->
            auth_by_membership(UserId, Provider) orelse
                user_logic_plugin:auth_by_oz_privilege(UserId, ?OZ_PROVIDERS_LIST);

        _ ->
            % Access to private data also allows access to protected data
            authorize(Req#el_req{gri = #gri{scope = private}}, Provider)
    end;

authorize(Req = #el_req{operation = get, gri = #gri{aspect = eff_users}}, _) ->
    auth_by_self(Req) orelse
        user_logic_plugin:auth_by_oz_privilege(Req, ?OZ_PROVIDERS_LIST_USERS);

authorize(Req = #el_req{operation = get, gri = #gri{aspect = eff_groups}}, _) ->
    auth_by_self(Req) orelse
        user_logic_plugin:auth_by_oz_privilege(Req, ?OZ_PROVIDERS_LIST_GROUPS);

authorize(Req = #el_req{operation = get, gri = #gri{aspect = spaces}}, _) ->
    auth_by_self(Req) orelse
        user_logic_plugin:auth_by_oz_privilege(Req, ?OZ_PROVIDERS_LIST_SPACES);

authorize(Req = #el_req{operation = get, gri = #gri{aspect = domain_config}}, _) ->
    auth_by_self(Req);

authorize(Req = #el_req{operation = update, gri = #gri{aspect = instance}}, _) ->
    auth_by_self(Req);

authorize(Req = #el_req{operation = update, gri = #gri{aspect = domain_config}}, _) ->
    auth_by_self(Req);

authorize(Req = #el_req{operation = update, gri = #gri{aspect = {space, _}}}, _) ->
    auth_by_self(Req);

authorize(Req = #el_req{operation = delete, gri = #gri{aspect = instance}}, _) ->
    auth_by_self(Req) orelse
        user_logic_plugin:auth_by_oz_privilege(Req, ?OZ_PROVIDERS_DELETE);

authorize(Req = #el_req{operation = delete, gri = #gri{aspect = {space, _}}}, _) ->
    auth_by_self(Req);

authorize(_, _) ->
    false.


%%--------------------------------------------------------------------
%% @doc
%% Returns validity verificators for given request.
%% Returns a map with 'required', 'optional' and 'at_least_one' keys.
%% Under each of them, there is a map:
%%      Key => {type_verificator, value_verificator}
%% Which means how value of given Key should be validated.
%% @end
%%--------------------------------------------------------------------
-spec validate(entity_logic:req()) -> entity_logic:validity_verificator().
validate(#el_req{operation = create, gri = #gri{aspect = instance},
    data = Data}) ->
    Required = #{
        <<"csr">> => {binary, non_empty},
        <<"subdomainDelegation">> => {boolean, any}
       },
    Common = #{
      optional => #{
        <<"latitude">> => {float, {between, -90, 90}},
        <<"longitude">> => {float, {between, -180, 180}}
       },
      % TODO VFS-2918
      at_least_one => #{
        <<"name">> => {binary, non_empty},
        <<"clientName">> => {binary, non_empty}
       }
     },
    case maps:get(<<"subdomainDelegation">>, Data, undefined) of
        true ->
            Common#{
                required => Required#{
                    <<"subdomain">> => {binary, subdomain},
                    <<"ipList">> => {list_of_ipv4_addresses, any}
                }
             };
        false ->
            Common#{
                required => Required#{<<"domain">> => {binary, domain}}
            };
        _ ->
            Common#{required => Required}
    end;

validate(#el_req{operation = create, gri = #gri{aspect = instance_dev},
    data = Data}) ->
    Required = #{
        <<"csr">> => {binary, non_empty},
        <<"uuid">> => {binary, non_empty},
        <<"subdomainDelegation">> => {boolean, any}
       },
    Common = #{
      optional => #{
        <<"latitude">> => {float, {between, -90, 90}},
        <<"longitude">> => {float, {between, -180, 180}}
       },
      % TODO VFS-2918
      at_least_one => #{
        <<"name">> => {binary, non_empty},
        <<"clientName">> => {binary, non_empty}
       }
     },
    case maps:get(<<"subdomainDelegation">>, Data, undefined) of
        true ->
            Common#{
                required => Required#{
                    <<"subdomain">> => {binary, subdomain},
                    <<"ipList">> => {list_of_ipv4_addresses, any}
                }
             };
        false ->
            Common#{
                required => Required#{<<"domain">> => {binary, domain}}
            };
        _ ->
            Common#{required => Required}
    end;

validate(#el_req{operation = create, gri = #gri{aspect = support}}) -> #{
    required => #{
        <<"token">> => {token, ?SPACE_SUPPORT_TOKEN},
        <<"size">> => {integer, {not_lower_than, get_min_support_size()}}
    }
};

validate(#el_req{operation = create, gri = #gri{aspect = check_my_ports}}) -> #{
};

validate(#el_req{operation = create, gri = #gri{aspect = map_idp_group}}) -> #{
    required => #{
        <<"idp">> => {binary, {exists, fun(Idp) ->
            auth_utils:has_group_mapping_enabled(binary_to_atom(Idp, utf8))
        end}},
        <<"groupId">> => {binary, non_empty}
    }
};

validate(#el_req{operation = update, gri = #gri{aspect = instance}}) -> #{
    at_least_one => #{
        <<"name">> => {binary, non_empty},
        <<"clientName">> => {binary, non_empty},
        <<"latitude">> => {float, {between, -90, 90}},
        <<"longitude">> => {float, {between, -180, 180}}
    }
};

validate(#el_req{operation = update, gri = #gri{aspect = {space, _}}}) -> #{
    required => #{
        <<"size">> => {integer, {not_lower_than, get_min_support_size()}}
    }
};

validate(#el_req{operation = update, gri = #gri{aspect = domain_config},
                 data = Data}) ->
    case maps:get(<<"subdomainDelegation">>, Data, undefined) of
        true -> #{required => #{
                <<"subdomainDelegation">> => {boolean, any},
                <<"subdomain">> => {binary, subdomain},
                <<"ipList">> => {list_of_ipv4_addresses, any}
            }};
        false -> #{required => #{
                <<"subdomainDelegation">> => {boolean, any},
                <<"domain">> => {binary, domain}
            }};
        _ ->
            #{required => #{<<"subdomainDelegation">> => {boolean, any}}}
    end.


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns if given user is supported by the provider represented by entity.
%% ProviderId is either given explicitly or derived from entity logic request.
%% @end
%%--------------------------------------------------------------------
-spec auth_by_membership(od_user:id(), od_provider:info()) ->
    boolean().
auth_by_membership(UserId, #od_provider{eff_users = EffUsers}) ->
    maps:is_key(UserId, EffUsers).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns true if request client is the same as provider id in GRI.
%% @end
%%--------------------------------------------------------------------
-spec auth_by_self(entity_logic:req()) -> boolean().
auth_by_self(#el_req{client = ?PROVIDER(ProvId), gri = #gri{id = ProvId}}) ->
    true;
auth_by_self(_) ->
    false.


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Tests connection to given urls.
%% @end
%% @equiv test_connection/2
%%--------------------------------------------------------------------
-spec test_connection(#{ServiceName :: binary() => Url :: binary()}) ->
    #{ServiceName :: binary() => Status :: ok | error}.
test_connection(Map) ->
    test_connection(maps:to_list(Map), #{}).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Tests connection to given urls.
%% @end
%%--------------------------------------------------------------------
-spec test_connection([{ServiceName :: binary(), Url :: binary()}], Result) ->
    Result when Result :: #{Url :: binary() => Status :: ok | error}.
test_connection([], Acc) ->
    Acc;
test_connection([{<<"undefined">>, <<Url/binary>>} | Rest], Acc) ->
    Opts = [{ssl_options, [{secure, false}]}],
    ConnStatus = case http_client:get(Url, #{}, <<>>, Opts) of
        {ok, 200, _, _} ->
            ok;
        _ ->
            error
    end,
    test_connection(Rest, Acc#{Url => ConnStatus});
test_connection([{<<ServiceName/binary>>, <<Url/binary>>} | Rest], Acc) ->
    Opts = [{ssl_options, [{secure, false}]}],
    ConnStatus = case http_client:get(Url, #{}, <<>>, Opts) of
        {ok, 200, _, ServiceName} ->
            ok;
        Error ->
            ?debug("Checking connection to ~p failed with error: ~n~p",
                [Url, Error]),
            error
    end,
    test_connection(Rest, Acc#{Url => ConnStatus});
test_connection([{Key, _} | _], _) ->
    throw(?ERROR_BAD_DATA(Key)).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Reads minimum space support size from app.config env variable.
%% @end
%%--------------------------------------------------------------------
-spec get_min_support_size() -> integer().
get_min_support_size() ->
    {ok, MinSupportSize} = application:get_env(
        oz_worker, minimum_space_support_size
    ),
    MinSupportSize.
