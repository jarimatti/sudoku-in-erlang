-module(sudoku).
-import(lists, [member/2, filter/2, map/2, flatmap/2, sort/1, all/2]).
-compile(export_all).

print_results(Filename, Seperator) ->
    Solutions = solve_file(Filename, Seperator),
    Msg = "Solved ~p of ~p puzzles from ~s in ~f secs
\t(avg ~f sec (~f Hz) max ~f secs, min ~f secs, ~p eliminations)~n",
    io:format(Msg, time_stats(Solutions, Filename)).

time_stats(Solutions, Filename) ->
    Solved = filter(fun({_, Tuple}) -> is_solved(Tuple) end, Solutions),
    NumberPuzzles = length(Solutions),
    Times = [Time|| {Time, _} <- Solutions],
    Eliminations = [E|| {_, {_, E}} <- Solutions],
    Max = lists:max(Times)/1000000,
    Min = lists:min(Times)/1000000,
    TotalTime = lists:sum(Times)/1000000,
    Avg = TotalTime/NumberPuzzles,
    Hz = NumberPuzzles/TotalTime,
    [length(Solved), NumberPuzzles, Filename,
     TotalTime, Avg, Hz, Max, Min, lists:sum(Eliminations)].

solve_file(Filename, Seperator) ->
    Solutions = solve_all(from_file(Filename, Seperator)),
    OutFilename = [filename:basename(Filename, ".txt")|".out"],
    ok = to_file(OutFilename, Solutions),
    Solutions.

solve_all(GridList) ->
    map(fun time_solve/1, GridList).

from_file(Filename, Seperator) ->
    {ok, BinData} = file:read_file(Filename),
    string:tokens(binary_to_list(BinData), Seperator).

to_file(Filename, Solutions) ->
    GridStrings = map(fun({_, S}) -> [to_string(S)|"\n"] end, Solutions),
    ok = file:write_file(Filename, list_to_binary(GridStrings)).

is_solved({ValuesDict, _}) ->
    all(fun(Unit) -> is_unit_solved(ValuesDict, Unit) end, unitlist()).
is_unit_solved(ValuesDict, Unit) ->
    UnitValues = flatmap(fun(S) -> dict:fetch(S, ValuesDict) end, Unit),
    (length(UnitValues) == 9) and (sets:from_list(UnitValues) == sets:from_list(digits())).

time_solve(GridString) ->
    timer:tc(sudoku, solve, [GridString]).

solve(GridString) ->
    search(parse_grid(GridString)).

search(false) ->
    false;
search(ValuesTuple) ->
    search(ValuesTuple, is_solved(ValuesTuple)).
search(ValuesTuple, true) ->
    %% Searching an already solved puzzle should just return it unharmed.
    ValuesTuple;
search(ValuesTuple, false) ->
    {Square, Values} = least_valued_unassigned_square(ValuesTuple),
    first_valid_result(ValuesTuple, Square, Values).

assign(Puzzle, Square, Digit) ->
    %% Assign by eliminating all values except the assigned value.
    {ValuesDict, _} = Puzzle,
    OtherValues = exclude_from(dict:fetch(Square, ValuesDict), [Digit]),
    eliminate(Puzzle, [Square], OtherValues).

eliminate(false, _, _) ->
    false;
eliminate(Puzzle, [], _) ->
    Puzzle;
eliminate(Puzzle, [Square|T], Digits) ->
    %% Eliminate the specified Digits from all specified Squares.
    {ValuesDict, _} = Puzzle,
    OldValues = dict:fetch(Square, ValuesDict),
    NewValues = exclude_from(OldValues, Digits),
    NewPuzzle = eliminate(Puzzle, Square, Digits, NewValues, OldValues),
    eliminate(NewPuzzle, T, Digits).

eliminate(_, _, _, [], _) ->
    %% Contradiction: removed last value
    false;
eliminate(Puzzle, _, _, Vs, Vs) ->
    %% NewValues and OldValues are the same, already eliminated.
    Puzzle;
eliminate({ValuesDict, Eliminations}, Square, Digits, NewValues, _) ->
    NewDict = dict:store(Square, NewValues, ValuesDict),
    NewPuzzle = peer_eliminate({NewDict, Eliminations}, Square, NewValues),

    %% Digits have been eliminated from this Square.
    %% Now see if the elimination has created a unique place for a digit
    %% to live in the surrounding units of this Square.
    assign_unique_place(NewPuzzle, units(Square), Digits).

peer_eliminate(Puzzle, Square, [AssignedValue]) ->
    %% If there is only one value left, we can also
    %% eliminate that value from the peers of Square
    eliminate(Puzzle, peers(Square), [AssignedValue]);
peer_eliminate(Puzzle, _, _) ->
    %% Multiple values, cannot eliminate from peers.
    Puzzle.

assign_unique_place(false, _, _) ->
    false;
assign_unique_place(Puzzle, [], _) ->
    Puzzle;
assign_unique_place(Puzzle, [Unit|T], Digits) ->
    %% If a certain digit can only be in one place in a unit,
    %% assign it.
    NewPuzzle = assign_unique_place_for_unit(Puzzle, Unit, Digits),
    assign_unique_place(NewPuzzle, T, Digits).

assign_unique_place_for_unit(false, _, _) ->
    false;
assign_unique_place_for_unit(Puzzle, _, []) ->
    Puzzle;
assign_unique_place_for_unit(Puzzle, Unit, [Digit|T]) ->
    {ValuesDict, _} = Puzzle,
    Places = places_for_value(ValuesDict, Unit, Digit),
    NewPuzzle = assign_unique_place_for_digit(Puzzle, Places, Digit),
    assign_unique_place_for_unit(NewPuzzle, Unit, T).

assign_unique_place_for_digit(_, [], _) ->
    %% Contradiction: no place for Digit found
    false;
assign_unique_place_for_digit(Puzzle, [Square], Digit) ->
    %% Unique place for Digit found, assign
    assign(Puzzle, Square, Digit);
assign_unique_place_for_digit(Puzzle, _, _) ->
    %% Mutlitple palces (or none) found for Digit
    Puzzle.

places_for_value(ValuesDict, Unit, Digit) ->
    [Square||Square <- Unit, member(Digit, dict:fetch(Square, ValuesDict))].

least_valued_unassigned_square({ValuesDict, _}) ->
    Lengths = map(fun({S, Values}) -> {length(Values), S, Values} end,
                  dict:to_list(ValuesDict)),
    Unassigned = filter(fun({Length, _, _}) -> Length > 1 end, Lengths),
    {_, Square, Values} = lists:min(Unassigned),
    {Square, Values}.

to_string(Puzzle) ->
    {ValuesDict, _} = Puzzle,
    Fun = fun({_, [V]}) -> [V];
             ({_, _}) -> "."
          end,
    flatmap(Fun, sort(dict:to_list(ValuesDict))).

parse_grid(GridString) ->
    CleanGrid = clean_grid(GridString),
    81 = length(CleanGrid),
    parse_puzzle({empty_dict(), 0}, squares(), CleanGrid).

clean_grid(GridString) ->
    %% Return a string with only digits, 0 and .
    ValidChars = digits() ++ "0.",
    filter(fun(E) -> member(E, ValidChars) end, GridString).

parse_puzzle(Puzzle, [], []) ->
    Puzzle;
parse_puzzle(Puzzle, [Square|Squares], [Value|GridString]) ->
    {_,_} = Puzzle,
    IsDigit = member(Value, digits()),
    NewPuzzle = assign_if_digit(Puzzle, Square, Value, IsDigit),
    {_,_} = NewPuzzle,
    parse_puzzle(NewPuzzle, Squares, GridString).

assign_if_digit(Puzzle, Square, Value, true) ->
    %% Value is a Digit, possible to assign
    assign(Puzzle, Square, Value);
assign_if_digit(Puzzle, _, _, false) ->
    %% Not possible to assign
    Puzzle.

empty_dict() ->
    Digits = digits(),
    dict:from_list([{Square, Digits} || Square <- squares()]).

cross(SeqA, SeqB) ->
    %% Cross product of elements in SeqA and elements in SeqB.
    [[X,Y] || X <- SeqA, Y <- SeqB].

digits() ->
    "123456789".
rows() ->
    "ABCDEFGHI".
cols() ->
    digits().

squares() ->
    %% Returns a list of 81 square names, including "A1" etc.
    cross(rows(), cols()).

col_squares() ->
    %% All the square names for each column.
    [cross(rows(), [C]) || C <- cols()].
row_squares() ->
    %% All the square names for each row.
    [cross([R], cols()) || R <- rows()].
box_squares() ->
    %% All the square names for each box.
    [cross(Rows, Cols) || Rows <- ["ABC", "DEF", "GHI"],
                          Cols <- ["123", "456", "789"]].

unitlist() ->
    %% A list of all units (columns, rows, boxes) in a grid.
    col_squares() ++ row_squares() ++ box_squares().

units(Square) ->
    %% A list of units for a specific square
    [S || S <- unitlist(), member(Square, S)].

peers(Square) ->
    %% A unique list of squares (excluding this one)
    %% that are also part of the units for this square.
    NonUniquePeers = shallow_flatten([S || S <- units(Square)]),
    PeerSet = sets:from_list(NonUniquePeers),
    PeersWithSelf = sets:to_list(PeerSet),
    lists:delete(Square, PeersWithSelf).

shallow_flatten([]) -> [];
shallow_flatten([H|T]) ->
    H ++ shallow_flatten(T).

exclude_from(Values, Exluders) ->
    filter(fun(E) -> not member(E, Exluders) end, Values).

%% Returns the first non-false puzzle, otherwise false
first_valid_result(_, _, []) ->
    false;
first_valid_result(Puzzle, Square, [Digit|T]) ->
    PuzzleOrFalse = search(assign(Puzzle, Square, Digit)),
    first_valid_result(Puzzle, Square, [Digit|T], PuzzleOrFalse).
first_valid_result(Puzzle, Square, [_|T], false) ->
    first_valid_result(Puzzle, Square, T);
first_valid_result(_, _, _, Puzzle) ->
    Puzzle.
