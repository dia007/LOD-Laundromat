:- module(
  lwm_progress,
  [
    lwm_progress/2 % +Request:list(nvpair)
                   % +HtmlStyle
  ]
).

/** <module> LOD Washing Machine: Progress

A Web-based debug tool for tracking the progress of the LOD Washing Machine.

@author Wouter Beek
@version 2014/09
*/

:- use_module(library(http/html_write)).

:- use_module(plHtml(html_pl_term)).

:- use_module(plTabular(rdf_html_table)).

:- use_module(lwm(lwm_sparql_query)).



%! lwm_progress(+Request:list(nvpair), +HtmlStyle)// is det.

lwm_progress(_, HtmlStyle):-
  reply_html_page(
    HtmlStyle,
    title('LOD Laundromat'),
    html([
      \pending_table,
      \unpacking_table,
      \unpacked_table_small,
      \unpacked_table_medium,
      \unpacked_table_large,
      \cleaning_table,
      \cleaned_table
    ])
  ).


%! pending_table// is det.

pending_table -->
  {lwm_sparql_select(
    [llo],
    [datadoc],
    [
      rdf(var(datadoc),llo:added,var(added)),
      not([rdf(var(datadoc),llo:startUnpack,var(start))])
    ],
    Rows,
    []
  )},
  progress_table(' pending data documents.', Rows).


%! unpacking_table(+Graph:atom)// is det.

unpacking_table -->
  {lwm_sparql_select(
    [llo],
    [datadoc],
    [
      rdf(var(datadoc),llo:startUnpack,var(startUnpack)),
      not([
        rdf(var(datadoc),llo:endUnpack,var(endUnpack))
      ])
    ],
    Rows,
    []
  )},
  progress_table(' data documents are being unpacked.', Rows).


%! unpacked_table_small// is det.

unpacked_table_small -->
  {
    Max is 0.5 * (1024 ** 3), % 0.5 GB
    lwm_sparql_query:build_unpacked_query(_, Max, Query),
    lwm_sparql_select([llo], [datadoc], Query, Rows, [])
  },
  progress_table(' SMALL unpacked data documents.', Rows).


%! unpacked_table_medium// is det.

unpacked_table_medium -->
  {
    Min is 0.5 * (1024 ** 3), % 0.5 GB
    Max is 2.5 * (1024 ** 3), % 2.5 GB
    lwm_sparql_query:build_unpacked_query(Min, Max, Query),
    lwm_sparql_select([llo], [datadoc], Query, Rows, [])
  },
  progress_table(' MEDIUM unpacked data documents.', Rows).


%! unpacked_table_large// is det.

unpacked_table_large -->
  {
    Min is 2.5 * (1024 ** 3), % 2.5 GB
    Max is 30 * (1024 ** 3), % 30 GB
    lwm_sparql_query:build_unpacked_query(Min, Max, Query),
    lwm_sparql_select([llo], [datadoc], Query, Rows, [])
  },
  progress_table(' LARGE unpacked data documents.', Rows).


%! cleaning_table// is det.

cleaning_table -->
  {lwm_sparql_select(
    [llo],
    [datadoc],
    [
      rdf(var(datadoc),llo:startClean,var(start_clean)),
      not([rdf(var(datadoc),llo:endClean,var(end_clean))])
    ],
    Rows,
    []
  )},
  progress_table(' data documents are being cleaned.', Rows).


%! cleaned_table// is det.

cleaned_table -->
  {lwm_sparql_select(
    [llo],
    [datadoc],
    [rdf(var(datadoc),llo:endClean,var(end_clean))],
    Rows,
    []
  )},
  progress_table(' cleaned data documents.', Rows).



% Helpers

%! progress_table(+CaptionPostfix:atom, +Rows:list(list(iri)))// is det.

progress_table(CaptionPostfix, Rows) -->
  {length(Rows, Length)},
  rdf_html_table(
		html([\html_pl_term(lwm_progress,Length),CaptionPostfix]),
    [['Data document']|Rows],
    [
      header_column(true),
      header_row(true),
      indexed(true),
      location(lwm_progress),
      maximum_number_of_rows(3)
    ]
  ).
