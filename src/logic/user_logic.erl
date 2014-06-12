%% ===================================================================
%% @author Konrad Zemek
%% @copyright (C): 2014 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc The module implementing the business logic for registry's users.
%% This module serves as a buffer between the database and the REST API.
%% @end
%% ===================================================================
-module(user_logic).
-author("Konrad Zemek").

-include("dao/dao_types.hrl").


%% API
-export([create/1, modify/2, merge/2]).
-export([get_data/1, get_spaces/1, get_groups/1]).
-export([remove/1]).


%% create/1
%% ====================================================================
%% @doc Creates a user account.
%% Throws exception when call to dao fails.
%% @end
%% ====================================================================
-spec create(Name :: binary()) ->
    {ok, UserId :: binary()} | no_return().
%% ====================================================================
create(Name) ->
    UserId = dao_adapter:save(#user{name = Name}),
    {ok, UserId}.


%% modify/2
%% ====================================================================
%% @doc Modifies user details.
%% Throws exception when call to dao fails, or user doesn't exist.
%% @end
%% ====================================================================
-spec modify(UserId :: binary(), Name :: binary()) ->
    ok | no_return().
%% ====================================================================
modify(UserId, Name) ->
    #veil_document{record = User} = Doc = dao_adapter:user_doc(UserId),
    DocNew = Doc#veil_document{record = User#user{name = Name}},
    dao_adapter:save(DocNew),
    ok.


%% merge/2
%% ====================================================================
%% @doc Merges an account identified by token into current user's account.
%% ====================================================================
-spec merge(UserId :: binary(), Token :: binary()) ->
    ok | no_return().
%% ====================================================================
merge(_UserId, _Token) ->
    %% @todo: a proper authentication must come first, so that a certificate
    %% or whatever is redirected to new user id
    ok.


%% get_data/1
%% ====================================================================
%% @doc Returns user details.
%% Throws exception when call to dao fails, or user doesn't exist.
%% @end
%% ====================================================================
-spec get_data(UserId :: binary()) ->
    {ok, [proplists:property()]} | no_return().
%% ====================================================================
get_data(UserId) ->
    #veil_document{record = User} = dao_adapter:user_doc(UserId),
    #user{name = Name} = User,
    {ok, [
        {userId, UserId},
        {name, Name}
    ]}.


%% get_spaces/1
%% ====================================================================
%% @doc Returns user's spaces.
%% Throws exception when call to dao fails, or user doesn't exist.
%% @end
%% ====================================================================
-spec get_spaces(UserId :: binary()) ->
    {ok, [proplists:property()]} | no_return().
%% ====================================================================
get_spaces(UserId) ->
    Doc = dao_adapter:user_doc(UserId),
    #veil_document{record = #user{spaces = Spaces}} = Doc,
    {ok, [{spaces, Spaces}]}.


%% get_groups/1
%% ====================================================================
%% @doc Returns user's groups.
%% Throws exception when call to dao fails, or user doesn't exist.
%% @end
%% ====================================================================
-spec get_groups(UserId :: binary()) ->
    {ok, [proplists:property()]} | no_return().
%% ====================================================================
get_groups(UserId) ->
    Doc = dao_adapter:user_doc(UserId),
    #veil_document{record = #user{groups = Groups}} = Doc,
    {ok, [{groups, Groups}]}.


%% remove/1
%% ====================================================================
%% @doc Remove user's account.
%% Throws exception when call to dao fails, or user is already deleted.
%% @end
%% ====================================================================
-spec remove(UserId :: binary()) -> true | no_return().
%% ====================================================================
remove(UserId) ->
    Doc = dao_adapter:user_doc(UserId),
    #veil_document{record = #user{groups = Groups, spaces = Spaces}} = Doc,

    lists:foreach(fun(GroupId) ->
        GroupDoc = dao_adapter:group_doc(GroupId),
        #veil_document{record = #user_group{users = Users} = Group} = GroupDoc,
        GroupNew = Group#user_group{users = lists:keydelete(UserId, 1, Users)},
        dao_adapter:save(GroupDoc#veil_document{record = GroupNew}),
        group_logic:cleanup(GroupId)
    end, Groups),

    lists:foreach(fun(SpaceId) ->
        SpaceDoc = dao_adapter:space_doc(SpaceId),
        #veil_document{record = #space{users = Users} = Space} = SpaceDoc,
        SpaceNew = Space#space{users = lists:keydelete(UserId, 1, Users)},
        dao_adapter:save(SpaceDoc#veil_document{record = SpaceNew}),
        space_logic:cleanup(SpaceId)
    end, Spaces),

    dao_adapter:user_remove(UserId).