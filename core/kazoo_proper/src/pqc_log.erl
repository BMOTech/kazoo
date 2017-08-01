-module(pqc_log).

-export([log_info/0]).

-spec log_info() -> [{atom(), iolist()}].
log_info() ->
    [{'elapsed', kz_term:to_list(kz_time:elapsed_ms(get('now')))}].
