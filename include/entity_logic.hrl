%%%-------------------------------------------------------------------
%%% @author Lukasz Opiola
%%% @copyright (C) 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% Common definitions concerning entity logic.
%%% @end
%%%-------------------------------------------------------------------

-ifndef(ENTITY_LOGIC_HRL).
-define(ENTITY_LOGIC_HRL, 1).

-include_lib("cluster_worker/include/graph_sync/graph_sync.hrl").

% Record expressing entity logic request client (REST and Graph Sync).
-record(client, {
    % root is allowed to do anything, it must be used with caution
    % (should not be used in any kind of external API!)
    type = nobody :: user | provider | root | nobody,
    id = <<"">> :: binary()
}).

% Record expressing entity logic request
-record(el_req, {
    client = #client{} :: entity_logic:client(),
    gri :: entity_logic:gri(),
    operation = create :: entity_logic:operation(),
    data = #{} :: entity_logic:data(),
    auth_hint = undefined :: undefined | entity_logic:auth_hint()
}).

% Convenience macros for concise code
-define(USER, #client{type = user}).
-define(USER(__Id), #client{type = user, id = __Id}).
-define(PROVIDER, #client{type = provider}).
-define(PROVIDER(__Id), #client{type = provider, id = __Id}).
-define(NOBODY, #client{type = nobody}).
-define(ROOT, #client{type = root}).

% Macros to strip results from entity_logic:create into simpler form.
-define(CREATE_RETURN_ID(__Expr),
    case __Expr of
        {error, _} = __Err ->
            __Err;
        ok ->
            throw(create_did_not_return_id);
        {ok, {data, _}} ->
            throw(create_did_not_return_id);
        {ok, {fetched, #gri{id = __Id}, _}} ->
            {ok, __Id};
        {ok, {not_fetched, #gri{id = __Id}}} ->
            {ok, __Id};
        {ok, {not_fetched, #gri{id = __Id}, _}} ->
            {ok, __Id}
    end
).

-define(CREATE_RETURN_DATA(__Expr),
    case __Expr of
        {error, _} = __Err ->
            __Err;
        ok ->
            throw(create_did_not_return_data);
        {ok, {data, __Data}} ->
            {ok, __Data};
        {ok, {fetched, _GRI, __Data}} ->
            {ok, __Data};
        {ok, {not_fetched, _GRI}} ->
            throw(create_did_not_return_data);
        {ok, {not_fetched, _GRI, _AuthHint}} ->
            throw(create_did_not_return_data)
    end
).

-define(CREATE_RETURN_OK(__Expr),
    case __Expr of
        {error, _} = __Err ->
            __Err;
        ok ->
            ok;
        {ok, _} ->
            ok
    end
).

% Regexp to validate domain (domain, subdomain or IP)
% Domain consists of some number of parts delimited by single dot characters.
% Each part must start and end with an lowercase alphanum
% and may contain a hyphen '-'.
-define(DOMAIN_VALIDATION_REGEXP,
    <<"^(([a-z0-9]|[a-z0-9][a-z0-9\\-]*[a-z0-9])\\.)*([a-z0-9]|[a-z0-9][a-z0-9\\-]*[a-z0-9])$">>).

-define(MAX_DOMAIN_LENGTH, 253).

-define(SUBDOMAIN_VALIDATION_REGEXP,
    <<"^([a-z0-9]|[a-z0-9][a-z0-9\\-]*[a-z0-9])$">>).


% Regexp to validate logins. Login must be 3-15 characters long and composed of letters and digits,
% dashes and underscores are allowed (but not at the beginning or the end).
-define(LOGIN_VALIDATION_REGEXP, <<"^[a-z0-9A-Z][a-z0-9A-Z_-]{1,13}[a-z0-9A-Z]$">>).

-endif.
