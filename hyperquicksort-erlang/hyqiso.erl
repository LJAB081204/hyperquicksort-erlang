-module(hyqiso).
-author('Lewis Ashton-Braun').
-compile(export_all).

%Negative und 0-Dimension abfangen
hyperQuickInit(N) when N=<0 -> io:format("Dimension kann nicht negativ oder 0 sein~n");

%1.1-1.5
hyperQuickInit(N) -> 
P = hoch(N), 	%P = Anzahl der gesamten Knoten -> 1.1	Knotenmenge herausfinden
C = 0,			%C = Counter für Anzahl der erstellten Knoten
Master = spawn(fun() -> master_loop(0,[],0,N,[],0) end), %Master= Masterprozess ->	1.2  Master erstlellen
Cube = hyperQuickInit(P,C,N,[],Master),	%Cube= 2^N viele Prozesse in einer Cubue struktur
CubeM = {Master, Cube},
CubeM.
%A = Tripel mit Adresse d. aktuellen Prozess in allen Formen
hyperQuickInit(P,C,N,[],Master) -> ID = 0, A = create_adr(C,N,Master,ID), hyperQuickInit(P,C+1,N,[A],Master,ID+1).	
hyperQuickInit(P,C,_N,Cube,_Master,_ID) when C == P -> Cube;	%Abbruchbedingung nach Erstellung aller Knoten
hyperQuickInit(P,C,N,Cube,Master,ID) ->	%Erstellung der Knotenadressen
A = create_adr(C,N,Master,ID),
Cuben = konkat(Cube,[A]),	%1.5	Knoten dem Cube hinzufügen
hyperQuickInit(P,C+1,N,Cuben,Master,ID+1).

%-----------------------------------------------------------------------------
%Funktion erstellt verschiedenen Darstellungrn der Adressen			
create_adr(C,N,Master,ID) ->	
BinL = binary_to_list(integer_to_binary(C,2)),		%1.4 BinL = binäre Adresse Adr = Adresse als String
													%			inklusuive der führenden Nullen
Adr = getPad(BinL,N, $0),
Name = list_to_atom(lists:concat(["p",Adr])),
Pid = start(Name,ID,Master,N),						%1.3	Erstellung eines Knotens
{Name,Pid,ID}.


%Funktion welche guckt ob Padding nötig ist (1.5 Hilfsfunktion)
getPad(BinL,N,$0) -> 
Len = N - len(BinL),
case Len =< 0 of
	true -> BinL;
	false -> konkat(makePad(Len, $0),  BinL)
end.

%Erstellen der Adresse mit fürenden Nullen(Padding) (1.5 Hilfsfunktion)
makePad(0,$0)->[];
makePad(N, $0) -> [$0|makePad(N-1, $0)].

%------------------------------------------------------------------------------

hyperQuickStop(Cube) ->
{Master,CubeN} = Cube,	%3.1 Master Adresse erlangen
PidCurrent = self(),
Master ! {terminate_cube,PidCurrent,CubeN},
receive
	{terminated} ->		%3.3 Master terminiert
	io:format("Master terminiert den Cube~n")
end.

%------------------------------------------------------------------------------

%2  Funktion, die die Liste und Cube bekommt und den Sortierprozess in Gang setzt
hyperQuickS(CubeM,List) -> 
{Master, Cube} = CubeM,					 
PidR = self(),
Master ! {zuteilung, List,PidR, Cube},	%2.2 zuteilung der Teillisten

receive
	%Ausgabe der finalen Liste
	
	{finished_final, Global} ->
		io:format("Der Hyperquicksort ist fertig~n"),
		Global
end.

%-----------------------------------------------------------------------------------

%Loop für den Master
master_loop(Finished,Cube,Phase,Dimension,Acc,PidF) -> 
	receive
		%2.1  Zuteilung der Teillisten auf die Hypercube Knoten
		{zuteilung,List,PidFinal,NewCube} ->	
			zuteil(List, NewCube),				%2.1
			master_loop(0,NewCube,0,Dimension,[],PidFinal);
			
		%2.4 Synchronisieren der Knoten (Warten bis alle fertig sortiert haben)	
		{sorted, Name} ->
			[{_NameF,_PidF,_IDF}|_T] = Cube,
			io:format("Prozess ~s sortiert seine Teilliste~n", [Name]),
			FinishedN = Finished +1,		%2.4 Ein weiterer Prozess ist fertig
			P = len(Cube),					%P = Gesamtanzahl an Knoten
			case FinishedN of
			P ->		
				io:format("Alle ~p Prozesse haben fertig sortiert.~n", [P]),
				PhaseN = 0,
				findMulPivots(Cube,PhaseN,Dimension),	%2.5 Befehl, dass Pivots gesucht werden sollen
				master_loop(0,Cube,PhaseN,Dimension,Acc,PidF);	
			%Noch nicht alle habenfertig sortiert
			_->
				master_loop(FinishedN,Cube,Phase,Dimension,Acc,PidF)
			
			end;
			
		%2.7 Master schickt jedem Knoten den passenden Pivot
		{pivot_found, Pivot,ID} ->
			case Pivot of
				%Liste des Knotens war leer
				empty ->
					sendPivot(0,Cube,ID,Phase,Dimension),	%0 als Dummy-Pivot
					master_loop(Finished, Cube,Phase,Dimension,Acc,PidF);
				
				%Pivot wurde gefunden und jetzt an passende Knoten geschickt	
				_ ->
					sendPivot(Pivot,Cube,ID,Phase,Dimension),			
					master_loop(Finished, Cube,Phase,Dimension,Acc,PidF)
			end;
			
		%2.9 %Synchronisation des Teilen der Listen
		{list_split,Name} ->
			io:format("Knoten ~p ist fertig mit splitten.~n", [Name]),
			FinishedN = Finished +1,	%Ein weiterer Knoten ist fertig mit Teilen
			P = len(Cube),
			case FinishedN of 
			P -> 
				io:format("Alle Knoten haben ihre Teillisten anhand des Pivots getrennt.~n"),
				sendSwapCommand(Cube,Cube,Phase),  %Liste der Prozesse 2 mal übergeben. 
													%Ein mal fürs durchiterieren und einmal für das Nachbar finden
				master_loop(0,Cube,Phase,Dimension,Acc,PidF);
			
			_-> 
				master_loop(FinishedN,Cube,Phase,Dimension,Acc,PidF)
			
			end;
		
		%2.11 
		{swap_finished} -> 
			FinishedN = Finished +1,	%Ein Knoten mehr, der fertig ist
			P = len(Cube),				%Gesamtzahl der Knoten
			Limit = Dimension -1,		%Limit schaut ob alle Dimensionen durchlaufen wurden
			
			%2.11 Synchronisation der Knoten für das Mergen ihrer Teillisten
			case FinishedN of
			P ->	
				io:format("Alle ~p Knoten haben fertig getauscht.~n", [P]),
				case Phase of 
				%Alle Dimensionen wurden durchlaufen
				Limit -> 
					sendFinalLists(Cube),	%2.13 finale Liste senden
					master_loop(0,Cube,Phase,Dimension,Acc,PidF);
	
				%Noch nicht alle Dimensionen wurden durchlaufen
				_ ->
					PhaseN = Phase +1,		%Erhöhen der Phase (nächste Dimension betrachten)
					findMulPivots(Cube,PhaseN,Dimension),
					master_loop(0,Cube,PhaseN,Dimension,Acc,PidF)
				end;
				
			_->
				master_loop(FinishedN,Cube,Phase,Dimension,Acc,PidF)
			end;
			
		%2.13 
		{send_final_list, ID, List} ->
			FinishedN = Finished+1, 		%Ein Knoten mehr, der fertig ist
			P = len(Cube),					%Gesamtzahl der Knoten
			NewAcc = [{ID,List}|Acc],		%Akkumulator mit allen Teillisten und jeweilige ID als Tupel
			
			%2.13 Synchronisation der Knoten für das Senden ihrer Teillisten
			case FinishedN of
				%Alle Knoten haben finale Teilliste geschickt
				P ->
					Global = makeFinalList(NewAcc),		%Global ist die finale global sortierte Liste
					PidF ! {finished_final, Global},	%Finale Liste wird an den Prozess
														%gebroadcastet, der den Master erstellt hat
					master_loop(0,Cube,Phase,Dimension,NewAcc,PidF);
				
				%Noch nicht Alle Knoten haben finale Teilliste geschickt				
				_ ->
					master_loop(FinishedN,Cube,Phase,Dimension,NewAcc,PidF)
			end;
			
		{terminate_cube, PidCurrent,CubeN} ->
			terminateWorkers(CubeN, len(CubeN)),	
			master_loop(0, Cube, Phase, Dimension, Acc, PidCurrent);
			 
		

		{worker_stopped,Length} ->
			FinishedN = Finished + 1,
			P = Length,
			case FinishedN of
				P ->
					PidF ! {terminated},
					ok;		% 3.3 Master terminieren
				_ ->
					master_loop(FinishedN, Cube, Phase, Dimension, Acc, PidF)
			end

			
	end.
	
%-----------------------------------------------------------------------------------
	
%Erstellung eines Prozesses vom Cube
start(Name,ID,Master,Dimension)->
spawn(fun() -> loop(Name,ID,Master,[],[],[],Dimension) end).

loop(Name,ID,Master,List,Lower,Upper,Dimension) ->

	receive 
		{zuteilung_Liste, [H|T]} ->
			io:format("~p bekommt seine Teilliste~n", [Name]),
			L = quickS([H|T]), 			%2.3
			Master ! {sorted,Name},		%2.4
			loop(Name,ID,Master,L,[],[],Dimension);
			
			
		{zuteilung_Liste,[]} ->
			io:format("Prozess ~p bekommt eine leere Teilliste~n",[Name]),
			Master ! {sorted,Name},		%2.4
			loop(Name,ID,Master,[],[],[],Dimension);
			
		%2.5 Leader jeder Gruppe sucht seinen Pivot
		{pivot} -> 
			case List of
				[] ->
					Master ! {pivot_found, empty, ID},	%2.6 Broadcast an Master (kein Pivot weil Liste leer)
					loop(Name,ID,Master,List,[],[],Dimension);
				_ ->
					Pivot = findPivot(List),	%2.5 Pivotsuche
					io:format("Prozess ~p wählt ~p als Pivot und sendet es dem Master.~n", [Name,Pivot]),
					Master ! {pivot_found, Pivot, ID},	%2.6 Pivot an Master broadcasten
					loop(Name,ID,Master,List,[],[],Dimension)
			end;
			
		
		%2.8/2.9 Splittet anhand von Pivot, bildet ober und untergruppe Sendet Master zeichen, dass er fertig mit splitten ist
		{pivot_sent, Pivot} ->			
			NewLower = getLower(List,Pivot,[]),		%Untergruppe
			NewUpper = getUpper(List,Pivot,[]),		%Obergruppe
			io:format("Prozess ~p hat den Pivot ~p erhalten und trennt seine Liste~n",[Name,Pivot]),
			Master ! {list_split,Name},				%Master Bescheid geben, dass split fertig ist
			loop(Name,ID,Master,List,NewLower,NewUpper,Dimension);
 
		%2.10  Findet Nachbar, teilt Knoten in Gruppe ein und sendet die andere Hälfte an Nachbar
		{swap_send,L,Phase} ->
			SwapPhase = Dimension -1 - Phase,	%Sorgt dafür dass nach richtigem Bit geswappped wird 
												%-> Sonst wär andersherum
			Bit = 1 bsl SwapPhase,
			Nachbar = ID bxor Bit,				%ID des Nachbarn			
			Group = (ID bsr SwapPhase) band 1,	%Gruppe um zu gucken ob obere oder
												%untere Teilliste geshcikt wird
			{PidN, NameN} = findNeighbour(L,Nachbar),
			
			case Group of
			0 -> %Untere gruppe
				PidN ! {swap_receive, Upper,Phase},
				io:format("Knoten ~p gehört zur unteren Gruppe und schickt Knoten ~p seine obere Teilliste ~n", [Name,NameN]),
				loop(Name,ID,Master,List,Lower,[],Dimension);
			1 -> %Obere Gruppe
				PidN ! {swap_receive, Lower,Phase},
				io:format("Knoten ~p gehört zur oberen Gruppe und schickt Knoten ~p seine untere Teilliste ~n", [Name,NameN]),
				loop(Name,ID,Master,List,[],Upper,Dimension)
			end;
			
		%2.11 Teilliste wird Empfangen und jetzt mit Komplement gemerged
		{swap_receive,ListS,Phase} ->
			SwapPhase = Dimension - 1 - Phase,
			Group = (ID bsr SwapPhase) band 1,

			case Group of
			0 -> 
				NewList = merge(Lower,ListS),		%2.11 mergen der Teillisten
				io:format("Knoten ~p hat seine Liste erhalten und konkateniert und merged sie ~n",[Name]),
				Master ! {swap_finished},
				loop(Name,ID,Master,NewList,[],[],Dimension);
			
			1 -> 
				NewList = merge(Upper,ListS),		%2.11 mergen
				io:format("Knoten ~p hat seine Liste erhalten und konkateniert und merged sie ~n",[Name]),
				Master ! {swap_finished},		%Mitteilung an Master dass mergen fertig ist
				loop(Name,ID,Master,NewList,[],[],Dimension)
			end;
			
		%2.13 aktueller Knoten sendet Master seine finale Teilliste, und die ID, damit Master gesamtliste sortieren kann 
		{final_list} -> 
			Master ! {send_final_list, ID,List},
			loop(Name,ID,Master,[],[],[],Dimension)	;
			
		{stop,Name,Length} ->
			io:format("Prozess ~p wurde gestoppt~n",[Name]),
			Master ! {worker_stopped,Length},	%3.2 	Knoten terminieren
			ok								
	end.

%-------------------------------------------------------------------------------------------------


%Errechnen der Länge jeder Teilliste, Knotenanzahl, etc. 
zuteil(_List,[]) -> ok;
zuteil(List,[{Name,Pid,ID}|T]) ->
Length = len(List),					%Length = Länge der Liste
Amount = len([{Name,Pid,ID}|T]),	%Amount = Anzahl Knoten
Count = Length div Amount,			%Count = Größe jeder Teilliste
Rem = Length rem Amount,
zuteil(List,[{Name,Pid,ID}|T], Count, Amount, Rem).

zuteil(_List,[], _Count, 0, _Rem) -> ok;

%2.2  zuteil teilt die Teillisten auf die Knoten auf
zuteil(List,[{_Name,Pid,_ID}|T], Count, Amount,Rem) ->
%Errechnung ob aktueller Knoten ein Element mehr bekommt oder nicht
case Rem of
	0 ->
	Teil = extract(Count,List),
	Rest = newList(Count,List),
	Pid ! {zuteilung_Liste, Teil},
	zuteil(Rest, T, Count, Amount-1,Rem);
	_ ->
	
	Teil = extract(Count+1,List),
	Rest = newList(Count+1,List),
	Pid ! {zuteilung_Liste, Teil},
	zuteil(Rest, T, Count, Amount-1,Rem-1)	
end.




%Eigene Funktion für Dimensionberechnug(Anfangs gedacht 2^N würde gehen)
hoch(0) -> 1;
hoch(N) -> 2* hoch(N-1).

%Eigene Funktion für Länge zählen erstellen
len([]) -> 0;
len([_H|T]) -> 1+ len(T).

%Gibt die neue Liste ohne den ersten Teil der alten Liste wieder - also der Teil, der dem Prozess bereits zugewiesen wurde
newList(0,List) -> List;
newList(_Size,[]) -> [];
newList(Size,[_H|T]) -> newList(Size-1,T). 

%Gibt immer die nächste Teilliste wieder
extract(0,_List) -> [];
extract(_Size,[]) -> [];
extract(Size,[H|T]) -> [H|extract(Size-1,T)].

%2.8/2.9 Liste kleiner als Pivot
getLower(List, Pivot) ->
getLower(List, Pivot, []).

getLower([], _Pivot, Acc) ->
reverse(Acc);

getLower([H|T], Pivot, Acc) when H < Pivot ->
getLower(T, Pivot, [H|Acc]);

getLower([_H|T], Pivot, Acc) ->
getLower(T, Pivot, Acc).




%2.8/2.9 Liste größer als Pivot
getUpper(List, Pivot) ->
getUpper(List, Pivot, []).

getUpper([], _Pivot, Acc) ->
reverse(Acc);

getUpper([H|T], Pivot, Acc) when H >= Pivot ->
getUpper(T, Pivot, [H|Acc]);

getUpper([_H|T], Pivot, Acc) ->
getUpper(T, Pivot, Acc).



reverse(L) -> reverse(L,[]).

reverse([], Acc) -> Acc;
reverse([H|T],Acc) -> reverse(T,[H|Acc]).

%Stoppt alle workerprozesse
terminateWorkers([],_Length) -> ok;
terminateWorkers([{Name,Pid,_ID}|T], Length) ->
Pid ! {stop,Name,Length},	%3.2	Knoten terminieren
terminateWorkers(T,Length).



%Funktion zum konkatenieren zweier Listen
konkat([],B) -> B;
konkat([H|T], B) -> [H|konkat(T,B)].


%2.11 Merged die empfangende und behaltene Liste eines Prozesses, sodass allle Elemente intern sortiert sind
merge([],B) -> B ;
merge(A,[]) -> A;

merge([HA|TA],[HB|TB]) when HA =< HB ->
[HA|merge(TA,[HB|TB])];

merge([HA|TA], [HB|TB]) ->
[HB|merge([HA|TA],TB)].


% 2.5  Funktion zum finden des Median Pivots(Hier mittlere Wert der Liste, da Liste bereits sortiert ist
findPivot([H|T]) -> Length = len([H|T]), 
PivC = Length div 2, Count = 0,
findPivot([H|T],PivC, Count).

findPivot([H|_T], PivC, Count) when PivC == Count -> H;
findPivot([_H|T],PivC, Count) -> findPivot(T,PivC, Count+1);
findPivot([],_PivC, _Count) ->[].



%2.5 Sucht jeden Anführer der Gruppen und Adressiert die jewieligen Prozesse dass sie den Pivot raussuchen sollen
findMulPivots([],_Phase,_Dimension) -> ok;
findMulPivots([{_Name,Pid,ID} | T], Phase, Dimension) ->
case isLeader(ID, Phase,Dimension) of
    true ->
		Pid ! {pivot},		%2.5 Pivotsuche jeder Gruppe
		findMulPivots(T, Phase,Dimension);
    false ->
		findMulPivots(T, Phase,Dimension)
end.


%2.5 Knoten ist Leader wenn er die kleinste ID seiner Gruppe besitzt
isLeader(ID,Phase,Dimension) -> 
Mask = (1 bsl (Dimension-Phase)) -1,
case (ID band Mask) == 0 of
	true -> true;
	false -> false
end.


%2.7  Sendet den Pivot an alle Knoten der selben Gruppe
sendPivot(Pivot, [{_NameF,PidF,IDF}|T], ID, Phase, Dimension) ->
    Mask = (1 bsl (Dimension - Phase)) -1,	%Bitmaske für Gruppenbestimmung
	GroupID = ID band bnot Mask,	%Gruppe zu der ID gehört durch löschen der unteren
									%Bits mit invertieren der Maske und verunden der ID
	GroupIDF = IDF band bnot Mask,	%Gruppe zu der IDF gehört durch löschen der unteren 
									%Bits mit invertieren der Maske und verunden der IDF
    case GroupID == GroupIDF of
        true ->
            PidF ! {pivot_sent, Pivot},
            sendPivot(Pivot, T, ID, Phase, Dimension);
        false ->
            sendPivot(Pivot, T, ID, Phase, Dimension)
    end;
sendPivot(_Pivot, [], _LeaderID, _Phase, _Dimension) ->
    ok.




%2.10 Gibt allen Knoten Bescheid dass sie swappen sollen 
sendSwapCommand([{_NameF,PidF,_IDF}|T],L,Phase) ->
[{Name,Pid,ID}|Tl] = L,
PidF ! {swap_send,[{Name,Pid,ID}|Tl],Phase},
sendSwapCommand(T,[{Name,Pid,ID}|Tl],Phase);

sendSwapCommand([],_L,_Phase) -> ok.

%2.13  Master sendet allen Workern befehl dass sie ihre finale liste schicken
sendFinalLists([]) -> ok;
sendFinalLists([{_Name,Pid,_ID} | T]) ->
    Pid ! {final_list},
    sendFinalLists(T).
   

%2.13 Finale Liste wird hier zusammengestellt
makeFinalList(Acc) -> 	
Sorted = sortPairs(Acc),
remID(Sorted).

%2.13 Hilfsfunktion die die Teillisten nach der ID aufsteigend sortiert
sortPairs([]) -> [];
sortPairs([H|T]) -> 
insertPair(H,sortPairs(T)).

%2.13 Fügt Teilliste an richtige Stelle für die finale Liste ein
insertPair({ID,L},[]) -> [{ID,L}];
insertPair({ID,L}, [{ID2,L2} | T]) when ID < ID2 ->
[{ID,L}, {ID2,L2} | T];

insertPair({ID,L}, [H|T]) ->
[H | insertPair({ID,L}, T)].


%2.13 Entfernt die ID damit finale Liste nur noch aus Zahlen besteht
remID([]) -> [];
remID([{_ID,List}|T]) ->
konkat(List, remID(T)).

%2.10 Findet den Nachbarn vom übergebenen Prozess
findNeighbour([{NameF,PidF,IDF}|_T], Nachbar) when IDF == Nachbar -> {PidF, NameF};
findNeighbour([{_NameF,_PidF,_IDF}|T], Nachbar) -> findNeighbour(T, Nachbar);
findNeighbour([],_Nachbar) -> [].


% 2.3 implementierung von Quicksort
quickS([]) -> [];
quickS([Piv|Rest]) ->
{S,B} = partition(Rest, Piv, [], []),		%Partitionierung in Listen > und <= Pivot
konkat(quickS(S),konkat([Piv],quickS(B))).	%Konkatenieren der Listen

partition([],_Piv,S,B) ->
{S,B};
partition([H|T], Piv, S, B) when H =< Piv ->	%wenn Element =< Pivot dann kommt Element in S
partition(T, Piv, [H|S], B);					%Weiter mit Tail
partition([H|T], Piv, S, B) when H > Piv ->		%wenn Element > Pivot, dann kommt Element in B
partition(T, Piv, S, [H|B]).					%Weiter mit Tail

