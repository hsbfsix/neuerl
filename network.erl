-module(network).
-compile(export_all).

linear_threshold(Threshold, Input) ->
	if
		Input =< Threshold ->
			0.0;
		true ->
			1.0
	end.

file2lines(File) ->
	{ok, Bin} = file:read_file(File),
	string2lines(binary_to_list(Bin), []).

string2lines("\n" ++ Str, Acc) -> [lists:reverse([$\n | Acc]) | string2lines(Str, [])];
string2lines([H|T], Acc) -> string2lines(T, [H|Acc]);
string2lines([], Acc) -> [lists:reverse(Acc)].

node(InputNodesList, ThresholdFunction, OutputNodesList, ActivationNumber, ActivationLevel) ->
	if 
		(ActivationNumber =:= length(InputNodesList)) and (ActivationNumber > 0) -> 
			Output = ThresholdFunction(ActivationLevel),
			[P ! {signal, Output * W} || {P, W} <- OutputNodesList],
			node(InputNodesList, ThresholdFunction, OutputNodesList, 0, 0.0);

		true ->	
			receive
				{add_input, Pid} -> node([Pid | InputNodesList], ThresholdFunction, OutputNodesList, 0, 0.0);
				{add_output, Pid, Weight} -> node(InputNodesList, ThresholdFunction, [{Pid, Weight} | OutputNodesList], 0, 0.0);
				{signal, SignalValue} -> node(InputNodesList, ThresholdFunction, OutputNodesList, ActivationNumber + 1, ActivationLevel + SignalValue);
				_ -> exit(self(), kill)
			end
	end.

cnth(Idx, List) -> lists:nth(Idx + 1, List).

to_int(String) -> 
	{S, _} = string:to_integer(String),
	S.

to_float(String) -> 
	{S, _} = string:to_float(String),
	S.

process_line(InputPid, OutputPid, NodeList, Line) ->
	SourcePidStr = cnth(0, Line),
	DestPidStr = cnth(1, Line),
	WeightStr = cnth(2, Line),
	Weight = to_float(WeightStr),

	if
		SourcePidStr =:= "I" ->
			DestPid = cnth(to_int(DestPidStr), NodeList),
			InputPid ! {add_output, DestPid, Weight},
			DestPid ! {add_input, InputPid},
			{input_destination, to_int(DestPidStr), DestPid};

		DestPidStr =:= "O" ->
			SourcePid = cnth(to_int(SourcePidStr), NodeList),
			SourcePid ! {add_output, OutputPid, Weight},
			OutputPid ! {add_input, SourcePid},
			{output_source, to_int(SourcePidStr), SourcePid};

		true ->
			SourcePid = cnth(to_int(SourcePidStr), NodeList),
			DestPid = cnth(to_int(DestPidStr), NodeList),
			SourcePid ! {add_output, DestPid, Weight},
			DestPid ! {add_input, SourcePid},
			[]
	end.

make_network(InputPid, OutputPid, NetFilename, ThresholdFunction) ->
	FileLines = file2lines(NetFilename),
	[Header | DefinitionLines] = lists:map(fun(X) -> string:tokens(X, " \r\t\n") end, FileLines),
	{NumNodes, _} = string:to_integer(cnth(0, Header)),
	NodeList = [spawn(?MODULE, node, [[], ThresholdFunction, [], 0, 0.0]) || _ <- lists:seq(1, NumNodes)],
	ConnectionList = [process_line(InputPid, OutputPid, NodeList, Line) || Line <- DefinitionLines],
	ConnectionList.

get_input_list(List) -> get_input_list(List, []).
get_input_list([], Acc) -> Acc;
get_input_list([H|T], Acc) -> 
	case H of
		{input_destination, DestInt, DestPid} -> get_input_list(T, [{DestInt, DestPid} | Acc]);
		_ -> get_input_list(T, Acc)
	end. 

get_output_list(List) -> get_output_list(List, []).
get_output_list([], Acc) -> Acc;
get_output_list([H|T], Acc) -> 
	case H of
		{output_source, SourceInt, SourcePid} -> get_output_list(T, [{SourceInt, SourcePid} | Acc]);
		_ -> get_output_list(T, Acc)
	end. 

classify_lists(List) -> classify_lists(List, [], []).
classify_lists([], AccI, AccO) -> {AccI, AccO};
classify_lists([H|T], AccI, AccO) -> 
	case H of
		{input_destination, DestInt, DestPid} -> classify_lists(T, [{DestInt, DestPid} | AccI], AccO);
		{output_source, SourceInt, SourcePid} -> classify_lists(T, AccI, [{SourceInt, SourcePid} | AccO]);
		_ -> classify_lists(T, AccI, AccO)
	end. 

gen_network(InputPid, OutputPid, NetFilename, ThresholdFunction) ->
	classify_lists(make_network(InputPid, OutputPid, NetFilename, ThresholdFunction)).

