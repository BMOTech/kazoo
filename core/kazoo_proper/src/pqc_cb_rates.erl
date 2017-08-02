-module(pqc_cb_rates).
-behaviour(proper_statem).

-export([seq/0, cleanup/0]).

-export([upload_rate/2
        ,rate_did/3
        ,delete_rate/2
        ,get_rate/2
        ,get_rates/1, get_rates/2

        ,create_service_plan/2
        ,assign_service_plan/3
        ,rate_account_did/3
        ]).

-export([command/1
        ,initial_state/0
        ,next_state/3
        ,postcondition/3
        ,precondition/2

        ,correct/0
        ,correct_parallel/0
        ]).

-include_lib("proper/include/proper.hrl").
-include("kazoo_proper.hrl").
-include_lib("kazoo_stdlib/include/kz_databases.hrl").

-define(RATE_ID, <<"XX-1222">>).
-define(RATEDECK_NAMES, [?KZ_RATES_DB, <<"custom">>]).
-define(PHONE_NUMBERS, [<<"+12223334444">>]).
-define(ACCOUNT_NAMES, [<<"account_for_rates">>]).

-define(GLOBAL_COST, 1).
-define(ACCOUNT_COST, 4).

-spec rate_doc(ne_binary() | proper_types:type(), number() | proper_types:type()) ->
                      kzd_rate:doc().
rate_doc(RatedeckId, Cost) ->
    kzd_rate:from_map(#{<<"prefix">> => <<"1222">>
                       ,<<"rate_cost">> => Cost
                       ,<<"ratedeck_id">> => RatedeckId
                       }
                     ).

-spec upload_rate(cb_pqc_api:state(), kzd_rate:doc()) -> {'ok', api_ne_binary()}.
upload_rate(API, RateDoc) ->
    CSV = kz_csv:from_jobjs([RateDoc]),

    CreateResp = pqc_cb_tasks:create(API, "category=rates&action=import", CSV),
    TaskId = kz_json:get_ne_binary_value([<<"data">>, <<"_read_only">>, <<"id">>], kz_json:decode(CreateResp)),
    _ExecResp = pqc_cb_tasks:execute(API, TaskId),
    create_service_plan(API, kzd_rate:ratedeck(RateDoc)),
    _DelResp = wait_for_task(API, TaskId),

    {'ok', TaskId}.

-spec create_service_plan(pqc_cb_api:state(), ne_binary() | proper_types:type()) -> 'ok'.
create_service_plan(API, RatedeckId) ->
    case pqc_cb_service_plans:create_service_plan(API, ratedeck_service_plan(RatedeckId)) of
        {'ok', _} -> 'ok';
        {'error', 'conflict'} -> 'ok'
    end.

-spec assign_service_plan(pqc_cb_api:state(), ne_binary() | proper_types:type(), ne_binary()) ->
                                 pqc_cb_api:response().
assign_service_plan(_API, 'undefined', _RatedeckId) ->
    ?FAILED_RESPONSE;
assign_service_plan(API, AccountId, RatedeckId) ->
    ServicePlanId = service_plan_id(RatedeckId),
    pqc_cb_service_plans:assign_service_plan(API, AccountId, ServicePlanId).

-spec rate_account_did(pqc_cb_api:state(), ne_binary() | proper_types:type(), ne_binary()) ->
                              pqc_cb_api:response().
rate_account_did(_API, 'undefined', _DID) ->
    ?FAILED_RESPONSE;
rate_account_did(API, AccountId, DID) ->
    URL = string:join([pqc_cb_accounts:account_url(AccountId), "rates", "number", kz_term:to_list(DID)], "/"),
    RequestHeaders = pqc_cb_api:request_headers(API),
    pqc_cb_api:make_request([200]
                           ,fun kz_http:get/2
                           ,URL
                           ,RequestHeaders
                           ).

-spec ratedeck_service_plan(ne_binary() | kzd_rate:doc()) -> kzd_service_plan:doc().
ratedeck_service_plan(<<_/binary>> = RatedeckId) ->
    Plan = kz_json:from_list([{<<"ratedeck">>
                              ,kz_json:from_list([{RatedeckId, kz_json:new()}])
                              }
                             ]),
    Funs = [{fun kzd_service_plan:set_plan/2, Plan}],

    lists:foldl(fun({F, V}, Acc) -> F(Acc, V) end
               ,kz_json:from_list([{<<"_id">>, service_plan_id(RatedeckId)}
                                  ,{<<"pvt_type">>, <<"service_plan">>}
                                  ,{<<"name">>, <<RatedeckId/binary, " Ratedeck Service Plan">>}
                                  ])
               ,Funs
               );
ratedeck_service_plan(RateDoc) ->
    ratedeck_service_plan(kzd_rate:ratedeck(RateDoc)).

service_plan_id(RatedeckId) ->
    <<"plan_ratedeck_", RatedeckId/binary>>.

wait_for_task(API, TaskId) ->
    GetResp = pqc_cb_tasks:fetch(API, TaskId),
    case kz_json:get_value([<<"data">>, <<"_read_only">>, <<"status">>]
                          ,kz_json:decode(GetResp)
                          )
    of
        <<"success">> -> pqc_cb_tasks:delete(API, TaskId);
        _Status ->
            timer:sleep(1000),
            wait_for_task(API, TaskId)
    end.

-spec delete_rate(cb_pqc_api:state(), ne_binary() | kzd_rate:doc()) -> pqc_cb_api:response().
delete_rate(API, <<_/binary>>=RatedeckId) ->
    delete_rate(API, ?RATE_ID, RatedeckId);
delete_rate(API, RateDoc) ->
    delete_rate(API, ?RATE_ID, kzd_rate:ratedeck(RateDoc)).

-spec delete_rate(cb_pqc_api:state(), ne_binary(), ne_binary()) -> pqc_cb_api:response().
delete_rate(API, ID, <<_/binary>>=RatedeckId) ->
    _ = pqc_cb_service_plans:delete_service_plan(API, RatedeckId),

    URL = rate_url(ID, RatedeckId),
    pqc_cb_api:make_request([200, 404]
                           ,fun kz_http:delete/2
                           ,URL ++ "&should_soft_delete=false"
                           ,pqc_cb_api:request_headers(API)
                           ).

-spec get_rate(cb_pqc_api:state(), kzd_rate:doc()) -> pqc_cb_api:response().
get_rate(API, RateDoc) ->
    ID = kz_doc:id(RateDoc),
    URL = rate_url(ID, kzd_rate:ratedeck(RateDoc)),
    pqc_cb_api:make_request([200, 404]
                           ,fun kz_http:get/2
                           ,URL
                           ,pqc_cb_api:request_headers(API)
                           ).

-spec get_rates(cb_pqc_api:state()) -> cb_pqc_api:response().
-spec get_rates(cb_pqc_api:state(), ne_binary()) -> cb_pqc_api:response().
get_rates(API) ->
    get_rates(API, ?KZ_RATES_DB).
get_rates(API, RatedeckId) ->
    pqc_cb_api:make_request([200]
                           ,fun kz_http:get/2
                           ,rates_url() ++ "?ratedeck_id=" ++ kz_term:to_list(RatedeckId)
                           ,pqc_cb_api:request_headers(API)
                           ).

-spec rate_did(cb_pqc_api:state(), ne_binary(), ne_binary()) -> cb_pqc_api:response().
rate_did(API, RatedeckId, DID) ->
    URL = rate_number_url(RatedeckId, DID),
    RequestHeaders = pqc_cb_api:request_headers(API),

    Resp = pqc_cb_api:make_request([200, 500]
                                  ,fun kz_http:get/2
                                  ,URL
                                  ,RequestHeaders
                                  ),
    RespJObj = kz_json:decode(Resp),
    case kz_json:get_ne_binary_value(<<"status">>, RespJObj) of
        <<"error">> -> 'undefined';
        <<"success">> -> kz_json:get_integer_value([<<"data">>, <<"Rate">>], RespJObj)
    end.

rates_url() ->
    string:join([pqc_cb_api:v2_base_url(), "rates"], "/").

rate_number_url(RatedeckId, DID) ->
    rate_did_url(pqc_cb_api:v2_base_url(), DID) ++ "?ratedeck_id=" ++ kz_term:to_list(RatedeckId).

rate_url(ID, RatedeckId) ->
    string:join([pqc_cb_api:v2_base_url(), "rates", kz_term:to_list(ID)], "/")
        ++ "?ratedeck_id=" ++ kz_term:to_list(RatedeckId).

rate_did_url(Base, DID) ->
    string:join([Base, "rates", "number", kz_term:to_list(kz_http_util:urlencode(DID))], "/").

-spec correct() -> any().
correct() ->
    init(),
    ?FORALL(Cmds
           ,commands(?MODULE)
           ,?TRAPEXIT(
               begin
                   {History, Model, Result} = run_commands(?MODULE, Cmds),

                   cleanup(pqc_kazoo_model:api(Model)),

                   ?WHENFAIL(io:format("Final Model : ~p~nFailing Cmds: ~p~n"
                                      ,[Model, zip(Cmds, History)]
                                      )
                            ,aggregate(command_names(Cmds), Result =:= 'ok')
                            )
               end
              )
           ).

-spec correct_parallel() -> any().
correct_parallel() ->
    init(),
    ?FORALL(Cmds
           ,parallel_commands(?MODULE)
           ,?TRAPEXIT(
               begin
                   {Sequential, Parallel, Result} = run_parallel_commands(?MODULE, Cmds),
                   cleanup(),

                   ?WHENFAIL(io:format("S: ~p~nP: ~p~n", [Sequential, Parallel])
                            ,aggregate(command_names(Cmds), Result =:= 'ok')
                            )
               end
              )
           ).

init() ->
    _ = [kapps_controller:start_app(App) ||
            App <- ['crossbar', 'hotornot', 'tasks']
        ],
    _ = [crossbar_maintenance:start_module(Mod) ||
            Mod <- ['cb_tasks', 'cb_rates', 'cb_accounts']
        ],
    'ok'.

-spec cleanup() -> 'ok'.
cleanup() ->
    cleanup(pqc_cb_api:authenticate()).

cleanup(API) ->
    _ = [?MODULE:delete_rate(API, RatedeckId) || RatedeckId <- ?RATEDECK_NAMES],
    _ = pqc_cb_accounts:cleanup_accounts(API, ?ACCOUNT_NAMES),
    _ = [pqc_cb_service_plans:delete_service_plan(API, RatedeckId) || RatedeckId <- ?RATEDECK_NAMES],
    pqc_cb_api:cleanup(API).

-spec initial_state() -> pqc_kazoo_model:model().
initial_state() ->
    API = pqc_cb_api:authenticate(),
    pqc_kazoo_model:new(API).

-spec seq() -> any().
seq() ->
    init(),
    Model = initial_state(),
    API = pqc_kazoo_model:api(Model),

    try
        RateDoc = rate_doc(?KZ_RATES_DB, 1),

        _Up = ?MODULE:upload_rate(API, RateDoc),
        ?INFO("upload: ~p~n", [_Up]),

        _Get = ?MODULE:get_rate(API, RateDoc),
        ?INFO("get: ~p~n", [_Get]),

        _Rated = ?MODULE:rate_did(API, kzd_rate:ratedeck(RateDoc), hd(?PHONE_NUMBERS)),
        ?INFO("rated: ~p~n", [_Rated]),

        _SP = ?MODULE:create_service_plan(API, kzd_rate:ratedeck(RateDoc)),
        ?INFO("created sp: ~p~n", [_SP]),

        AccountResp = pqc_cb_accounts:create_account(API, hd(?ACCOUNT_NAMES)),
        AccountId = kz_json:get_value([<<"data">>, <<"id">>], kz_json:decode(AccountResp)),

        case is_binary(AccountId) of
            'true' -> ?INFO("created account ~s~n", [AccountId]);
            'false' ->
                ?INFO("failed to get account id from ~s~n", [AccountResp]),
                throw(no_account_id)
        end,

        PlanId = service_plan_id(kzd_rate:ratedeck(RateDoc)),
        _Assigned = ?MODULE:assign_service_plan(API, AccountId, kzd_rate:ratedeck(RateDoc)),
        case kz_json:get_value([<<"data">>, <<"plan">>, <<"ratedeck">>, PlanId]
                              ,kz_json:decode(_Assigned)
                              )
        of
            'undefined' ->
                ?ERROR("failed to assign plan ~s to account ~s", [PlanId, AccountId]),
                throw(no_plan);
            _ ->
                ?INFO("assigned service plan to account: ~p~n", [_Assigned])
        end,

        _AcctRated = ?MODULE:rate_account_did(API, AccountId, hd(?PHONE_NUMBERS)),
        ?INFO("rated ~s in account ~s: ~p~n", [hd(?PHONE_NUMBERS), AccountId, _AcctRated]),

        _Deleted = ?MODULE:delete_rate(API, RateDoc),
        ?INFO("deleted: ~p~n", [_Deleted])
    catch
        _E:_R ->
            ST = erlang:get_stacktrace(),
            ?INFO("crashed ~s: ~p~n", [_E, _R]),
            io:format("crashed ~s: ~p~n", [_E, _R]),
            [begin
                 ?INFO("s: ~p~n", [S]),
                 io:format("s: ~p~n", [S])
             end
             || S <- ST
            ]
    after
        cleanup(API),
        io:format("done: ~p~n", [API])
    end.

-spec command(any()) -> proper_types:type().
command(Model) ->
    API = pqc_kazoo_model:api(Model),

    AccountName = account_name(),
    AccountId = pqc_cb_accounts:symbolic_account_id(Model, AccountName),

    oneof([{'call', ?MODULE, 'upload_rate', [API, rate_doc(ratedeck_id(), rate_cost())]}
          ,{'call', ?MODULE, 'delete_rate', [API, ratedeck_id()]}
          ,{'call', ?MODULE, 'rate_did', [API, ratedeck_id(), phone_number()]}
          ,pqc_cb_accounts:command(Model, AccountName)
          ,{'call', ?MODULE, 'create_service_plan', [API, ratedeck_id()]}
          ,{'call', ?MODULE, 'assign_service_plan', [API, AccountId, ratedeck_id()]}
          ,{'call', ?MODULE, 'rate_account_did', [API, AccountId, phone_number()]}
          ]).

ratedeck_id() ->
    oneof(?RATEDECK_NAMES).

rate_cost() ->
    range(1,10).

phone_number() ->
    elements(?PHONE_NUMBERS).

account_name() ->
    oneof(?ACCOUNT_NAMES).

-spec next_state(pqc_kazoo_model:model(), any(), any()) -> pqc_kazoo_model:model().
next_state(Model, APIResp, {'call', _, 'create_account', _Args}=Call) ->
    pqc_cb_accounts:next_state(Model, APIResp, Call);
next_state(Model
          ,_APIResp
          ,{'call', _, 'upload_rate', [_API, RateDoc]}
          ) ->
    Ratedeck = kzd_rate:ratedeck(RateDoc, ?KZ_RATES_DB),
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:is_rate_missing/3, [Ratedeck, RateDoc]}
                           ,{fun pqc_kazoo_model:add_rate_to_ratedeck/3, [Ratedeck, RateDoc]}
                           ]);
next_state(Model
          ,_APIResp
          ,{'call', _, 'delete_rate', [_API, RatedeckId]}
          ) ->
    RateDoc = rate_doc(RatedeckId, 0),
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_rate_exist/3, [RatedeckId, RateDoc]}
                           ,{fun pqc_kazoo_model:remove_rate_from_ratedeck/3, [RatedeckId, RateDoc]}
                           ]);
next_state(Model
          ,_APIResp
          ,{'call', _, 'rate_did', [_API, _RatedeckId, _PhoneNumber]}
          ) ->
    Model;
next_state(Model
          ,_APIResp
          ,{'call', ?MODULE, 'create_service_plan', [_API, RatedeckId]}
          ) ->
    PlanId = service_plan_id(RatedeckId),
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:add_service_plan/2, [PlanId]}]
                          );
next_state(Model
          ,_APIResp
          ,{'call', ?MODULE, 'assign_service_plan', [_API, AccountId, RatedeckId]}
          ) ->
    PlanId = service_plan_id(RatedeckId),
    pqc_util:transition_if(Model
                          ,[{fun pqc_kazoo_model:does_account_exist/2, [AccountId]}
                           ,{fun pqc_kazoo_model:does_service_plan_exist/2, [PlanId]}
                           ,{fun pqc_kazoo_model:add_service_plan/2, [AccountId, RatedeckId]}
                           ]
                          );
next_state(Model
          ,_APIResp
          ,{'call', ?MODULE, 'rate_account_did', [_API, _AccountId, _DID]}
          ) ->
    Model.

-spec precondition(pqc_kazoo_model:model(), any()) -> boolean().
precondition(_Model, _Call) -> 'true'.

-spec postcondition(pqc_kazoo_model:model(), any(), any()) -> boolean().
postcondition(Model, {'call', _, 'create_account', _Args}=Call, APIResult) ->
    pqc_cb_accounts:postcondition(Model, Call, APIResult);
postcondition(_Model
             ,{'call', _, 'upload_rate', [_API, _RateDoc]}
             ,{'ok', _TaskId}
             ) ->
    'true';
postcondition(_Model
             ,{'call', _, 'delete_rate', [_API, _RateDoc]}
             ,_APIResult
             ) ->
    'true';
postcondition(Model
             ,{'call', _, 'rate_did', [_API, RatedeckId, PhoneNumber]}
             ,APIResult
             ) ->
    matches_cost(Model, RatedeckId, PhoneNumber, APIResult);
postcondition(_Model
             ,{'call', ?MODULE, 'create_service_plan', [_API, _RatedeckId]}
             ,APIResult
             ) ->
    'ok' =:= APIResult;
postcondition(_Model
             ,{'call', ?MODULE, 'assign_service_plan', [_API, 'undefined', _RatedeckId]}
             ,?FAILED_RESPONSE
             ) ->
    'true';
postcondition(Model
             ,{'call', ?MODULE, 'assign_service_plan', [_API, _AccountId, RatedeckId]}
             ,APIResult
             ) ->
    PlanId = service_plan_id(RatedeckId),
    case pqc_kazoo_model:does_service_plan_exist(Model, PlanId) of
        'true' ->
            'undefined' =/=
                kz_json:get_value([<<"data">>, <<"plan">>, <<"ratedeck">>, PlanId]
                                 ,kz_json:decode(APIResult)
                                 );
        'false' ->
            ?FAILED_RESPONSE
    end;
postcondition(_Model
             ,{'call', ?MODULE, 'rate_account_did', [_API, 'undefined', _DID]}
             ,?FAILED_RESPONSE
             ) ->
    'true';
postcondition(Model
             ,{'call', ?MODULE, 'rate_account_did', [_API, AccountId, DID]}
             ,APIResult
             ) ->
    matches_service_plan_cost(Model, AccountId, DID, APIResult).

matches_service_plan_cost(Model, AccountId, DID, APIResult) ->
    case pqc_kazoo_model:has_service_plan_rate_matching(Model, AccountId, DID) of
        {'true', Cost} when is_number(APIResult) ->
            Cost =:= wht_util:dollars_to_units(APIResult);
        {'true', _Cost} ->
            'false';
        'false' ->
            'undefined' =:= APIResult
    end.

matches_cost(Model, RatedeckId, PhoneNumber, APIResult) ->
    case pqc_kazoo_model:has_rate_matching(Model, RatedeckId, PhoneNumber) of
        {'true', Cost} when is_number(APIResult) ->
            Cost =:= wht_util:dollars_to_units(APIResult);
        {'true', _Cost} ->
            'false';
        'false' ->
            'undefined' =:= APIResult
    end.
