:- module(
  wm,
  [
    add_wm/0,
    add_wms/1,       % +N
    current_wm/1,    % ?Alias
    current_wm/2,    % ?Alias, ?Hash
    number_of_wms/1, % -N
    reset/0,
    single_wm/0
  ]
).

/* <module> LOD Laundromat washing machine

@author Wouter Beek
@version 2016/01-2016/03
*/

:- use_module(library(aggregate)).
:- use_module(library(apply)).
:- use_module(library(atom_ext)).
:- use_module(library(debug_ext)).
:- use_module(library(dict_ext)).
:- use_module(library(error)).
:- use_module(library(filesex)).
:- use_module(library(gen/gen_ntuples)).
:- use_module(library(hash_ext)).
:- use_module(library(http/json)).
:- use_module(library(jsonld/jsonld_metadata)).
:- use_module(library(jsonld/jsonld_read)).
:- use_module(library(os/dir_ext)).
:- use_module(library(os/open_any2)).
:- use_module(library(os/process_ext)).
:- use_module(library(os/thread_ext)).
:- use_module(library(pl/pl_term)).
:- use_module(library(print_ext)).
:- use_module(library(prolog_stack)).
:- use_module(library(rdf/rdf_clean)).
:- use_module(library(rdf/rdf_ext)).
:- use_module(library(rdf/rdf_load)).
:- use_module(library(rdf/rdf_print)).
:- use_module(library(semweb/rdf11)). % Operators.
:- use_module(library(string_ext)).
:- use_module(library(uri/uri_ext)).
:- use_module(library(zlib)).

:- use_module(cpack('LOD-Laundromat'/lclean)).
:- use_module(cpack('LOD-Laundromat'/lfs)).
:- use_module(cpack('LOD-Laundromat'/lhdt)).
:- use_module(cpack('LOD-Laundromat'/seedlist)).

prolog_stack:stack_guard('C').
prolog_stack:stack_guard(none).

:- dynamic
    wm_hash0/2.





%! add_wm is det.
% Add a LOD Laundromat thread.

add_wm :-
  add_wms(1).



%! add_wms(+N) is det.

add_wms(0) :- !.
add_wms(M1) :-
  must_be(positive_integer, M1),
  number_of_wms(N1),
  N2 is N1 + 1,
  atom_concat(wm, N2, Alias),
  thread_create(start_wm0, _, [alias(Alias),detached(false)]),
  M2 is M1 - 1,
  add_wms(M2).



%! current_wm(+Alias) is semidet.
%! current_wm(-Alias) is nondet.

current_wm(Alias) :-
  current_wm(Alias, _).


%! current_wm(+Alias, +Hash) is semidet.
%! current_wm(+Alias, -Hash) is det.
%! current_wm(-Alias, +Hash) is semidet.
%! current_wm(-Alias, -Hash) is nondet.

current_wm(Alias, Hash) :-
  thread_property(Id, alias(Alias)),
  atom_prefix(wm, Alias),
  thread_property(Id, status(running)),
  ignore(wm_hash0(Alias, Hash)).



%! number_of_wms(-N) is det.

number_of_wms(N) :-
  aggregate_all(count, current_wm(_), N).



%! reset is det.
% Reset the LOD Laundromat.  This removes all data files and resets the
% seedlist.

reset :-
  lroot(Root),
  forall(direct_subdir(Root, Subdir), delete_directory_and_contents(Subdir)),
  absolute_file_name(cpack('LOD-Laundromat'), Dir, [file_type(directory)]),
  run_process(git, ['checkout','seedlist.db'], [cwd(Dir)]),
  retractall(wm_hash0(_,_)).



%! single_wm is det.

single_wm :-
  start_wm0.


start_wm0 :-
  wm0(_{idle: 0}).

wm0(State) :-
  % Clean one arbitrary seed.
  begin_seed(Hash, Iri),
  thread_name(Alias),
  wm_hash_update(Alias, Hash),
  number_of_wms(N1),
  debug(wm(thread), "---- [~a,~D] Cleaning ~a", [Alias,N1,Hash]),
  lclean:clean_seed0(Hash, Iri),
  number_of_wms(N2),
  debug(wm(thread), "---- [~a,~D] Cleaned ~a", [Alias,N2,Hash]),
  end_seed(Hash),
  wm0(State).
wm0(State) :-
  M = 100,
  sleep(M),
  thread_name(Alias),
  dict_inc(idle, State, N),
  S is M * N,
  debug(wm(idle), "==== Thread ~w idle ~D sec.", [Alias,S]),
  wm0(State).



%! wm_hash_update(+Alias, +Hash) is det.

wm_hash_update(Alias, Hash) :-
  with_mutex(wm_hash, (
    retractall(wm_hash0(Alias, _)),
    assert(wm_hash0(Alias, Hash))
  )).
