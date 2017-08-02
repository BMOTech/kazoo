-module(pqc_cb_service_plans).

-export([create_service_plan/2
        ,delete_service_plan/2
        ,assign_service_plan/3
        ]).

-include("kazoo_proper.hrl").

-spec create_service_plan(pqc_cb_api:state(), kzd_service_plan:doc()) ->
                                 {'ok', kzd_service_plan:doc()} |
                                 {'error', any()}.
create_service_plan(_API, ServicePlan) ->
    %% No API to add service plans to master account
    %% Doing so manually for now
    {'ok', MasterAccountDb} = kapps_util:get_master_account_db(),
    kz_datamgr:save_doc(MasterAccountDb, ServicePlan).

-spec delete_service_plan(pqc_cb_api:state(), ne_binary()) ->
                                 {'ok', kz_json:object()} |
                                 {'error', any()}.
delete_service_plan(_API, ServicePlanId) ->
    {'ok', MasterAccountDb} = kapps_util:get_master_account_db(),
    kz_datamgr:del_doc(MasterAccountDb, ServicePlanId).

-spec assign_service_plan(pqc_cb_api:state(), ne_binary() | proper_types:type(), ne_binary()) -> pqc_cb_api:response().
assign_service_plan(API, AccountId, ServicePlanId) ->
    URL = account_service_plan_url(AccountId),
    RequestHeaders = pqc_cb_api:request_headers(API),

    RequestData = kz_json:from_list([{<<"add">>, [ServicePlanId]}]),
    RequestEnvelope = pqc_cb_api:create_envelope(RequestData),

    pqc_cb_api:make_request([200, 404]
                           ,fun kz_http:post/3
                           ,URL
                           ,RequestHeaders
                           ,kz_json:encode(RequestEnvelope)
                           ).

-spec account_service_plan_url(ne_binary()) -> string().
account_service_plan_url(AccountId) ->
    string:join([pqc_cb_accounts:account_url(AccountId), "service_plans"], "/").
