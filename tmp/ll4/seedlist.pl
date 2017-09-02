:- module(
  seedlist,
  [
    add_seed/1,      % +Uri
    end_seed/1,      % +Hash
    init_seedlist/0,
    seed/5,          % ?Hash, ?Uri, ?Added, ?Started, ?Ended
    start_seed/2     % -Hash, -Uri
  ]
).

/** <module> Seedlist

@author Wouter Beek
@version 2017/04
*/

:- use_module(library(ckan_query)).
:- use_module(library(debug)).
:- use_module(library(md5)).
:- use_module(library(persistency)).
:- use_module(library(semweb/rdf11)).
:- use_module(library(uri)).

:- use_module(ll_api).

:- debug(seedlist).

:- initialization(db_attach('seedlist.data', [])).

:- persistent
   seed(hash:atom, uri:atom, added:float, started:float, ended:float).





%! add_seed(+Uri) is det.

add_seed(Uri0) :-
  uri_normalized(Uri0, Uri),
  md5_hash(Uri, Hash, []),
  with_mutex(seedlist, (
    (   seed(Hash, Uri, _, _, _)
    ->  true
    ;   get_time(Now),
        assert_seed(Hash, Uri, Now, 0.0, 0.0),
        debug(seedlist, "Seedpoint added: ~a", [Uri])
    )
  )).



%! end_seed(+Hash) is semidet.

end_seed(Hash) :-
  with_mutex(seedlist, (
    retract_seed(Hash, Uri, Added, Started, 0.0),
    get_time(Ended),
    assert_seed(Hash, Uri, Added, Started, Ended)
  )).



%! init_seedlist is det.

init_seedlist :-
  forall(
    ckan_resource_uri(Uri),
    add_seed(Uri)
  ).



%! start_seed(-Hash, -Uri) is semidet.

start_seed(Hash, Uri) :-
  with_mutex(seedlist, (
    retract_seed(Hash, Uri, Added, 0.0, 0.0),
    get_time(Started),
    assert_seed(Hash, Uri, Added, Started, 0.0)
  )).