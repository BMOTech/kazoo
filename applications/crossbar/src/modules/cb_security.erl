%%%-------------------------------------------------------------------
%%% @copyright (C) 2017, 2600Hz INC
%%% @doc
%%%
%%% Kazoo authentication configuration API endpoint
%%%
%%% @end
%%% @contributors:
%%%-------------------------------------------------------------------
-module(cb_security).

-export([init/0
        ,authorize/1, authorize/2, authorize/3
        ,allowed_methods/0, allowed_methods/1, allowed_methods/2
        ,resource_exists/0, resource_exists/1, resource_exists/2
        ,validate/1, validate/2, validate/3
        ,put/1
        ,post/1
        ,patch/1
        ,delete/1
        ]).

-include("crossbar.hrl").

-define(DEFAULT_AUTH_METHODS, [<<"cb_user_auth">>
                              ,<<"cb_api_auth">>
                              ,<<"cb_auth">>
                              ,<<"cb_ip_auth">>
                              ,<<"cb_ubiquiti_auth">>
                              ]).

-define(SYSTEM_AUTH_METHODS
       ,kapps_config:get_ne_binaries(?AUTH_CONFIG_CAT, <<"available_auth_methods">>, ?DEFAULT_AUTH_METHODS)
       ).

-define(AVAILABLE_AUTH_METHODS
       ,kz_json:from_list([{<<"available_auth_methods">>, ?SYSTEM_AUTH_METHODS}])
       ).

-define(CB_LIST_ATTEMPT_LOG, <<"auth/login_attempt_by_time">>).

-define(ATTEMPTS, <<"attempts">>).
-define(AUTH_ATTEMPT_TYPE, <<"login_attempt">>).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Initializes the bindings this module will respond to.
%% @end
%%--------------------------------------------------------------------
-spec init() -> 'ok'.
init() ->
    _ = crossbar_bindings:bind(<<"*.authorize.security">>, ?MODULE, 'authorize'),
    _ = crossbar_bindings:bind(<<"*.allowed_methods.security">>, ?MODULE, 'allowed_methods'),
    _ = crossbar_bindings:bind(<<"*.resource_exists.security">>, ?MODULE, 'resource_exists'),
    _ = crossbar_bindings:bind(<<"*.validate.security">>, ?MODULE, 'validate'),
    _ = crossbar_bindings:bind(<<"*.execute.get.security">>, ?MODULE, 'get'),
    _ = crossbar_bindings:bind(<<"*.execute.put.security">>, ?MODULE, 'put'),
    _ = crossbar_bindings:bind(<<"*.execute.post.security">>, ?MODULE, 'post'),
    _ = crossbar_bindings:bind(<<"*.execute.patch.security">>, ?MODULE, 'patch'),
    _ = crossbar_bindings:bind(<<"*.execute.delete.security">>, ?MODULE, 'delete').

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Authorizes the incoming request, returning true if the requestor is
%% allowed to access the resource, or false if not.
%% @end
%%--------------------------------------------------------------------
-spec authorize(cb_context:context()) ->
                       boolean() |
                       {'halt', cb_context:context()}.
authorize(Context) ->
    authorize_list_available_module(Context, cb_context:req_nouns(Context), cb_context:req_verb(Context)).

-spec authorize(cb_context:context(), path_token()) -> 'true'.
authorize(_Context, _) -> 'true'.

-spec authorize(cb_context:context(), path_token(), path_token()) -> 'true'.
authorize(_Context, _, _) -> 'true'.

-spec authorize_list_available_module(cb_context:context(), req_nouns(), http_method()) ->
                                             boolean() |
                                             {'halt', cb_context:context()}.
authorize_list_available_module(_Context, [{<<"security">>, []}], ?HTTP_GET) ->
    'true';
authorize_list_available_module(Context, [{<<"security">>, []}], _) ->
    {'halt', cb_context:add_system_error('forbidden', Context)};
authorize_list_available_module(_Context, _Nouns, _Verb) ->
    'true'.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Given the path tokens related to this module, what HTTP methods are
%% going to be responded to.
%% @end
%%--------------------------------------------------------------------
-spec allowed_methods() -> http_methods().
allowed_methods() ->
    [?HTTP_GET, ?HTTP_PUT, ?HTTP_POST, ?HTTP_PATCH, ?HTTP_DELETE].

-spec allowed_methods(path_token()) -> http_methods().
allowed_methods(?ATTEMPTS) ->
    [?HTTP_GET].

-spec allowed_methods(path_token(), path_token()) -> http_methods().
allowed_methods(?ATTEMPTS, _AttemptId) ->
    [?HTTP_GET].

%%--------------------------------------------------------------------
%% @public
%% @doc
%% Does the path point to a valid resource
%% So /security => []
%%    /security/foo => [<<"foo">>]
%%    /security/foo/bar => [<<"foo">>, <<"bar">>]
%% @end
%%--------------------------------------------------------------------
-spec resource_exists() -> 'true'.
resource_exists() -> 'true'.

-spec resource_exists(path_token()) -> 'true'.
resource_exists(?ATTEMPTS) -> 'true';
resource_exists(_ConfigId) -> 'false'.

-spec resource_exists(path_token(), path_token()) -> 'true'.
resource_exists(?ATTEMPTS, _AttemptId) -> 'true'.
%%--------------------------------------------------------------------
%% @public
%% @doc
%% Check the request (request body, query string params, path tokens, etc)
%% and load necessary information.
%% /security mights load a list of auth objects
%% /security/123 might load the auth object 123
%% Generally, use crossbar_doc to manipulate the cb_context{} record
%% @end
%%--------------------------------------------------------------------
-spec validate(cb_context:context()) -> cb_context:context().
validate(Context) ->
    validate_auth_configs(Context, cb_context:req_verb(Context)).

-spec validate(cb_context:context(), path_token()) -> cb_context:context().
validate(Context, ?ATTEMPTS) ->
    crossbar_view:load(Context, ?CB_LIST_ATTEMPT_LOG, [{mapper, fun normalize_attempt_view_result/1}]).

-spec validate(cb_context:context(), path_token(), path_token()) -> cb_context:context().
validate(Context, ?ATTEMPTS, AttemptId) ->
    read_attempt_log(AttemptId, Context).

%% validates /security
-spec validate_auth_configs(cb_context:context(), http_method()) -> cb_context:context().
validate_auth_configs(Context, ?HTTP_GET) ->
    case cb_context:req_nouns(Context) of
        [{<<"security">>, []}] -> summary_available(Context);
        [{<<"security">>, []}, {<<"accounts">>, [?NE_BINARY=_Id]}] -> read(Context);
        _Nouns -> Context
    end;
validate_auth_configs(Context, ?HTTP_PUT) ->
    create(Context);
validate_auth_configs(Context, ?HTTP_POST) ->
    ConfigId = kapps_config_util:account_doc_id(?AUTH_CONFIG_CAT),
    update(ConfigId, Context);
validate_auth_configs(Context, ?HTTP_PATCH) ->
    ConfigId = kapps_config_util:account_doc_id(?AUTH_CONFIG_CAT),
    validate_patch(ConfigId, Context);
validate_auth_configs(Context, ?HTTP_DELETE) ->
    C1 = crossbar_doc:load(?ACCOUNT_AUTH_CONFIG_ID, Context, ?TYPE_CHECK_OPTION(<<"account_config">>)),
    case cb_context:resp_status(C1) of
        'success' -> C1;
        _ ->
            Msg = <<"account does not have customize auth configuration">>,
            cb_context:add_system_error('bad_identifier', kz_json:from_list([{<<"cause">>, Msg}]),  Context)
    end.

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is PUT, execute the actual action, usually a db save.
%% @end
%%--------------------------------------------------------------------
-spec put(cb_context:context()) -> cb_context:context().
put(Context) ->
    crossbar_doc:save(Context).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is POST, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%--------------------------------------------------------------------
-spec post(cb_context:context()) -> cb_context:context().
post(Context) ->
    crossbar_doc:save(Context).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is PATCH, execute the actual action, usually a db save
%% (after a merge perhaps).
%% @end
%%--------------------------------------------------------------------
-spec patch(cb_context:context()) -> cb_context:context().
patch(Context) ->
    crossbar_doc:save(Context).

%%--------------------------------------------------------------------
%% @public
%% @doc
%% If the HTTP verb is DELETE, execute the actual action, usually a db delete
%% @end
%%--------------------------------------------------------------------
-spec delete(cb_context:context()) -> cb_context:context().
delete(Context) ->
    crossbar_doc:delete(Context, ?HARD_DELETE).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Attempt to load a summarized listing of all instances of this
%% resource.
%% @end
%%--------------------------------------------------------------------
-spec summary_available(cb_context:context()) -> cb_context:context().
summary_available(Context) ->
    Setters = [{fun cb_context:set_resp_status/2, 'success'}
              ,{fun cb_context:set_resp_data/2, ?AVAILABLE_AUTH_METHODS}
              ],
    cb_context:setters(Context, Setters).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load an instance from the database
%% @end
%%--------------------------------------------------------------------
-spec read(cb_context:context()) -> cb_context:context().
read(Context) ->
    InheritedConfig = crossbar_auth:get_inherited_auth_config(cb_context:account_id(Context)),
    ConfigId = kapps_config_util:account_doc_id(?AUTH_CONFIG_CAT),

    Doc = kz_json:from_list([{<<"inherited_config">>, InheritedConfig}]),

    C1 = crossbar_doc:load(ConfigId, Context, ?TYPE_CHECK_OPTION(<<"account_config">>)),
    case cb_context:resp_status(C1) of
        'success' ->
            NewDoc = kz_json:set_value(<<"account">>, cb_context:doc(C1), Doc),
            cb_context:set_resp_data(Context, NewDoc);
        _ ->
            crossbar_doc:handle_json_success(kz_json:set_value(<<"account">>, kz_json:new(), Doc), Context)
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Create a new instance with the data provided, if it is valid
%% @end
%%--------------------------------------------------------------------
-spec create(cb_context:context()) -> cb_context:context().
create(Context) ->
    OnSuccess = fun(C) -> on_successful_validation('undefined', C) end,
    SchemaName = kapps_config_util:account_schema_name(?AUTH_CONFIG_CAT),
    cb_context:validate_request_data(SchemaName, Context, OnSuccess).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Update an existing menu document with the data provided, if it is
%% valid
%% @end
%%--------------------------------------------------------------------
-spec update(ne_binary(), cb_context:context()) -> cb_context:context().
update(Id, Context) ->
    OnSuccess = fun(C) -> on_successful_validation(Id, C) end,
    SchemaName = kapps_config_util:account_schema_name(?AUTH_CONFIG_CAT),
    cb_context:validate_request_data(SchemaName, Context, OnSuccess).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Update-merge an existing menu document with the data provided, if it is
%% valid
%% @end
%%--------------------------------------------------------------------
-spec validate_patch(ne_binary(), cb_context:context()) -> cb_context:context().
validate_patch(Id, Context) ->
    crossbar_doc:patch_and_validate(Id, Context, fun update/2).

%%--------------------------------------------------------------------
%% @private
%% @doc
%%
%% @end
%%--------------------------------------------------------------------
-spec on_successful_validation(api_binary(), cb_context:context()) -> cb_context:context().
on_successful_validation('undefined', Context) ->
    ConfigId = kapps_config_util:account_doc_id(?AUTH_CONFIG_CAT),
    Doc = kz_doc:set_id(cb_context:doc(Context), ConfigId),
    cb_context:set_doc(Context, kz_doc:set_type(Doc, <<"account_config">>));
on_successful_validation(Id, Context) ->
    crossbar_doc:load_merge(Id, Context, ?TYPE_CHECK_OPTION(<<"account_config">>)).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Load a login attempt log from MODB
%% @end
%%--------------------------------------------------------------------
-spec read_attempt_log(ne_binary(), cb_context:context()) -> cb_context:context().
read_attempt_log(?MATCH_MODB_PREFIX(Year, Month, _)=AttemptId, Context) ->
    crossbar_doc:load(AttemptId, cb_context:set_account_modb(Context, Year, Month), ?TYPE_CHECK_OPTION(?AUTH_ATTEMPT_TYPE)).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Normalizes the resuts of a view
%% @end
%%--------------------------------------------------------------------
-spec normalize_attempt_view_result(kz_json:object()) -> kz_json:object().
normalize_attempt_view_result(JObj) ->
    kz_json:get_value(<<"value">>, JObj).
