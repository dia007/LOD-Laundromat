:- module(
  ll_dataset,
  [
    ll_dataset/1 % +Seed
  ]
).

/** <module> LOD Laundromat: Scrape an individual dataset

@author Wouter Beek
@version 2018
*/

:- use_module(library(apply)).
:- use_module(library(debug)).
:- use_module(library(lists)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(settings)).
:- use_module(library(zlib)).

:- use_module(library(dict)).
:- use_module(library(file_ext)).
:- use_module(library(http/http_client2)).
:- use_module(library(media_type)).
:- use_module(library(tapir)).
:- use_module(library(uri_ext)).

:- use_module(library(ll/ll_document)).

:- dynamic
    debug_hash/1.

%debug_hash('4cd198eba288de77ad3406c556ca2e07').
%debug_hash('5541542e841e267a86ce2ee301c1ea00').

% Set global stack to 10GB for larger datasets.
:- set_prolog_stack(global, limit(10*10**9)).





%! ll_dataset(+Seed:dict) is det.

ll_dataset(Seed) :-
  setting(ll_init:temporary_directory, Dir0),
  directory_file_path(Dir0, Seed.hash, Dir),
  create_directory(Dir),
  (debug_hash(Seed.hash) -> gtrace ; true),
  directory_file_path(Dir, Seed.hash, Base),
  file_name_extension(Base, 'nt.gz', File),
  setup_call_cleanup(
    gzopen(File, write, Out),
    ll_documents(Out, Seed),
    close(Out)
  ),
  (   % Do not upload empty datasets.
      is_nonempty_file(File)
  ->  % Create the organization, unless it already exists.
      ignore(organization_create(_, Seed.organization.name, _{}, _)),
      ignore(dataset_create(Seed.organization.name, Seed.dataset.name, _{}, _)),
      setting(ll_init:script, Script),
      process_create(
        path(node),
        [Script,Seed.organization.name,Seed.dataset.name,file(File)],
        []
      ),
      upload_description(Seed),
      upload_image(Dir, Seed),
      upload_license(Seed),
      debug(ll, "DONE ~a ~a", [Seed.organization.name,Seed.dataset.name])
  ;   true
  ),
  delete_directory_and_contents(Dir).

dataset_image(Dir, Seed, File) :-
  (   get_dict(image, Seed.dataset, Url1)
  ;   get_dict(image, Seed.organization, Url1)
  ),
  % We download the URL prior to determining whether it is an image,
  % because we may not be able to download the same image a second
  % time.
  downcase_atom(Url1, Url2),
  uri_file_extensions(Url2, Exts),
  once((
    member(Ext, Exts),
    media_type_extension(media(image/_,_), Ext)
  )),
  file_name_extension(avatar, Ext, Local),
  directory_file_path(Dir, Local, File),
  setup_call_cleanup(
    open(File, write, Out, [type(binary)]),
    (
      catch(http_open2(Url2, In1, [failure(404)]), _, fail),
      call_cleanup(
        copy_stream_data(In1, Out),
        close(In1)
      )
    ),
    close(Out)
  ),
  setup_call_cleanup(
    open(File, read, In2, [type(binary)]),
    is_image(In2),
    close(In2)
  ).

is_nonempty_file(File) :-
  setup_call_cleanup(
    gzopen(File, read, In),
    (
      read_line_to_codes(In, _Line1),
      read_line_to_codes(In, _Line2),
      \+ at_end_of_stream(In)
    ),
    close(In)
  ).

upload_description(Seed) :-
  get_dict(description, Seed.dataset, Desc), !,
  dataset_property(Seed.organization.name, Seed.dataset.name, description(Desc), _).
upload_description(_).

upload_image(Dir, Seed) :-
  dataset_image(Dir, Seed, Image), !,
  dataset_property(Seed.organization.name, Seed.dataset.name, avatar(Image), _).
upload_image(_, _).

upload_license(Seed) :-
  get_dict(license, Seed.dataset, Url), !,
  normalize_license(Url, Label),
  (   % TBD: TAPIR cannot upload the `None' license.
      Label == 'None'
  ->  true
  ;   dataset_property(Seed.organization.name, Seed.dataset.name, license(Label), _)
  ).
upload_license(_).



%! normalize_license(+Url:atom, -Label:atom) is det.
%
% License URLs that cannot be mapped:
%   - ε
%   - http://data.surrey.ca/pages/open-government-licence-surrey
%   - http://portal.opendata.dk/dataset/open-data-dk-licens
%   - http://www.data.gouv.fr/license-Ouverte-Open-license
%   - http://www.nationalarchives.gov.uk/doc/non-commercial-government-licence/
%   - http://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/
%   - https://creativecommons.org/licenses/by/3.0/at/deed.de
%   - https://www.agesic.gub.uy/innovaportal/file/6327/1/licencia-de-datos-abiertos.pdf

normalize_license(Url, Label) :-
  license_(Prefix, Label),
  atom_prefix(Url, Prefix), !.
normalize_license(Url, 'None') :-
  print_message(warning, unsupported_license(Url)).

% CC0 1.0
license_('http://creativecommons.org/publicdomain/zero/1.0', 'CC0 1.0').
license_('http://www.opendefinition.org/licenses/cc-zero', 'CC0 1.0').
license_('https://creativecommons.org/publicdomain/zero/1.0', 'CC0 1.0').

/*
% CC-BY
license_('http://creativecommons.org/licenses/by/', 'CC-BY').
license_('http://www.opendefinition.org/licenses/cc-by', 'CC-BY').
license_('https://creativecommons.org/licenses/by/', 'CC-BY').
*/

/*
% CC-BY-NC
license_('http://creativecommons.org/licenses/by-nc/', 'CC-BY-NC').
*/

% CC-BY-SA
license_('http://creativecommons.org/licenses/by-sa/', 'CC-BY-SA').
license_('http://www.opendefinition.org/licenses/cc-by-sa', 'CC-BY-SA').
license_('https://creativecommons.org/licenses/by-sa/3.0/', 'CC-BY-SA').

% GFDL
license_('http://www.opendefinition.org/licenses/gfdl', 'GFDL').

% ODC-BY
license_('http://www.opendefinition.org/licenses/odc-by', 'ODC-By').

% ODC-ODBL
license_('http://www.opendefinition.org/licenses/odc-odbl', 'ODC-ODbL').

/*
% OGL
license_('http://reference.data.gov.uk/id/open-government-licence', 'OGL').
*/

% PDDL
license_('http://www.opendefinition.org/licenses/odc-pddl', 'PDDL').
