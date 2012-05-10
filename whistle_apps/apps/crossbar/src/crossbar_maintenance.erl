%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, VoIP, INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(crossbar_maintenance).

-export([flush/0]).
-export([refresh/0, refresh/1]).
-export([find_account_by_number/1]).
-export([find_account_by_name/1]).
-export([find_account_by_realm/1]).
-export([enable_account/1, disable_account/1]).
-export([promote_account/1, demote_account/1]).
-export([allow_account_number_additions/1, disallow_account_number_additions/1]).
-export([create_account/4]).

-include_lib("crossbar/include/crossbar.hrl").

-type input_term() :: atom() | string() | ne_binary().

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Flush the crossbar local cache
%% @end
%%--------------------------------------------------------------------
-spec flush/0 :: () -> 'ok'.
flush() ->
    wh_cache:flush_local(?CROSSBAR_CACHE).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec refresh/0 :: () -> 'ok'.
-spec refresh/1 :: (input_term()) -> 'ok'.

refresh() ->
    lager:info("please use whapps_maintenance:refresh().", []).

refresh(Value) ->
    lager:info("please use whapps_maintenance:refresh(~p).", [Value]).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec find_account_by_number/1 :: (input_term()) -> {'ok', ne_binary()} | {'error', term()}.
find_account_by_number(Number) when not is_binary(Number) ->
    find_account_by_number(wh_util:to_binary(Number));
find_account_by_number(Number) ->
    case wh_number_manager:lookup_account_by_number(Number) of
        {ok, AccountId, _} -> 
            AccountDb = wh_util:format_account_id(AccountId, encoded),
            print_account_info(AccountDb, AccountId);
        {error, {not_in_service, AssignedTo}} ->
            AccountDb = wh_util:format_account_id(AssignedTo, encoded),
            print_account_info(AccountDb, AssignedTo);
        {error, {account_disabled, AssignedTo}} ->
            AccountDb = wh_util:format_account_id(AssignedTo, encoded),
            print_account_info(AccountDb, AssignedTo);
        {error, Reason}=E ->
            lager:info("failed to find account assigned to number '~s': ~p", [Number, Reason]),
            E
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec find_account_by_name/1 :: (input_term()) -> {'ok', ne_binary()} | 
                                                  {'multiples', [ne_binary(),...]} |
                                                  {'error', term()}.
find_account_by_name(Name) when not is_binary(Name) ->
    find_account_by_name(wh_util:to_binary(Name)); 
find_account_by_name(Name) ->
    case whapps_util:get_accounts_by_name(Name) of
        {ok, AccountDb} ->
            print_account_info(AccountDb);
        {multiples, AccountDbs} ->
            AccountIds = [begin
                              {ok, AccountId} = print_account_info(AccountDb),
                              AccountId
                          end || AccountDb <- AccountDbs
                         ],
            {multiples, AccountIds};
        {error, Reason}=E ->
            lager:info("failed to find account: ~p", [Reason]),
            E
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec find_account_by_realm/1 :: (input_term()) -> {'ok', ne_binary()} | 
                                                  {'multiples', [ne_binary(),...]} |
                                                  {'error', term()}.
find_account_by_realm(Realm) when not is_binary(Realm) ->
    find_account_by_realm(wh_util:to_binary(Realm));
find_account_by_realm(Realm) ->
    case whapps_util:get_account_by_realm(Realm) of
        {ok, AccountDb} ->
            print_account_info(AccountDb);
        {multiples, AccountDbs} ->
            AccountIds = [begin
                              {ok, AccountId} = print_account_info(AccountDb),
                              AccountId
                          end || AccountDb <- AccountDbs
                         ],
            {multiples, AccountIds};
        {error, Reason}=E ->
            lager:info("failed to find account: ~p", [Reason]),
            E
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec allow_account_number_additions/1 :: (input_term()) -> 'ok' | 'failed'.
allow_account_number_additions(AccountId) ->
    case update_account(AccountId, <<"pvt_wnm_allow_additions">>, true) of
        {ok, _} ->
            lager:info("allowing account '~s' to added numbers", [AccountId]),
            ok;
        {error, Reason} ->
            lager:info("failed to find account: ~p", [Reason]),
            failed
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec disallow_account_number_additions/1 :: (input_term()) -> 'ok' | 'failed'.
disallow_account_number_additions(AccountId) ->
    case update_account(AccountId, <<"pvt_wnm_allow_additions">>, false) of
        {ok, _} ->
            lager:info("disallowed account '~s' to added numbers", [AccountId]),
            ok;
        {error, Reason} ->
            lager:info("failed to find account: ~p", [Reason]),
            failed
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec enable_account/1 :: (input_term()) -> 'ok' | 'failed'.
enable_account(AccountId) ->
    case update_account(AccountId, <<"pvt_enabled">>, true) of
        {ok, _} ->
            lager:info("enabled account '~s'", [AccountId]),
            ok;
        {error, Reason} ->
            lager:info("failed to enable account: ~p", [Reason]),
            failed
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec disable_account/1 :: (input_term()) -> 'ok' | 'failed'.
disable_account(AccountId) ->
    case update_account(AccountId, <<"pvt_enabled">>, false) of
        {ok, _} ->
            lager:info("disabled account '~s'", [AccountId]),
            ok;
        {error, Reason} ->
            lager:info("failed to disable account: ~p", [Reason]),
            failed
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec promote_account/1 :: (input_term()) -> 'ok' | 'failed'.
promote_account(AccountId) ->
    case update_account(AccountId, <<"pvt_superduper_admin">>, true) of
        {ok, _} ->
            lager:info("promoted account '~s', this account now has permission to change system settings", [AccountId]),
            ok;
        {error, Reason} ->
            lager:info("failed to promote account: ~p", [Reason]),
            failed
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec demote_account/1 :: (input_term()) -> 'ok' | 'failed'.
demote_account(AccountId) ->
    case update_account(AccountId, <<"pvt_superduper_admin">>, false) of
        {ok, _} ->
            lager:info("promoted account '~s', this account can no longer change system settings", [AccountId]),
            ok;
        {error, Reason} ->
            lager:info("failed to demote account: ~p", [Reason]),
            failed
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec create_account/4 :: (input_term(), input_term(), input_term(), input_term()) -> 'ok' | 'failed'.
create_account(AccountName, Realm, Username, Password) when not is_binary(AccountName) ->
    create_account(wh_util:to_binary(AccountName), Realm, Username, Password);
create_account(AccountName, Realm, Username, Password) when not is_binary(Realm) ->
    create_account(AccountName, wh_util:to_binary(Realm), Username, Password);
create_account(AccountName, Realm, Username, Password) when not is_binary(Username) ->
    create_account(AccountName, Realm, wh_util:to_binary(Username), Password);
create_account(AccountName, Realm, Username, Password) when not is_binary(Password) ->
    create_account(AccountName, Realm, Username, wh_util:to_binary(Password));
create_account(AccountName, Realm, Username, Password) ->
    Account = wh_json:from_list([{<<"_id">>, couch_mgr:get_uuid()}
                                 ,{<<"name">>, AccountName}
                                 ,{<<"realm">>, Realm}
                                ]),
    User = wh_json:from_list([{<<"_id">>, couch_mgr:get_uuid()}
                              ,{<<"username">>, Username}
                              ,{<<"password">>, Password}
                              ,{<<"first_name">>, <<"Account">>}
                              ,{<<"last_name">>, <<"Admin">>}
                              ,{<<"priv_level">>, <<"admin">>}
                             ]),
    try
        {ok, C1} = validate_account(Account, #cb_context{}),
        {ok, C2} = validate_user(User, C1),
        {ok, #cb_context{db_name=Db, account_id=AccountId}} = create_account(C1),
        {ok, _} = create_user(C2#cb_context{db_name=Db, account_id=AccountId}),
        case whapps_util:get_all_accounts() of
            [Db] -> promote_account(AccountId);
            _Else -> ok
        end,
        ok
    catch
        _:_ -> 
            failed
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec validate_account/2 :: (wh_json:json_object(), #cb_context{}) -> {'ok', #cb_context{}} |
                                                                      {'error', wh_json:json_object()}.
validate_account(JObj, Context) ->
    Payload = [Context#cb_context{req_data=JObj
                                  ,req_nouns=[{?WH_ACCOUNTS_DB, []}]
                                  ,req_verb = <<"put">>
                                 }               
              ],
    case crossbar_bindings:fold(<<"v1_resource.validate.accounts">>, Payload) of
        #cb_context{resp_status=success}=Context1 -> {ok, Context1};
        #cb_context{resp_data=Errors} -> 
            lager:info("failed to validate account properties: '~s'", [list_to_binary(wh_json:encode(Errors))]),
            {error, Errors}
    end.
    

%%--------------------------------------------------------------------
%% @private
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec validate_user/2 :: (wh_json:json_object(), #cb_context{}) -> {'ok', #cb_context{}} |
                                                                   {'error', wh_json:json_object()}.    
validate_user(JObj, Context) ->
    Payload = [Context#cb_context{req_data=JObj
                                  ,req_nouns=[{?WH_ACCOUNTS_DB, []}]
                                  ,req_verb = <<"put">>
                                 }               
              ],
    case crossbar_bindings:fold(<<"v1_resource.validate.users">>, Payload) of
        #cb_context{resp_status=success}=Context1 -> {ok, Context1};
        #cb_context{resp_data=Errors} -> 
            lager:info("failed to validate user properties: '~s'", [list_to_binary(wh_json:encode(Errors))]),
            {error, Errors}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec create_account/1 :: (#cb_context{}) -> {'ok', #cb_context{}} |
                                             {'error', wh_json:json_object()}.
create_account(Context) ->
    case crossbar_bindings:fold(<<"v1_resource.execute.put.accounts">>, [Context]) of
        #cb_context{resp_status=success, db_name=AccountDb, account_id=AccountId}=Context1 ->
            lager:info("created new account '~s' in db '~s'", [AccountId, AccountDb]),
            {ok, Context1};
        #cb_context{resp_data=Errors} ->
            lager:info("failed to create account: '~s'", [list_to_binary(wh_json:encode(Errors))]),
            AccountId = wh_json:get_value(<<"_id">>, Context#cb_context.req_data),
            couch_mgr:db_delete(wh_util:format_account_id(AccountId, encoded)),
            {error, Errors}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec create_user/1 :: (#cb_context{}) -> {'ok', #cb_context{}} |
                                             {'error', wh_json:json_object()}.
create_user(Context) ->
    case crossbar_bindings:fold(<<"v1_resource.execute.put.users">>, [Context]) of
        #cb_context{resp_status=success, doc=JObj}=Context1 ->
            lager:info("created new account admin user '~s'", [wh_json:get_value(<<"_id">>, JObj)]),
            {ok, Context1};
        #cb_context{resp_data=Errors} ->
            lager:info("failed to create account admin user: '~s'", [list_to_binary(wh_json:encode(Errors))]),
            {error, Errors}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% 
%% @end
%%--------------------------------------------------------------------
-spec update_account/3 :: (input_term(), ne_binary(), term()) -> {'ok', wh_json:json_object()} |
                                                                 {'error', term()}.
update_account(AccountId, Key, Value) when not is_binary(AccountId) ->
    update_account(wh_util:to_binary(AccountId), Key, Value);
update_account(AccountId, Key, Value) ->
    AccountDb = wh_util:format_account_id(AccountId, encoded),
    Updaters = [fun({error, _}=E) -> E;
                    ({ok, J}) -> couch_mgr:ensure_saved(AccountDb, wh_json:delete_key(<<"_rev">>, J))
                 end
                 ,fun({error, _}=E) -> E;
                     ({ok, J}) -> couch_mgr:save_doc(AccountDb, wh_json:set_value(Key, Value, J))
                  end
                ],
    lists:foldr(fun(F, J) -> F(J) end, couch_mgr:open_doc(AccountDb, AccountId), Updaters).

print_account_info(AccountDb) ->
    AccountId = wh_util:format_account_id(AccountDb, raw),
    print_account_info(AccountDb, AccountId).    
print_account_info(AccountDb, AccountId) ->
    case couch_mgr:open_doc(AccountDb, AccountId) of
        {ok, JObj} ->
            lager:info("Account ID: ~s (~s)", [AccountId, AccountDb]),
            lager:info("  Name: ~s", [wh_json:get_value(<<"name">>, JObj)]),
            lager:info("  Realm: ~s", [wh_json:get_value(<<"realm">>, JObj)]),
            lager:info("  Enabled: ~s", [not wh_json:is_false(<<"pvt_enabled">>, JObj)]),
            lager:info("  System Admin: ~s", [wh_json:is_true(<<"pvt_superduper_admin">>, JObj)]),
            lager:info("  In Service Numbers", []),
            [lager:info("    ~s", [Number]) || Number <- wh_json:get_value(<<"pvt_wnm_in_service">>, JObj, [])];
        {error, _} ->
            lager:info("Account ID: ~s (~s)", [AccountId, AccountDb])
    end,
    {ok, AccountId}.
