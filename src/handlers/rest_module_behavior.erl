%% ===================================================================
%% @author Konrad Zemek
%% @copyright (C): 2014 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc The behavior implemented by different logic handlers behind the REST API.
%% ===================================================================
-module(rest_module_behavior).
-author("Konrad Zemek").

-include("handlers/rest_handler.hrl").


%% routes/0
%% ====================================================================
%% @doc Returns a Cowboy-understandable PathList of routes supported by a module
%% implementing this behavior. The State shall contain an opts record where
%% the #opts.module shall be set to the atom representing the implementing
%% module. If the route contains a resource identifier, it shall be bound to :id
%% so it will be passed as an argument of other callbacks.
%% @end
-callback routes() ->
    [{PathMatch :: binary(), rest_handler, State :: rstate()}].


%% is_authorized/4
%% ====================================================================
%% @doc Returns a boolean determining if the client is authorized to carry the
%% request on the resource.
%% @end
%% ====================================================================
-callback is_authorized(Resource :: atom(), Method :: method(),
                        ResId :: binary(), Client :: client()) -> boolean().


%% resource_exists/3
%% ====================================================================
%% @doc Returns whether a resource exists.
%% ====================================================================
-callback resource_exists(Resource :: atom(), ResId :: binary(),
                          Bindings :: [{atom(), any()}]) -> boolean().


%% accept_resource/6
%% ====================================================================
%% @doc Processes data submitted by a client through POST, PUT, PATCH on a REST
%% resource. The callback shall return {true, URL} with an URL pointing to the
%% newly created resource if it was created. Otherwise, it shall return whether
%% the operation was performed successfuly.
%% @end
%% ====================================================================
-callback accept_resource(Resource :: atom(), Method :: method(),
                          ResId :: binary(), Data :: [proplists:property()],
                          Client :: client(), Bindings :: [{atom(), any()}]) ->
    {true, URL :: binary()} | boolean().


%% provide_resource/4
%% ====================================================================
%% @doc Returns data requested by a client through GET request on a REST
%% resource.
%% @end
%% ====================================================================
-callback provide_resource(Resource :: atom(), ResId :: binary(),
                           Client :: client(), Bindings :: [{atom(), any()}]) ->
    Data :: [proplists:property()].


%% delete_resource/3
%% ====================================================================
%% @doc Deletes the resource. Returns whether the deletion was successful.
%% ====================================================================
-callback delete_resource(Resource :: atom(), ResId :: binary(),
                          Bindings :: [{atom(), any()}]) -> boolean().
