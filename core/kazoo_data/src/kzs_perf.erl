%%%-------------------------------------------------------------------
%%% @copyright (C) 2011-2016, 2600Hz
%%% @doc
%%%
%%%   Profiling
%%%
%%% @end
%%% @contributors
%%%   Luis Azedo
%%%-------------------------------------------------------------------
-module(kzs_perf).

-include("kz_data.hrl").

-define(CACHE_PROFILE_FROM_FILE, wh_json:load_fixture_from_file('kazoo_data', "defaults", "perf.json")). 
-define(CACHE_PROFILE_OPTS, [{'origin', [{'db', ?WH_CONFIG_DB, ?CONFIG_CAT}]}
                             ,{'expires', 'infinity'}
                            ]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([profile/2]).

-spec profile({atom(), atom(), arity()}, list()) -> any().
profile({Mod, Fun, Arity}, Args) ->
    case profile_match(Mod, Fun, Arity) of
        #{} -> do_profile({Mod, Fun, Arity}, Args, #{});
        _ -> erlang:apply(Mod, Fun, Args)
    end.

%% ====================================================================
%% Internal functions
%% ====================================================================
-spec load_profile_config_from_disk() -> map().
load_profile_config_from_disk() ->
    Doc = ?CACHE_PROFILE_FROM_FILE,
    JObj = wh_json:get_value(<<"performance">>, Doc, wh_json:new()),
    update_profile_config(JObj).

-spec load_profile_config() -> map().
load_profile_config() ->
    case whapps_config:get(?CONFIG_CAT, <<"performance">>) of
        'undefined' -> load_profile_config_from_disk();
        JObj -> JObj
    end.

-spec profile_config() -> map().
profile_config() ->
    case kz_cache:fetch_local(?KZ_DP_CACHE, {?MODULE, 'config'}) of
        {'error', 'not_found'} ->
            wh_util:spawn(fun update_profile_config/0),
            load_profile_config_from_disk();
        {'ok', Map} -> Map
    end.

-spec update_profile_config() -> map().
update_profile_config() ->
    lager:info("defering update profile config 1 minute"),
    timer:sleep(?SECONDS_IN_MINUTE),
    update_profile_config(load_profile_config()).

-spec update_profile_config(wh_json:object()) -> map().
update_profile_config(JObj) ->
    Map = kzs_util:map_keys_to_atoms(wh_json:to_map(JObj)),
    kz_cache:store_local(?KZ_DP_CACHE, {?MODULE, 'config'}, Map, ?CACHE_PROFILE_OPTS),
    Map.
    
-spec profile_match(atom(), atom(), arity()) -> map() | 'undefined'.
profile_match(Mod, Fun, Arity) ->
    try
        #{ Mod := #{ Fun := #{'arity' := Arity, 'enabled' := 'true'}=M}} = profile_config(),
        M
    catch
        _E:_R -> 'undefined'
    end.

-spec do_profile({atom(), atom(), arity()}, list(), map()) -> any().
do_profile({Mod, Fun, _Arity}, Args, PD) ->
        [Plan, DbName | Others] = Args,
        {Time, Result} = timer:tc(fun() -> erlang:apply(Mod, Fun, Args) end),
        From = wh_util:calling_process(),
        FromList = [{wh_util:to_atom(<<"from_", (wh_util:to_binary(K))/binary>>, true), V} || {K,V} <- maps:to_list(From)],
        MD = FromList ++ maps:to_list(maps:merge(Plan, PD)),
        data:debug([{'mod', Mod}
                    ,{'func', Fun}
                    ,{'plan', Plan}
                    ,{'duration', Time}
                    ,{'database', DbName}
                    ,{'from', From}
                    | MD 
                   ],
                   "execution of {~s:~s} in database ~s with args ~p took ~b",
                   [Mod, Fun, DbName, Others, Time]),
        Result.