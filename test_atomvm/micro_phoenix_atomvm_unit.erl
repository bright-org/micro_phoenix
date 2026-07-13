-module(micro_phoenix_atomvm_unit).

-export([
    start/0,
    request_parse_query_test/0,
    template_atom_assign_test/0,
    template_binary_assign_test/0,
    template_iolist_assign_test/0,
    template_non_binary_assign_test/0
]).

start() ->
    case eunit:test(?MODULE, [exact_execution]) of
        ok ->
            erlang:display({micro_phoenix_atomvm_unit, ok}),
            ok;
        Error ->
            erlang:error({micro_phoenix_atomvm_unit_failed, Error})
    end.

request_parse_query_test() ->
    Request =
        'Elixir.MicroPhoenix.Request':parse(
            <<"GET /index2.html?debug=1 HTTP/1.1\r\n"
              "Host: 192.168.1.200:5000\r\n"
              "\r\n">>
        ),
    assert_equal(request_method, get, maps:get(method, Request)),
    assert_equal(request_path, <<"/index2.html">>, maps:get(path, Request)).

template_atom_assign_test() ->
    assert_template(
        atom_assign,
        <<"Hello <%= @name %>">>,
        #{name => <<"AtomVM">>},
        <<"Hello AtomVM">>
    ).

template_binary_assign_test() ->
    assert_template(
        binary_assign,
        <<"Hello <%= @name %>">>,
        #{<<"name">> => <<"AtomVM">>},
        <<"Hello AtomVM">>
    ).

template_iolist_assign_test() ->
    assert_template(
        iolist_assign,
        <<"Items: <%= @items %>">>,
        #{items => [<<"A">>, <<",">>, <<"B">>]},
        <<"Items: A,B">>
    ).

template_non_binary_assign_test() ->
    assert_template(
        non_binary_assign,
        <<"Number: <%= @number %>">>,
        #{number => 123},
        <<"Number: ">>
    ).

assert_template(Label, Template, Assigns, ExpectedBody) ->
    Expected = {ok, 200, <<"text/html">>, ExpectedBody},
    Actual = 'Elixir.Template':render(nil, Template, Assigns),
    assert_equal(Label, Expected, Actual).

assert_equal(_Label, Expected, Expected) ->
    ok;
assert_equal(Label, Expected, Actual) ->
    erlang:error({assert_equal_failed, Label, {expected, Expected}, {actual, Actual}}).
