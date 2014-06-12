%% ===================================================================
%% @author Rafal Slota
%% @copyright (C): 2013 ACK CYFRONET AGH
%% This software is released under the MIT license
%% cited in 'LICENSE.txt'.
%% @end
%% ===================================================================
%% @doc This module implements {@link worker_plugin_behaviour} callbacks and contains utility API methods. <br/>
%% DAO API functions are implemented in DAO sub-modules like: {@link dao_cluster}, {@link dao_vfs}. <br/>
%% All DAO API functions Should not be used directly, use {@link dao:handle/2} instead.
%% Module :: atom() is module suffix (prefix is 'dao_'), MethodName :: atom() is the method name
%% and ListOfArgs :: [term()] is list of argument for the method. <br/>
%% If you want to call utility methods from this module - use Module = utils
%% See {@link dao:handle/2} for more details.
%% @end
%% ===================================================================
-module(dao).
-behaviour(gen_server).

-include_lib("dao/dao.hrl").
-include_lib("dao/couch_db.hrl").
-include_lib("dao/dao_types.hrl").
-include_lib("registered_names.hrl").

-import(dao_helper, [name/1]).

-ifdef(TEST).
-compile([export_all]).
-endif.

%% gen_server callbacks
-export([init/1,
	handle_call/3,
	handle_cast/2,
	handle_info/2,
	terminate/2,
	code_change/3]).

-record(state, {}).

%% API
-export([start_link/0]).
-export([save_record/1, exist_record/1, get_record/1, remove_record/1, list_records/2, load_view_def/2, set_db/1]).
-export([doc_to_term/1]).

%%%===================================================================
%%% Start gen_server api
%%%===================================================================

%% start_link/0
%% ===================================================================
%% @doc Starts the server
-spec(start_link() ->
	{ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
%% ===================================================================
start_link() ->
	gen_server:start_link({local, ?Dao}, ?MODULE, [], []).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% init/1
%% ===================================================================
%% @doc Initializes the server
-spec(init(Args :: term()) ->
	{ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
	{stop, Reason :: term()} | ignore).
%% ===================================================================
init({Args, {init_status, undefined}}) ->
	ets:new(db_host_store, [named_table, public, bag, {read_concurrency, true}]),
	init({Args, {init_status, table_initialized}});
init({_Args, {init_status, table_initialized}}) -> %% Final stage of initialization. ETS table was initialized
	case application:get_env(?APP_Name, db_nodes) of
		{ok, Nodes} when is_list(Nodes) ->
			[dao_hosts:insert(Node) || Node <- Nodes, is_atom(Node)],
			catch setup_views(?DATABASE_DESIGN_STRUCTURE);
		_ ->
			lager:warning("There are no DB hosts given in application env variable.")
	end,
	{ok,#state{}};
init({Args, {init_status, _TableInfo}}) ->
	init({Args, {init_status, table_initialized}});
init(Args) ->
	init({Args, {init_status, ets:info(db_host_store)}}).

%% handle_call/3
%% ===================================================================
%% @doc Handling call messages
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
	State :: #state{}) ->
	{reply, Reply :: term(), NewState :: #state{}} |
	{reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
	{noreply, NewState :: #state{}} |
	{noreply, NewState :: #state{}, timeout() | hibernate} |
	{stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
	{stop, Reason :: term(), NewState :: #state{}}).
%% ===================================================================
handle_call({ProtocolVersion,Target, Method, Args},_From,State) when is_atom(Target), is_atom(Method), is_list(Args) ->
	put(protocol_version, ProtocolVersion), %% Some sub-modules may need it to communicate with DAO' gen_server
	Module =
		case atom_to_list(Target) of
			"utils" -> dao;
			[$d, $a, $o, $_ | T] -> list_to_atom("dao_" ++ T);
			T -> list_to_atom("dao_" ++ T)
		end,
	try apply(Module, Method, Args) of
		{error, Err} ->
			lager:error("Handling ~p:~p with args ~p returned error: ~p", [Module, Method, Args, Err]),
			{reply, {error, Err}, State};
		{ok, Response} -> {reply, {ok, Response}, State};
		ok -> {reply, ok, State};
		Other ->
			lager:error("Handling ~p:~p with args ~p returned unknown response: ~p", [Module, Method, Args, Other]),
			{reply, {error, Other}, State}
	catch
		error:{badmatch, {error, Err}} -> {reply, {error, Err}, State};
		Type:Error ->
            lager:error("Handling ~p:~p with args ~p interrupted by exception: ~p:~p ~n ~p", [Module, Method, Args, Type, Error, erlang:get_stacktrace()]),
			{reply, {error, Error}, State}
	end;
handle_call({ProtocolVersion, Method, Args},_From,State) when is_atom(Method), is_list(Args) ->
	{reply,gen_server:call(?Dao,{ProtocolVersion, cluster, Method, Args}),State};
handle_call(_Request,_From,State) ->
	lager:error("Unknown call request ~p ", [_Request]),
	{reply,{error, wrong_args},State}.

%% handle_cast/2
%% ===================================================================
%% @doc Handling cast messages
%% ===================================================================
-spec(handle_cast(Request :: term(), State :: #state{}) ->
	{noreply, NewState :: #state{}} |
	{noreply, NewState :: #state{}, timeout() | hibernate} |
	{stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State) ->
	lager:error("Unknown cast request ~p ", [_Request]),
	{noreply, State}.

%% handle_info/2
%% ===================================================================
%% @doc Handling all non call/cast messages
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
	{noreply, NewState :: #state{}} |
	{noreply, NewState :: #state{}, timeout() | hibernate} |
	{stop, Reason :: term(), NewState :: #state{}}).
%% ===================================================================
handle_info(_Info, State) ->
	lager:error("Unknown info request ~p ", [_Info]),
	{noreply, State}.

%% terminate/2
%% ===================================================================
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%% @end
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
	State :: #state{}) -> term()).
%% ===================================================================
terminate(_Reason, _State) ->
	ok.

%% code_change/3
%% ===================================================================
%% @doc Convert process state when code is changed
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
	Extra :: term()) ->
	{ok, NewState :: #state{}} | {error, Reason :: term()}).
%% ===================================================================
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ===================================================================
%% API functions
%% ===================================================================


%% save_record/1
%% ====================================================================
%% @doc Saves record to DB. Argument has to be either Record :: term() which will be saved<br/>
%% with random UUID as completely new document or #veil_document record. If #veil_document record is passed <br/>
%% caller may set UUID and revision info in order to update this record in DB.<br/>
%% If you got #veil_document{} via {@link dao:get_record/1}, uuid and rev_info are in place and you shouldn't touch them<br/>
%% Should not be used directly, use {@link dao:handle/2} instead.
%% @end
-spec save_record(term() | #veil_document{uuid :: string(), rev_info :: term(), record :: term(), force_update :: boolean()}) ->
    {ok, DocId :: string()} |
    {error, conflict} |
    no_return(). % erlang:error(any()) | throw(any())
%% ====================================================================
save_record(#veil_document{uuid = "", record = Rec} = Doc) when is_tuple(Rec) ->
    save_record(Doc#veil_document{uuid = dao_helper:gen_uuid()});
save_record(#veil_document{uuid = Id, record = Rec} = Doc) when is_tuple(Rec), is_atom(Id) ->
    save_record(Doc#veil_document{uuid = atom_to_list(Id)});
save_record(#veil_document{uuid = Id, rev_info = RevInfo, record = Rec, force_update = IsForced}) when is_tuple(Rec), is_list(Id)->
    Valid = is_valid_record(Rec),
    if
        Valid -> ok;
        true ->
            lager:error("Cannot save record: ~p because it's not supported", [Rec]),
            throw(unsupported_record)
    end,
    Revs =
        if
            IsForced -> %% If Mode == update, we need to open existing doc in order to get revs
                case dao_helper:open_doc(get_db(), Id) of
                    {ok, #doc{revs = RevDef}} -> RevDef;
                    _ -> #doc{revs = RevDef} = #doc{}, RevDef
                end;
            RevInfo =/= 0 ->
                RevInfo;
            true ->
                #doc{revs = RevDef} = #doc{},
                RevDef
        end,
    case dao_helper:insert_doc(get_db(), #doc{id = dao_helper:name(Id), revs = Revs, body = term_to_doc(Rec)}) of
        {ok, _} ->
          {ok, Id};
        {error, Err} ->
          {error, Err}
    end;
save_record(Rec) when is_tuple(Rec) ->
    save_record(#veil_document{record = Rec}).


%% exist_record/1
%% ====================================================================
%% @doc Checks whether record with UUID = Id exists in DB.
%% Should not be used directly, use {@link dao:handle/2} instead.
%% @end
-spec exist_record(Id :: atom() | string()) -> {ok, true | false} | {error, any()}.
%% ====================================================================
exist_record(Id) when is_atom(Id) ->
    exist_record(atom_to_list(Id));
exist_record(Id) when is_list(Id) ->
    case dao_helper:open_doc(get_db(), Id) of
        {ok, _} ->
          {ok, true};
        {error, {not_found, _}} ->
          {ok, false};
        Other ->
          Other
    end.


%% get_record/1
%% ====================================================================
%% @doc Retrieves record with UUID = Id from DB. Returns whole #veil_document record containing UUID, Revision Info and
%% demanded record inside. #veil_document{}.uuid and #veil_document{}.rev_info should not be ever changed. <br/>
%% You can strip wrappers if you do not need them using API functions of dao_lib module.
%% See #veil_document{} structure for more info.<br/>
%% Should not be used directly, use {@link dao:handle/2} instead.
%% @end
-spec get_record(Id :: atom() | string()) ->
    {ok,#veil_document{record :: tuple()}} |
    {error, Error :: term()} |
    no_return(). % erlang:error(any()) | throw(any())
%% ====================================================================
get_record(Id) when is_atom(Id) ->
    get_record(atom_to_list(Id));
get_record(Id) when is_list(Id) ->
    case dao_helper:open_doc(get_db(), Id) of
        {ok, #doc{body = Body, revs = RevInfo}} ->
            try {doc_to_term(Body), RevInfo} of
                {Term, RInfo} ->
                  {ok, #veil_document{uuid = Id, rev_info = RInfo, record = Term}}
            catch
                _:Err ->
                  {error, {invalid_document, Err}}
            end;
        {error, Error} ->
          Error
    end.


%% remove_record/1
%% ====================================================================
%% @doc Removes record with given UUID from DB
%% Should not be used directly, use {@link dao:handle/2} instead.
%% @end
-spec remove_record(Id :: atom() | uuid()) ->
    ok |
    {error, Error :: term()}.
%% ====================================================================
remove_record(Id) when is_atom(Id) ->
    remove_record(atom_to_list(Id));
remove_record(Id) when is_list(Id) ->
    dao_helper:delete_doc(get_db(), Id).


%% list_records/2
%% ====================================================================
%% @doc Executes view query and parses returned result into #view_result{} record. <br/>
%% Strings from #view_query_args{} are not transformed by {@link dao_helper:name/1},
%% the caller has to do it by himself.
%% @end
-spec list_records(ViewInfo :: #view_info{}, QueryArgs :: #view_query_args{}) ->
    {ok, QueryResult :: #view_result{}} | {error, term()}.
%% ====================================================================
list_records(#view_info{name = ViewName, design = DesignName, db_name = DbName}, QueryArgs) ->
    FormatKey =  %% Recursive lambda:
    fun(F, K) when is_list(K) -> [F(F, X) || X <- K];
      (_F, K) when is_binary(K) -> binary_to_list(K);
      (_F, K) -> K
    end,
    FormatDoc =
    fun([{doc, {[ {_id, Id} | [ {_rev, RevInfo} | D ] ]}}]) ->
      #veil_document{record = doc_to_term({D}), uuid = binary_to_list(Id), rev_info = dao_helper:revision(RevInfo)};
      (_) -> none
    end,

        case dao_helper:query_view(DbName, DesignName, ViewName, QueryArgs) of
            {ok, [{total_and_offset, Total, Offset} | Rows]} ->
              FormattedRows =
                [#view_row{id = binary_to_list(Id), key = FormatKey(FormatKey, Key), value = Value, doc = FormatDoc(Doc)}
                  || {row, {[ {id, Id} | [ {key, Key} | [ {value, Value} | Doc ] ] ]}} <- Rows],
              {ok, #view_result{total = Total, offset = Offset, rows = FormattedRows}};

            {ok, Rows2} when is_list(Rows2)->
              FormattedRows2 =
                [#view_row{id = non, key = FormatKey(FormatKey, Key), value = Value, doc = non}
                  || {row, {[ {key, Key} | [ {value, Value} ] ]}} <- Rows2],
              {ok, #view_result{total = length(Rows2), offset = 0, rows = FormattedRows2}};
          {error, _} = E -> throw(E);
            Other ->
                lager:error("dao_helper:query_view has returned unknown query result: ~p", [Other]),
                throw({unknown_query_result, Other})
        end.


%% ===================================================================
%% Internal functions
%% ===================================================================

%% set_db/1
%% ====================================================================
%% @doc Sets current working database name
%% @end
-spec set_db(DbName :: string()) -> ok.
%% ====================================================================
set_db(DbName) ->
    put(current_db, DbName).

%% get_db/0
%% ====================================================================
%% @doc Gets current working database name
%% @end
-spec get_db() -> DbName :: string().
%% ====================================================================
get_db() ->
    case get(current_db) of
        DbName when is_list(DbName) ->
            DbName;
        _ ->
            ?DEFAULT_DB
    end.

%% setup_views/1
%% ====================================================================
%% @doc Creates or updates design documents
%% @end
-spec setup_views(DesignStruct :: list()) -> ok.
%% ====================================================================
setup_views(DesignStruct) ->
    DesignFun = fun(#design_info{name = Name, views = ViewList}, DbName) ->  %% Foreach design document
            LastCTX = %% Calculate MD5 sum of current views (read from files)
                lists:foldl(fun(#view_info{name = ViewName}, CTX) ->
                            crypto:hash_update(CTX, load_view_def(ViewName, map) ++ load_view_def(ViewName, reduce))
                        end, crypto:hash_init(md5), ViewList),

            LocalVersion = dao_helper:name(integer_to_list(binary:decode_unsigned(crypto:hash_final(LastCTX)), 16)),
            NewViewList =
                case dao_helper:open_design_doc(DbName, Name) of
                    {ok, #doc{body = Body}} -> %% Design document exists, so lets calculate MD5 sum of its views
                        ViewsField = dao_json:get_field(Body, "views"),
                        DbViews = [ dao_json:get_field(ViewsField, ViewName) || #view_info{name = ViewName} <- ViewList ],
                        EmptyString = fun(Str) when is_binary(Str) -> binary_to_list(Str); %% Helper function converting non-string value to empty string
                                         (_) -> "" end,
                        VStrings = [ EmptyString(dao_json:get_field(V, "map")) ++ EmptyString(dao_json:get_field(V, "reduce")) || {L}=V <- DbViews, is_list(L)],
                        LastCTX1 = lists:foldl(fun(VStr, CTX) -> crypto:hash_update(CTX, VStr) end, crypto:hash_init(md5), VStrings),
                        DbVersion = dao_helper:name(integer_to_list(binary:decode_unsigned(crypto:hash_final(LastCTX1)), 16)),
                        case DbVersion of %% Compare DbVersion with LocalVersion
                            LocalVersion ->
                                lager:info("DB version of design ~p is ~p and matches local version. Design is up to date", [Name, LocalVersion]),
                                [];
                            _Other ->
                                lager:info("DB version of design ~p is ~p and does not match ~p. Rebuilding design document", [Name, _Other, LocalVersion]),
                                ViewList
                        end;
                    _ ->
                        lager:info("Design document ~p in DB ~p not exists. Creating...", [Name, DbName]),
                        ViewList
                end,

            lists:map(fun(#view_info{name = ViewName}) -> %% Foreach view
                case dao_helper:create_view(DbName, Name, ViewName, load_view_def(ViewName, map), load_view_def(ViewName, reduce), LocalVersion) of
                    ok ->
                        lager:info("View ~p in design ~p, DB ~p has been created.", [ViewName, Name, DbName]);
                    _Err ->
                        lager:error("View ~p in design ~p, DB ~p creation failed. Error: ~p", [ViewName, Name, DbName, _Err])
                end
            end, NewViewList),
            DbName
        end,

    DbFun = fun(#db_info{name = Name, designs = Designs}) -> %% Foreach database
            dao_helper:create_db(Name, []),
            lists:foldl(DesignFun, Name, Designs)
        end,

    lists:map(DbFun, DesignStruct),
    ok.

%% load_view_def/2
%% ====================================================================
%% @doc Loads view definition from file.
%% @end
-spec load_view_def(Name :: string(), Type :: map | reduce) -> string().
%% ====================================================================
load_view_def(Name, Type) ->
    case file:read_file(?VIEW_DEF_LOCATION ++ Name ++ (case Type of map -> ?MAP_DEF_SUFFIX; reduce -> ?REDUCE_DEF_SUFFIX end)) of
        {ok, Data} -> binary_to_list(Data);
        _ -> ""
    end.

%% is_valid_record/1
%% ====================================================================
%% @doc Checks if given record/record name is supported and existing record
%% @end
-spec is_valid_record(Record :: atom() | string() | tuple()) -> boolean().
%% ====================================================================
is_valid_record(Record) when is_list(Record) ->
    is_valid_record(list_to_atom(Record));
is_valid_record(Record) when is_atom(Record) ->
    case ?dao_record_info(Record) of
        {_Size, _Fields, _} -> true;    %% When checking only name of record, we omit size check
        _ -> false
    end;
is_valid_record(Record) when not is_tuple(Record); not is_atom(element(1, Record)) ->
    false;
is_valid_record(Record) ->
    case ?dao_record_info(element(1, Record)) of
        {Size, Fields, _} when is_list(Fields), tuple_size(Record) =:= Size ->
            true;
        _ -> false
    end.


%% term_to_doc/1
%% ====================================================================
%% @doc Converts given erlang term() into valid BigCouch document body. Given term should be a record. <br/>
%% All erlang data types are allowed, although using binary() is not recommended (because JSON will treat it like a string and will fail to read it)
%% @end
-spec term_to_doc(Field :: term()) -> term().
%% ====================================================================
term_to_doc(Field) when is_number(Field) ->
    Field;
term_to_doc(Field) when is_boolean(Field); Field =:= null ->
    Field;
term_to_doc(Field) when is_pid(Field) ->
    list_to_binary(?RECORD_FIELD_PID_PREFIX ++ pid_to_list(Field));
term_to_doc(Field) when is_binary(Field) ->
    <<<<?RECORD_FIELD_BINARY_PREFIX>>/binary, Field/binary>>;   %% Binary is saved as string, so we add a prefix
term_to_doc(Field) when is_list(Field) ->
    case io_lib:printable_unicode_list(Field) of
        true -> dao_helper:name(Field);
        false -> [term_to_doc(X) || X <- Field]
    end;
term_to_doc(Field) when is_atom(Field) ->
    term_to_doc(?RECORD_FIELD_ATOM_PREFIX ++ atom_to_list(Field));  %% Atom is saved as string, so we add a prefix
term_to_doc(Field) when is_tuple(Field) ->
    IsRec = is_valid_record(Field),

    {InitObj, LField, RecName} =  %% Prepare initial structure for record or simple tuple
        case IsRec of
            true ->
                [RecName1 | Res] = tuple_to_list(Field),
                {dao_json:mk_field(dao_json:mk_obj(), ?RECORD_META_FIELD_NAME, dao_json:mk_str(atom_to_list(RecName1))), Res, RecName1};
            false ->
                {dao_json:mk_obj(), tuple_to_list(Field), none}
        end,
    FoldFun = fun(Elem, {Poz, AccIn}) ->  %% Function used in lists:foldl/3. It parses given record/tuple field
            case IsRec of                 %% and adds to Accumulator object
                true ->
                    {_, Fields, _} = ?dao_record_info(RecName),

                    Value = term_to_doc(Elem),

                    {Poz + 1, dao_json:mk_field(AccIn, atom_to_list(lists:nth(Poz, Fields)), Value)};
                false ->
                    {Poz + 1, dao_json:mk_field(AccIn, ?RECORD_TUPLE_FIELD_NAME_PREFIX ++ integer_to_list(Poz), term_to_doc(Elem))}
            end
        end,
    {_, {Ret}} = lists:foldl(FoldFun, {1, InitObj}, LField),
    {lists:reverse(Ret)};
term_to_doc(Field) ->
    lager:error("Cannot convert term to document because field: ~p is not supported", [Field]),
    throw({unsupported_field, Field}).


%% doc_to_term/1
%% ====================================================================
%% @doc Converts given valid BigCouch document body into erlang term().
%% If document contains saved record which is a valid record (see is_valid_record/1),
%% then structure of the returned record will be updated
%% @end
-spec doc_to_term(Field :: term()) -> term().
%% ====================================================================
doc_to_term(Field) when is_number(Field); is_atom(Field) ->
    Field;
doc_to_term(Field) when is_binary(Field) -> %% Binary type means that it is atom, string or binary.
    SField = binary_to_list(Field),         %% Prefix tells us which type is it
    BinPref = string:str(SField, ?RECORD_FIELD_BINARY_PREFIX),
    AtomPref = string:str(SField, ?RECORD_FIELD_ATOM_PREFIX),
    PidPref = string:str(SField, ?RECORD_FIELD_PID_PREFIX),
    if
	    BinPref == 1 -> list_to_binary(string:sub_string(SField, length(?RECORD_FIELD_BINARY_PREFIX) + 1));
	    AtomPref == 1 -> list_to_atom(string:sub_string(SField, length(?RECORD_FIELD_ATOM_PREFIX) + 1));
	    PidPref == 1 ->
		PidString = string:sub_string(SField, length(?RECORD_FIELD_PID_PREFIX) + 1),
		try list_to_pid(PidString) of %(temporary fix) todo change our pid storing mechanisms, so such conversion won't fail
			Pid -> Pid
		catch
			_:_Error ->
				lager:warning("Cannot convert document to term: cannot read PID ~p. Node missing?", [PidString]),
				undefined
		end;
	    true -> unicode:characters_to_list(list_to_binary(SField))
    end;
doc_to_term(Field) when is_list(Field) ->
    [doc_to_term(X) || X <- Field];
doc_to_term({Fields}) when is_list(Fields) -> %% Object stores tuple which can be an erlang record
    Fields1 = [{binary_to_list(X), Y} || {X, Y} <- Fields],
    {IsRec, FieldsInit, RecName} =
        case lists:keyfind(?RECORD_META_FIELD_NAME, 1, Fields1) of  %% Search for record meta field
            {_, RecName1} -> %% Meta field found. Check if it is valid record name. Either way - prepare initial working structures
                {case is_valid_record(binary_to_list(RecName1)) of true -> true; _ -> partial end,
                    lists:keydelete(?RECORD_META_FIELD_NAME, 1, Fields1), list_to_atom(binary_to_list(RecName1))};
            _ ->
                DataTmp = [{list_to_integer(lists:filter(fun(E) -> (E >= $0) andalso (E =< $9) end, Num)), Data} || {Num, Data} <- Fields1],
                {false, lists:sort(fun({A, _}, {B, _}) -> A < B end, DataTmp), none}
        end,
    case IsRec of
        false -> %% Object is an tuple. Simply create tuple from successive fields
            list_to_tuple([doc_to_term(Data) || {_, Data} <- FieldsInit]);
        partial -> %% Object is an unsupported record. We are gonna build record based only on current structure from DB
            list_to_tuple([RecName | [doc_to_term(Data) || {_, Data} <- FieldsInit]]);
        true -> %% Object is an supported record. We are gonna build record based on current erlang record structure (new fields will get default values)
            {_, FNames, InitRec} = ?dao_record_info(RecName),
            FoldFun = fun(Elem, {Poz, AccIn}) ->
                    case lists:keyfind(atom_to_list(Elem), 1, FieldsInit) of
                        {_, Data} ->
                            {Poz + 1, setelement(Poz, AccIn, doc_to_term(Data))};
                        _ ->
                            {Poz + 1, AccIn}
                    end
                end,
            {_, Ret} = lists:foldl(FoldFun, {2, InitRec}, FNames),
            Ret
    end;
doc_to_term(_) ->
    throw(invalid_document).