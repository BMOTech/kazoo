-module(pqc_cb_service_plans).

-export([create_service_plan/2
        ,delete_service_plan/2
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
