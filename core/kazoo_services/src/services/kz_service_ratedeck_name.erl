%%%-------------------------------------------------------------------
%%% @copyright (C) 2012-2017, 2600Hz, INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%     Sergey Korobkov
%%%-------------------------------------------------------------------
-module(kz_service_ratedeck_name).

-export([reconcile/1, reconcile/2]).
-export([get_ratedeck_name/1]).

-include("kazoo_services.hrl").

-define(SERVICE_CATEGORY, <<"ratedeck_name">>).

%%--------------------------------------------------------------------
%% @public
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec reconcile(kz_services:services()) -> kz_services:services().
-spec reconcile(kz_services:services(), api_binary()) -> kz_services:services().
reconcile(Services) ->
    ServicePlanJObj = kz_services:service_plan_json(Services),
    %% TODO: resolve conflict when there is more than one ratedeck

    case kzd_service_plan:items(ServicePlanJObj, ?SERVICE_CATEGORY) of
        [] ->
            lager:info("no keys in cat plan ~p, resetting"),
            kz_services:reset_category(?SERVICE_CATEGORY, Services);
        [RatedeckId] ->
            lager:info("ratedeck ~s found", [RatedeckId]),
            kz_services:update(?SERVICE_CATEGORY, RatedeckId, 1, Services);
        [_|_] = R ->
            AccountId = kz_services:account_id(Services),
            kz_notify:system_alert("several ratedeck names ~p for account ~s", [R, AccountId]),
            lager:error("several ratedeck names ~p for account ~s", [R, AccountId]),
            Services
    end.

reconcile(Services, 'undefined') ->
    kz_services:reset_category(?SERVICE_CATEGORY, Services);
reconcile(Services, RatedeckName) ->
    kz_services:update(?SERVICE_CATEGORY, RatedeckName, 1, Services).

-spec get_ratedeck_name(api_binary() | kz_services:services()) -> api_binary().
get_ratedeck_name('undefined') -> 'undefined';
get_ratedeck_name(<<_/binary>> = AccountId) ->
    get_ratedeck_name(kz_services:service_plan_json(AccountId));
get_ratedeck_name(ServicePlan) ->
    case kzd_service_plan:items(ServicePlan, ?SERVICE_CATEGORY) of
        [] -> 'undefined';
        [RatedeckId] -> RatedeckId
    end.