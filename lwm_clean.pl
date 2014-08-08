:- module(
  lwm_clean,
  [
    lwm_clean_loop/0
  ]
).

/** <module> LOD Washing Machine: cleaning

The cleaning process performed by the LOD Washing Machine.

@author Wouter Beek
@version 2014/03-2014/06, 2014/08
*/

:- use_module(library(aggregate)).
:- use_module(library(apply)).
:- use_module(library(http/http_client)).
:- use_module(library(semweb/rdf_db)).
:- use_module(library(uri)).
:- use_module(library(zlib)).

:- use_module(pl(pl_log)).
:- use_module(void(void_db)). % XML namespace.

:- use_module(plRdf_ser(rdf_detect)).
:- use_module(plRdf_ser(rdf_ntriples_write)).

:- use_module(lwm(lwm_basket)).
:- use_module(lwm(lwm_messages)).
:- use_module(lwm(lwm_settings)).
:- use_module(lwm(md5)).
:- use_module(lwm(noRdf_store)).
:- use_module(lwm(store_triple)).
:- use_module(lwm_sparql(lwm_sparql_query)).



lwm_clean_loop:-
  % Pick a new source to process.
  catch(pick_unpacked(Md5), Exception, var(Exception)),

  % DEB
  (debug_md5(Md5) -> gtrace ; true),

  % Process the URL we picked.
  lwm_clean(Md5),

  % Intermittent loop.
  flag(number_of_idle_loops, _, 0),
  lwm_clean_loop.
% Done for now. Check whether there are new jobs in one seconds.
lwm_clean_loop:-
  sleep(1),
  print_message(warning, idle_loop(lwm_clean)),
  lwm_clean_loop.
debug_md5('3c22dd25de533e90eac53072e40b31ec'). %no_rdf
debug_md5('5401da9718d5ee79dbe37001edc039c3'). %existence_error(directory)
debug_md5('5b4328effff921b18b5cee3da045387c'). %existence_error(source_sink)
debug_md5('6c05d2bd9a68bc6d44d78d543af7ba43'). %io_error(write)
debug_md5('7c2605d9992504f7c8ad9bc5b7308fec'). %instantiation_error
debug_md5('8fcbd6efeb1cb1f6a0f8409f419cb967'). %no_rdf.
debug_md5('993cb6c31a862cd8d9e770581d557925'). %type_error(xml_dom)
debug_md5('b775ae43b94aef4aacdf8abae5e3907f'). %instantiation_error
debug_md5('be7ed1f32a507d3d9f503778e5a37cd9'). %type_error(xml_dom)
debug_md5('cd54621d9e9d3cec30caeb9b21fdb91e'). %limit_exceeded(max_errors)
debug_md5('def6ea9a6bdc58ce77534e83a7a75507'). %timeout_error(read)
debug_md5('def7c635f47c0c9bb34f92b0bc5089db'). %false
debug_md5('f114a00db90b1744827bc59eab4c8fca'). %existence_error(source_sink)


%! lwm_clean(+Md5:atom) is det.

lwm_clean(Md5):-
  print_message(informational, lwm_start(clean,Md5,Source)),

  run_collect_messages(
    clean_md5(Md5),
    Status,
    Messages
  ),

  store_status(Md5, Status),
  maplist(store_message(Md5), Messages),

  store_end_clean(Md5),
  print_message(informational, lwm_end(clean,Md5,Source,Status,Messages)).


%! clean_md5(+Md5:atom) is det.

clean_md5(Md5):-
  % Construct the file name belonging to the given MD5.
  md5_directory(Md5, Md5Dir),
  absolute_file_name(dirty, DirtyFile, [access(read),relative_to(Md5Dir)]),

  % Retrieve the content type, if it was previously determined.
  md5_content_type(Md5, ContentType),

  % Clean the data document in an RDF transaction.
  setup_call_cleanup(
    open(DirtyFile, read, Read),
    (
      rdf_transaction(
        clean_datastream(Md5, DirtyFile, Read, ContentType, VoidUrls),
        _,
        [snapshot(true)]
      ),
      store_stream(Md5,Read)
    ),
    close(Read)
  ),

  % Remove the old file.
  % @tbd This is where a compressed copy of the dirty file could be kept.
  delete_file(DirtyFile),

  % Add the new VoID URLs to the LOD Basket.
  maplist(send_to_basket, VoidUrls).


%! clean_datastream(
%!   +Md5:atom,
%!   +File:atom,
%!   +Read:blob,
%!   +ContentType:atom,
%!   -VoidUrls:ordset(url)
%! ) is det.

clean_datastream(Md5, File, Read, ContentType, VoidUrls):-
  % Guess the RDF serialization format,
  % using the content type and the file extension as suggestions.
  ignore(md5_file_extension(Md5, FileExtension)),
  rdf_guess_format_md5(Md5, Read, FileExtension, ContentType, Format),
  store_triple(ll-Md5, ll-serialization_format,
      literal(type(xsd-string,Format))),

  % Load all triples by parsing the data document
  % according to the guessed RDF serialization format.
  md5_base_url(Md5, Base),
  rdf_load(
    stream(Read),
    [base_uri(Base),format(Format),register_namespaces(false)]
  ),

  % In between loading and saving the data,
  % we count the number of triples, including the number of duplicates.
  aggregate_all(
    count,
    rdf(_, _, _, _),
    TIn
  ),

  % Save the data in a cleaned format.
  save_data_to_file(Md5, File, TOut),

  % Store statistics about the number of (duplicate) triples.
  store_number_of_triples(Md5, TIn, TOut),

  % Make sure any VoID datadumps are added to the LOD Basket.
  find_void_datasets(VoidUrls).



% Helpers

%! find_void_datasets(-VoidUrls:ordset(url)) is det.

find_void_datasets(Urls):-
  aggregate_all(
    set(Url),
    rdf(_, void:dataDump, Url),
    Urls
  ),
  print_message(informational, found_void(Urls)).


%! rdf_guess_format_md5(
%!   +Md5:atom,
%!   +Read:blob,
%!   +FileExtension:atom,
%!   +ContentType:atom,
%!   -Format:atom
%! ) is semidet.

rdf_guess_format_md5(_, Read, FileExtension, ContentType, Format):-
  rdf_guess_format(Read, FileExtension, ContentType, Format), !.
rdf_guess_format_md5(Md5, _, _, _, _):-
  md5_source(Md5, Source),
  throw(error(no_rdf(Source))).


%! save_data_to_file(+Md5:atom, +File:atom, -NumberOfTriples:nonneg) is det.

save_data_to_file(Md5, File, NumberOfTriples):-
  file_directory_name(File, Dir),
  directory_file_path(Dir, 'clean.nt.gz', Path),
  md5_bnode_base(Md5, BaseComponents),
  setup_call_cleanup(
    gzopen(Path, write, Write),
    rdf_ntriples_write(
      Write,
      [bnode_base(BaseComponents),number_of_triples(NumberOfTriples)]
    ),
    close(Write)
  ).


%! send_to_basket(+Url:url) is det.

send_to_basket(Url):-
  lwm_scheme(Scheme),
  lwm_authority(Authority),
  uri_components(
    BasketLocation,
    uri_components(Scheme,Authority,basket,_,_)
  ),
  http_post(BasketLocation, atom(Url), Reply, []),
  writeln(Reply).



% Messages

:- multifile(prolog:message//1).

prolog:message(found_void([])) --> !, [].
prolog:message(found_void([H|T])) -->
  ['    [VoID] Found: ',H,nl],
  prolog:message(found_void(T)).

prolog:message(idle_loop(Kind)) -->
  {flag(number_of_idle_loops(Kind), X, X + 1)},
  ['IDLE ~D'-[X]].

