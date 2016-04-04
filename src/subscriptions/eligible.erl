%%%-------------------------------------------------------------------
%%% @author Michal Zmuda
%%% @copyright (C): 2016 ACK CYFRONET AGH
%%% This software is released under the MIT license
%%% cited in 'LICENSE.txt'.
%%% @end
%%%-------------------------------------------------------------------
%%% @doc
%%% This module resolves which providers are eligible for receiving updates.
%%% @end
%%%-------------------------------------------------------------------
-module(eligible).
-author("Michal Zmuda").

-include("registered_names.hrl").
-include("datastore/oz_datastore_models_def.hrl").
-include_lib("ctool/include/logging.hrl").

-export([providers/2]).

%%--------------------------------------------------------------------
%% @doc
%% Returns providers eligible for receiving given update.
%% @end
%%--------------------------------------------------------------------
-spec providers(Doc :: datastore:document(), Model :: subscriptions:model())
        -> [ProviderID :: binary()].
providers(Doc, space) ->
    #document{value = #space{providers = SpaceProviders,
        users = SpaceUserTuples, groups = GroupTuples}} = Doc,

    GroupUsersSets = lists:flatmap(fun({GroupId, _}) ->
        {ok, #document{value = #user_group{users = GroupUserTuples}}} = user_group:get(GroupId),
        {GroupUsers, _} = lists:unzip(GroupUserTuples),
        GroupUsers
    end, GroupTuples),

    {SpaceUsers, _} = lists:unzip(SpaceUserTuples),
    SpaceUsersSet = ordsets:from_list(SpaceUsers),

    SpaceProviders ++ through_users(SpaceUsersSet ++ GroupUsersSets);

providers(Doc, user_group) ->
    #document{value = #user_group{users = UsersWithPrivileges}} = Doc,
    {Users, _} = lists:unzip(UsersWithPrivileges),
    through_users(Users);

providers(Doc, onedata_user) ->
    through_users([Doc#document.key]);

providers(_Doc, _Type) ->
    [].

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Returns providers who are eligible thanks to users declared in
%% current subscription.
%% @end
%%--------------------------------------------------------------------
-spec through_users(UserIDs :: [binary()]) -> ProviderIDs :: [binary()].
through_users(UserIDs) ->
    UsersSet = ordsets:from_list(UserIDs),
    lists:filtermap(fun(SubDoc) ->
        #document{value = #provider_subscription{users = Users,
            provider = ProviderID}} = SubDoc,
        case ordsets:is_disjoint(UsersSet, ordsets:from_list(Users)) of
            false -> {true, ProviderID};
            true -> false
        end
    end, subscriptions:all()).
