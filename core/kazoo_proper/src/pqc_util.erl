-module(pqc_util).

-export([transition_if/2
        ,simple_counterexample/0
        ,run_counterexample/1
        ]).

-include("kazoo_proper.hrl").

-spec transition_if(pqc_kazoo_model:model(), [{fun(), list()}]) -> pqc_kazoo_model:model().
transition_if(CurrentModel, Checks) ->
    case lists:foldl(fun transition_if_fold/2, {'true', CurrentModel}, Checks) of
        {'true', UpdatedModel} -> UpdatedModel;
        {'false', _} -> CurrentModel
    end.

-spec transition_if_fold({fun(), list()}, {boolean(), pqc_kazoo_model:model()}) ->
                                {boolean(), pqc_kazoo_model:model()}.
transition_if_fold({_Fun, _Args}, {'false', _}=False) -> False;
transition_if_fold({Fun, Args}, {'true', Model}) ->
    case apply(Fun, [Model | Args]) of
        'false' -> {'false', Model};
        'true' -> {'true', Model};
        {'true', _NewState}=True -> True;
        NewModel -> {'true', NewModel}
    end.

-spec simple_counterexample() -> [{module(), function(), list()}].
simple_counterexample() ->
    simple_counterexample(proper:counterexample()).

simple_counterexample([Seq]) ->
    [{M, F, ['{API}'|cleanup_args(Args)]}
     || {set, _Var, {call, M, F, [_|Args]}} <- Seq
    ].

cleanup_args(Args) ->
    [cleanup_arg(Arg) || Arg <- Args].
cleanup_arg({call, M, F, Args}) ->
    {M,F, length(Args)};
cleanup_arg(Arg) -> Arg.


-spec run_counterexample(module()) -> {integer(), module(), any()}.
run_counterexample(PQC) ->
    try run_counterexample(PQC, proper:counterexample(), PQC:initial_state()) of
        OK -> OK
    catch
        E:R -> {E, R, erlang:get_stacktrace()}
    after
        PQC:cleanup()
    end.

run_counterexample(PQC, [{Seq, Threads}], State) ->
    Steps = lists:usort(fun sort_steps/2, Seq ++ lists:flatten(Threads)),
    lists:foldl(fun run_step/2, {0, PQC, State}, Steps);
run_counterexample(PQC, [Steps], State) ->
    lists:foldl(fun run_step/2, {0, PQC, State}, Steps).

sort_steps({'set', Var1, _Call1}, {'set', Var2, _Call2}) ->
    Var1 < Var2.

run_step({'set', Var, Call}, {Step, PQC, State}) ->
    run_call(Var, Call, {Step, PQC, State}).

run_call(_Var, {'call', M, F, Args}=Call, {Step, PQC, State}) ->
    io:format('user', "(~p) ~p:~p(~p) -> ", [Step, M, F, Args]),
    Args1 = resolve_args(Args),
    Resp = erlang:apply(M, F, Args1),
    io:format('user', "~p~n~n", [Resp]),
    'true' = PQC:postcondition(State, Call, Resp),
    {Step+1, PQC, PQC:next_state(State, Resp, Call)}.

resolve_args(Args) ->
    [resolve_arg(Arg) || Arg <- Args].

resolve_arg({'call', M, F, Args}) ->
    io:format("  resolving ~p:~p(~p)~n", [M, F, Args]),
    Args1 = resolve_args(Args),
    io:format("  resolved ~p:~p(~p)~n", [M, F, Args1]),
    erlang:apply(M, F, Args1);
resolve_arg(Arg) -> Arg.
