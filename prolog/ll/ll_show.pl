:- module(
  ll_show,
  [
    export_uri/1, % +Uri
    show_uri/1    % +Uri
  ]
).

/** <module> LOD Laundromat: Show

@author Wouter Beek
@version 2017/09
*/

:- use_module(library(aggregate)).
:- use_module(library(apply)).
:- use_module(library(atom_ext)).
:- use_module(library(date_time)).
:- use_module(library(dcg/dcg_ext)).
:- use_module(library(debug_ext)).
:- use_module(library(dict_ext)).
:- use_module(library(graph/dot)).
:- use_module(library(http/http_generic)).
:- use_module(library(lists)).
:- use_module(library(ll/ll_generics)).
:- use_module(library(ll/ll_seedlist)).
:- use_module(library(stream_ext)).
:- use_module(library(yall)).

:- debug(dot).





%! export_uri(+Uri:atom) is det.
%! export_uri(+Uri:atom, +Format:atom) is det.
%
% Exports the LOD Laundromat job for the given URI to a PDF file, or
% to a file in some other Format.

export_uri(Uri) :-
  export_uri(Uri, pdf).


export_uri(Uri, Format) :-
  uri_hash(Uri, Hash),
  file_name_extension(Hash, Format, File),
  setup_call_cleanup(
    graphviz(dot, ProcIn, Format, ProcOut),
    seed2dot(ProcIn, Hash),
    close(ProcIn)
  ),
  setup_call_cleanup(
    open(File, write, Out),
    copy_stream_type(ProcOut, Out),
    close(Out)
  ).



%! show_uri(+Uri:atom) is det.
%! show_uri(+Uri:atom, +Program:atom) is det.
%
% Shows the LOD Laundromat job for the given URI in X11, or in some
% other Program.

show_uri(Uri) :-
  show_uri(Uri, x11).


show_uri(Uri, Program) :-
  uri_hash(Uri, Hash),
  setup_call_cleanup(
    graphviz(dot, ProcIn, Program),
    seed2dot(ProcIn, Hash),
    close(ProcIn)
  ).





% GENERICS %

seed2dot(Out, Hash) :-
  format_debug(dot, Out, "digraph g {"),
  seed2dot_hash_id(Out, Hash, _),
  format_debug(dot, Out, "}").

seed2dot_hash_id(Out, Hash, Id) :-
  atomic_concat(n, Hash, Id),
  seed(Hash, Dict),
  dict_pairs(Dict, Pairs),
  seed2dot_id_pairs(Out, Id, Pairs).

seed2dot_id_pairs(Out, Id, Pairs1) :-
  maplist(writeln, Pairs1),
  seed2dot_header(Pairs1, Header, Pairs2),
  seed2dot_edges(Out, Id, Pairs2, Pairs3),
  aggregate_all(
    set(Attr),
    (
      member(Name-Value, Pairs3),
      seed2dot_attr(Name, Value, Attr)
    ),
    Attrs
  ),
  atomics_to_string([Header|Attrs], "<BR/>", Label),
  dot_node(Out, Id, [label(Label),shape(box)]).

% archive record
seed2dot_header(Pairs1, Header, Pairs2) :-
  selectchk(name-Entry, Pairs1, Pairs2), !,
  format(string(Header), "<B>Archive entry: ~a</B>", [Entry]).
% HTTP record
seed2dot_header(Pairs1, Header, Pairs3) :-
  selectchk(version-Version, Pairs1, Pairs2), !,
  selectchk(status-Status, Pairs2, Pairs3),
  _{major: Major, minor: Minor} :< Version,
  http_status_reason(Status, Reason),
  format(
    string(Header0),
    "HTTP/~d.~d status: ~d (~s)",
    [Major,Minor,Status,Reason]
  ),
  format(string(Header), "<B>~s</B>", [Header0]).
% seed record
seed2dot_header(Pairs1, Header, Pairs2) :-
  selectchk(uri-Uri, Pairs1, Pairs2), !,
  format(string(Header), "<B>~a</B>", [Uri]).
% other records
seed2dot_header(Pairs1, Header, Pairs2) :-
  selectchk(status-Status, Pairs1, Pairs2),
  format(string(Header), "<B>~a</B>", [Status]).

seed2dot_edges(Out, Id, Pairs1, Pairs2) :-
  seed2dot_edges(Out, Id, Pairs1, [], Pairs2).

seed2dot_edges(_, _, [], Pairs3, Pairs3) :- !.
seed2dot_edges(Out, Id, [Name-Value|Pairs1], Pairs2, Pairs3) :-
  seed2dot_edge(Out, Id, Name, Value), !,
  seed2dot_edges(Out, Id, Pairs1, Pairs2, Pairs3).
seed2dot_edges(Out, Id, [Pair|Pairs1], Pairs2, Pairs3) :-
  seed2dot_edges(Out, Id, Pairs1, [Pair|Pairs2], Pairs3).

% added, processed
seed2dot_attr(Name, Added, Attr) :-
  memberchk(Name, [added,processed]), !,
  dt_label(Added, Label),
  atom_capitalize(Name, CName),
  format(string(Attr), "~a: ~s", [CName,Label]).
% content
seed2dot_attr(content, Value1, Attr) :-
  dict_pairs(Value1, Pairs),
  member(Name2-Value2, Pairs),
  seed2dot_attr(Name2, Value2, Attr).
% filetype
seed2dot_attr(filetype, Filetype, Attr) :-
  format(string(Attr), "File type: ~a", [Filetype]).
% filters
seed2dot_attr(filters, Filters, Attr) :-
  atomics_to_string(Filters, ", ", String),
  format(string(Attr), "Filters: ~s", [String]).
% format
seed2dot_attr(format, Format, Attr) :-
  (   rdf_format(Format, Super, Sub)
  ->  format(string(Attr), "Serialization format: ~a/~a", [Super,Sub])
  ;   format(string(Attr), "Compression format: ~a", [Format])
  ).
% headers
seed2dot_attr(headers, Headers, Attr) :-
  dict_pairs(Headers, Pairs),
  member(Name-Values, Pairs),
  member(Value, Values),
  http_header_name_label(Name, NameLabel),
  format(string(Attr), "~s: ~w", [NameLabel,Value]).
% interval, mtime
seed2dot_attr(Name, Interval, Attr) :-
  memberchk(Name, [interval,mtime]), !,
  atom_capitalize(Name, CName),
  format(string(Attr), "~a: ~f", [CName,Interval]).
% newline
seed2dot_attr(newline, Atom, Attr) :-
  format(string(Attr), "Newline: ~a", [Atom]).
% number of bytes
seed2dot_attr(number_of_bytes, N, Attr) :-
  format(string(Attr), "Number of bytes: ~D", [N]).
% number of characters
seed2dot_attr(number_of_characters, N, Attr) :-
  format(string(Attr), "Number of characters: ~D", [N]).
% number of lines
seed2dot_attr(number_of_lines, N, Attr) :-
  format(string(Attr), "Number of lines: ~D", [N]).
% permissions
seed2dot_attr(permissions, Permission, Attr) :-
  format(string(Attr), "Archive permissions: ~d", [Permission]).
% relative
seed2dot_attr(relative, Bool, Attr) :-
  bool_string(Bool, String),
  format(string(Attr), "Relative URI: ~s", [String]).
% size
seed2dot_attr(size, Size, Attr) :-
  format(string(Attr), "Archive size: ~D", [Size]).
% timestamp
seed2dot_attr(timestamp, Begin-End, Attr) :-
  Duration is End - Begin,
  format(string(Attr), "Duration: ~f seconds", [Duration]).
% uri
seed2dot_attr(uri, Uri, Attr) :-
  format(string(Attr), "URI: ~a", [Uri]).
% walltime
seed2dot_attr(walltime, Walltime, Attr) :-
  format(string(Attr), "Walltime: ~d mili-seconds", [Walltime]).

% archive
seed2dot_edge(Out, Id1, archive, Dicts1) :-
  append(Dicts2, [_], Dicts1),
  Dicts2 \== [],
  maplist(dot_id, Dicts2, Id2s),
  maplist(dict_pairs, Dicts2, Pairss),
  maplist(seed2dot_id_pairs(Out), Id2s, Pairss),
  dot_linked_list(Out, Id2s, FirstId2-_LastId2),
  dot_edge(Out, Id1, FirstId2, [label("archive")]).
% http: A linked list / sequence of nodes.
seed2dot_edge(Out, Id1, http, Dicts) :-
  maplist(dot_id, Dicts, Id2s),
  maplist(dict_pairs, Dicts, Pairss),
  maplist(seed2dot_id_pairs(Out), Id2s, Pairss),
  dot_linked_list(Out, Id2s, FirstId2-_LastId2),
  dot_edge(Out, Id1, FirstId2, [label("HTTP")]).
% children: Multiple links to other nodes
seed2dot_edge(Out, Id1, children, Hashes) :-
  maplist(seed2dot_hash_id(Out), Hashes, Id2s),
  maplist(
    {Out,Id1}/[Id2]>>dot_edge(Out, Id1, Id2, [label("has child")]),
    Id2s
  ).
% dirty, parent: A single link to another node.
seed2dot_edge(_Out, _Id1, Name, _Hash) :-
  memberchk(Name, [dirty,parent]).
  %atomic_concat(n, Hash, Id2),
  %dot_edge(Out, Id1, Id2, [label(Name)]).

dot_linked_list(Out, [FirstId|Ids], FirstId-LastId) :-
  dot_linked_list_(Out, [FirstId|Ids], LastId).

dot_linked_list_(_, [LastId], LastId) :- !.
dot_linked_list_(Out, [Id1,Id2|T], LastId) :-
  dot_edge(Out, Id1, Id2),
  dot_linked_list_(Out, [Id2|T], LastId).

bool_string(false, "❌").
bool_string(true, "✓").

rdf_format(jsonld, application, 'json-ld').
rdf_format(nquads, application, 'n-quads').
rdf_format(ntriples, application, 'n-triples').
rdf_format(rdfa, application, 'xhtml+xml').
rdf_format(rdfxml, application, 'rdf+xml').
rdf_format(trig, application, trig).
rdf_format(turtle, text, turtle).
