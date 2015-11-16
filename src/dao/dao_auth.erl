%%%-------------------------------------------------------------------
%%% @author Konrad Zemek
%%% @copyright (C): 2014 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc This module provides high level DB API for handling authorizations documents.
%%% @end
%%%-------------------------------------------------------------------
-module(dao_auth).
-author("Konrad Zemek").

-include("dao/dao_auth.hrl").
-include("dao/dao_types.hrl").
-include("dao/dao_external.hrl").
-include_lib("dao/include/dao_helper.hrl").
-include_lib("ctool/include/logging.hrl").

%% API
-export([save_auth/1, remove_auth/1, exist_auth/1, get_auth/1,
    get_auth_by_user_id/1]).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Saves auth to DB. Argument should be either #auth{}
%% record (if you want to save it as new document) or #db_document{} that
%% wraps #auth{} if you want to update descriptor in DB.
%% See {@link dao_records:save_record/1} and {@link dao_records:get_record/1}
%% for more details about #db_document{} wrapper.
%% Should not be used directly, use {@link dao_worker:handle_call/3} instead
%% (See {@link dao_worker:handle_call/3} for more details).
%% @end
%%--------------------------------------------------------------------
-spec save_auth(Auth :: auth_info()
| auth_doc()) ->
    {ok, auth_id()} | {error, any()} | no_return().
save_auth(#auth{} = Auth) ->
    save_auth(#db_document{record = Auth});
save_auth(#db_document{uuid = UUID} = AuthDoc) when not is_list(UUID) ->
    save_auth(AuthDoc#db_document{uuid = utils:ensure_list(UUID)});
save_auth(#db_document{record = #auth{}} = AuthDoc) ->
    dao_external:set_db(?AUTH_DB_NAME),
    dao_records:save_record(AuthDoc).

%%--------------------------------------------------------------------
%% @doc Removes auth from DB.
%% Should not be used directly, use {@link dao_worker:handle_call/3} instead
%% (See {@link dao_worker:handle_call/3} for more details).
%% @end
%%--------------------------------------------------------------------
-spec remove_auth(AuthId :: auth_id()) ->
    ok | {error, any()} | no_return().
remove_auth(AuthId) ->
    dao_external:set_db(?AUTH_DB_NAME),
    dao_records:remove_record(utils:ensure_list(AuthId)).

%%--------------------------------------------------------------------
%% @doc Checks whether auth exists in DB.
%% Should not be used directly, use {@link dao_worker:handle_call/3} instead
%% (See {@link dao_worker:handle_call/3} for more details).
%% @end
%%--------------------------------------------------------------------
-spec exist_auth(AuthId :: auth_id()) ->
    {ok, boolean()} | {error, any()}.
exist_auth(AuthId) ->
    dao_external:set_db(?AUTH_DB_NAME),
    dao_records:exist_record(utils:ensure_list(AuthId)).

%%--------------------------------------------------------------------
%% @doc Gets auth from DB.
%% See {@link dao_records:save_record/1} and {@link dao_records:get_record/1}
%% for more details about #db_document{} wrapper.
%% Should not be used directly, use {@link dao_worker:handle_call/3} instead
%% (See {@link dao_worker:handle_call/3} for more details).
%% @end
%%--------------------------------------------------------------------
-spec get_auth(AuthId :: auth_id()) ->
    {ok, auth_doc()} | {error, any()} | no_return().
get_auth(AuthId) ->
    dao_external:set_db(?AUTH_DB_NAME),
    {ok, #db_document{record = #auth{}}} =
        dao_records:get_record(utils:ensure_list(AuthId)).

%%--------------------------------------------------------------------
%% @doc Gets auth from DB for a given user id.
%% Should not be used directly, use {@link dao_worker:handle_call/3} instead
%% (See {@link dao_worker:handle_call/3} for more details).
%% @end
%%--------------------------------------------------------------------
-spec get_auth_by_user_id(UserId :: binary()) -> {ok, [auth_doc()]} | no_return().
get_auth_by_user_id(UserId) ->
    {View, QueryArgs} =
        {?AUTH_BY_USER_ID_VIEW, #view_query_args{keys =
        [<<?RECORD_FIELD_BINARY_PREFIX, UserId/binary>>], include_docs = true}},

    {ok, #view_result{rows = Rows}} = dao_records:list_records(View, QueryArgs),
    {ok, [#db_document{record = #auth{}} = FDoc || #view_row{doc = FDoc} <- Rows]}.
