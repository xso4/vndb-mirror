---
title: VNDB.org API v2 (Kana)
header-includes: |
  <style>
  td { vertical-align: top }
  header, header h1 { margin: 0 }
  @media (min-width: 1100px) {
      body { margin: 0 0 0 270px }
      nav { box-sizing: border-box; position: fixed; padding: 50px 20px 10px 10px; top: 0; left: 0; height: 100%; overflow: scroll }
  }
  </style>
---

# Introduction

This document describes the HTTPS API to query information from the
[VNDB](https://vndb.org/) database and manage user lists.

This version of the API is intended to replace the [old TCP-based
API](https://vndb.org/d11), although the old API will likely remain available
for the forseeable future.

**Status**: Beta, some functionality is still missing and breaking changes may
occur.

**API endpoint**: `%endpoint%`

A sandbox endpoint is available for testing and development at
[https://beta.vndb.org/api/kana](https://beta.vndb.org/api/kana), for more
information see [the sandbox](https://beta.vndb.org/about-sandbox).

# Usage Terms

This service is free for non-commercial use. The API is provided on a
best-effort basis, no guarantees are made about the stability or applicability
of this service.

The data obtained through this API is subject to our [Data
License](https://vndb.org/d17#4).

API access is rate-limited in order to keep server resources in check. The
server will allow up to 200 requests per 5 minutes and up to 1 second of
execution time per minute. Requests taking longer than 3 seconds will be
aborted. These limits should be more than enough for most applications, but if
this is still too limiting for you, don't hesitate to get in touch.

This API intentionally does not expose *all* functionality provided by VNDB.
Some site features, such as forums, database editing or account creation will
not be exposed through the API, other features may be missing simply because
nobody has asked for it yet. If you need anything not yet provided by the API
or if you have any other questions, feel free to post on [the
forums](https://vndb.org/t/db), [the issue
tracker](https://code.blicky.net/yorhel/vndb/issues) or mail
[contact@vndb.org](mailto:contact@vndb.org).


# Common Data Types

vndbid
:   A 'vndbid' is an identifier for an entry in the database, typically
    formatted as a number with a one or two character prefix, e.g. "v17" refers
    to [this visual novel](https://vndb.org/v17) and "sf190" refers to [this
    screenshot](https://vndb.org/img/sf190).
:   The API will return vndbids as a JSON string, but the filters also accept
    bare integers if the prefix is unambiguous from the context. Which,
    currently, is always the case.

release date
:   Release dates are represented as JSON strings as either `"YYYY-MM-DD"`,
    `"YYYY-MM"` or `"YYYY"` formats, depending on whether the day and month are
    known. Unspecified future dates are returned as `"TBA"`. The values
    `"unknown"` and `"today"` are also supported in filters.
:   Partial dates are ordered *after* complete dates for the same year/month,
    i.e. `"2022"` is ordered after `"2022-12"`, which in turn is ordered after
    `"2022-12-31"`. This can be unintuitive when writing filters: `["released",
    "<", "2022-01"]` also matches all complete dates in Jan 2022. Likewise,
    `["released", "=", "2022"]` only matches items for which the release date
    is exactly `"2022"`, not any other date in that year.

*TODO: Something about languages, platforms and other enumeration types.*

# Simple Requests

## GET /stats

Returns a few overall database statistics.

`curl %endpoint%/stats`

```json
{
  "chars": 112347,
  "producers": 14789,
  "releases": 91490,
  "staff": 27929,
  "tags": 2783,
  "traits": 3115,
  "vn": 36880
}
```

## GET /user

Lookup users by id or username. Requested ids or usernames are given as one or
more `q` query parameters. The response object contains one key for each given
`q` parameter, its value is either `null` if no such user was found or an
object with an `id` and `username` field otherwise.

Strings that look like user IDs are not valid usernames, so the lookup is
unambiguous. Usernames matching is case-insensitive.

`curl '%endpoint%/user?q=NoUserWithThisNameExists&q=AYO&q=u3'`

```json
{
  "AYO": {
    "id": "u3",
    "username": "ayo"
  },
  "NoUserWithThisNameExists": null,
  "u3": {
    "id": "u3",
    "username": "ayo"
  }
}
```

# Database Querying

## API Structure

Searching for and fetching database entries is done through a custom query
format^[Yes, sorry, I know every API having its own query system sucks, but I
couldn't find an existing solution that works well for VNDB.]. Queries are sent
as `POST` requests, but I expect to also support the `QUERY` HTTP method once
that gains more software support.

### Query format

A query is a JSON object that looks like this:

```json
{
  "filters": [],
  "fields": "",
  "sort": "id",
  "reverse": false,
  "results": 10,
  "page": 1,
  "user": null,
  "count": false,
  "compact_filters": false,
  "normalized_filters": false
}
```

All members are optional, defaults are shown above.

filters
:   Filters are used to determine which database items to fetch, see the
    section on [Filters](#filters) below.

fields
:   String. Comma-separated list of fields to fetch for each database item. Dot
    notation can be used to select nested JSON objects, e.g. `"image.url"` will
    select the `url` field inside the `image` object. Multiple nested fields
    can be selected with brackets, e.g. `"image{id,url,dims}"` is equivalent to
    `"image.id, image.url, image.dims"`.
:   Every field of interest must be explicitely mentioned, there is no support
    for wildcard matching. The same applies to nested objects, it is an error
    to list `image` without sub-fields in the example above.
:   The top-level `id` field is always selected by default and does not have to
    be mentioned in this list.

sort
:   Field to sort on. Supported values depend on the type of data being queried
    and are documented separately.

reverse
:   Set to true to sort in descending order.

results
:   Number of results per page, max 100. Can also be set to `0` if you're not
    interested in the results at all, but just want to verify your query or get
    the `count`, `compact_filters` or `normalized_filters`.

page
:   Page number to request, starting from 1. See also the [note on
    pagination](#pagination) below.

user
:   User ID. This field is currently only required for `POST /ulist`. It also
    sets the default user ID to use for the visual novel "label" filter.

count
:   Whether the response should include the `count` field (see below). This
    option should be avoided when the count is not needed since it has a
    considerable performance impact.

compact\_filters
:   Whether the response should include the `compact_filters` field (see below).

normalized\_filters
:   Whether the response should include the `normalized_filters` field (see below).


### Response format

```json
{
  "results": [],
  "more": false,
  "count": 1,
  "compact_filters": "",
  "normalized_filters": [],
}
```

results
:   Array of objects representing the query results.

more
:   When `true`, repeating the query with an incremented `page` number will
    yield more results. This is a cheaper form of pagination than using the
    `count` field.

count
:   Only present if the query contained `"count":true`. Indicates the total
    number of entries that matched the given filters.

compact\_filters
:   Only present if the query contained `"compact_filters":true`. This is a
    compact string representation of the filters given in the query.

normalized\_filters
:   Only present if the query contained `"normalized_filters":true`. This is
    a normalized JSON representation of the filters given in the query.

### Filters

Simple predicates are represented as a three-element JSON array containing a
filter name, operator and value, e.g. `[ "id", "=", "v17" ]`. All filters
accept the (in)equality operators `=` and `!=`. Filters that support ordering
also accept `>=`, `>`, `<=` and `<`.  The full list of accepted filter names
and values is documented below for each type of database item.

Simple predicates can be combined into larger queries with and/or predicates.
These are represented as JSON arrays where the first element is either `"and"`
or `"or"`, followed by two or more other predicates.

Full example of a more complex visual novel filter (which, as of writing,
doesn't actually match anything in the database):

```json
[ "and"
, [ "or"
  , [ "lang", "=", "en" ]
  , [ "lang", "=", "de" ]
  , [ "lang", "=", "fr" ]
  ]
, [ "olang", "!=", "ja" ]
, [ "release", "=", [ "and"
    , [ "released", ">=", "2020-01-01" ]
    , [ "producer", "=", [ "id", "=", "p30" ] ]
    ]
  ]
]
```

Besides the above JSON format, filters can also be represented as a more
compact string. This representation is used in the URLs for the advanced search
web interface^[Fun fact: the web interface also accepts filters in JSON form,
but that tends to result in long and ugly URLs.] and is also accepted as value
to the `"filters"` field. Since actually working with the compact string
representation is kind of annoying, this API can convert between the two
representations, so you can freely copy filters from the website to the API and
the other way around.^[There is also a third representation for filters, which
the API also accepts, but I won't bother you with that. It's only useful as an
intermediate representation when converting between the JSON and string format,
which you shouldn't be doing manually.]

The compact representation of the above example is
`"03132gen2gde2gfr3hjaN180272_0c2vQN6830u"` and can be seen in action in [the web
UI](https://vndb.org/v?f=03132gen2gde2gfr3hjaN180272_0c2vQN6830u). The following
command will convert that string back into the above JSON:

```sh
curl %endpoint%/vn --header 'Content-Type: application/json' --data '{
    "filters": "03132gen2gde2gfr3hjaN180272_0c2vQN6830u",
    "normalized_filters": true
}'
```

Note that the advanced search editing UI on the site does not support all
filter types, for unsupported filters you will see an "Unrecognized filter"
block.  These are pretty harmless, the filter still works.

#### Filter flags

These flags are used in the documentation below to describe a few common filter
properties.

------------------------------------------------------------------------
 Flag  Description
-----  -----------------------------------------------------------------
    o  Ordering operators (such as `>` and `<`) can be used with this filter.

    n  This filter accepts `null` as value.

    m  A single entry can match multiple values. For example, a visual novel
       available in both English and Japanese matches both `["lang","=","en"]`
       and `["lang","=","ja"]`.

    i  Inverting or negating this filter (e.g. by changing the operator from
       '=' to '!=' or from '>' to '<=') is not always equivalent to inverting
       the selection of matching entries. This often means that the filter
       implies another requirement (e.g. that the information must be known in
       the first place), but the exact details depend on the filter.
------------------------------------------------------------------------

Be careful with applying boolean algebra to filters with the 'm' or 'i' flags,
the results may be unintuitive. For example, searching for releases matching
`["or",["minage","=",0],["minage","!=",0]]` will **not** find all releases in
the database, but only those for which the `minage` field is known. Exact
semantics regarding unknown or missing information often depends on how the
filter is implemented and may be subject to change.

## POST /vn

Query visual novel entries.

```sh
curl %endpoint%/vn --header 'Content-Type: application/json' --data '{
    "filters": ["id", "=", "v17"],
    "fields": "title, image.url"
}'
```

Accepted values for `"sort"`: `id`, `title`, `released`, `popularity`, `rating`, `votecount`.

### Filters {#vn-filters}

-----------------------------------------------------------------------------
Name              [F]  Description
----------------  ---- -------------------------------------------------------
`id`              o    vndbid

`search`          m    String search, matches on the VN titles, aliases and release titles.
                       The search algorithm is the same as used on the site.

`lang`            m    Language availability.

`olang`                Original language.

`platform`        m    Platform availability.

`length`          o    Play time estimate, integer between 1 (Very short) and 5 (Very long).
                       This filter uses the length votes average when available but
                       falls back to the entries' `length` field when there are no votes.

`released`        o,n  Release date.

`popularity`      o    Popularity score, integer between 0 and 100.

`rating`          o,i  Bayesian rating, integer between 10 and 100.

`votecount`       o    Integer, number of votes.

`has_description`      Only accepts a single value, integer `1`.
                       Can of course still be negated with the `!=` operator.

`has_anime`            See `has_description`.

`has_screenshot`       See `has_description`.

`has_review`           See `has_description`.

`devstatus`            Development status, integer. See `devstatus` field.

`tag`             m    Tags applied to this VN, also matches parent tags. See below for more details.

`dtag`            m    Tags applied directly to this VN, does not match parent tags. See below for details.

`anime_id`             Integer, AniDB anime identifier.

`label`           m    User labels applied to this VN. Accepts a two-element
                       array containing a user ID and label ID. If the `"user"`
                       request parameter has been set, then it also accepts
                       just a label ID.

`release`         m    Match visual novels that have at least one release
                       matching the given [release filters](#release-filters).

`character`       m    Match visual novels that have at least one character
                       matching the given [character filters](#character-filters).

`staff`           m    Match visual novels that have at least one staff member
                       matching the given [staff filters](#staff-filters).

`developer`       m    Match visual novels developed by the given [producer filters](#producer-filters).
------------------------------------------------------------------------------

The `tag` and `dtag` filters accept either a plain tag ID or a three-element
array containing the tag ID, maximum spoiler level (0, 1 or 2) and minimum tag
level (number between 0 and 3, inclusive), for example
`["tag","=",["g505",2,1.2]]` matches all visual novels that have a [Donkan
Protagonist](https://vndb.org/g505) with a vote of at least 1.2 at any spoiler
level. If only an ID is given, `0` is assumed for both the spoiler and tag
levels. For example, `["tag","=","g505"]` is equivalent to
`["tag","=",["g505",0,0]]`.

### Fields {#vn-fields}

id
:   vndbid.

title
:   String, main title as displayed on the site, typically romanized from the
    original script.[^title]

alttitle
:   String, can be null. Alternative title, typically the same as `title` but
    in the original script.[^title]

titles
:   Array of objects, full list of titles associated with the VN, always
    contains at least one title.

titles.lang
:   String, language. Each language appears at most once in the titles list.

titles.title
:   String, title in the original script.

titles.latin
:   String, can be null, romanized version of `title`.

titles.official
:   Boolean.

titles.main
:   Boolean, whether this is the "main" title for the visual novel entry.
    Exactly one title has this flag set in the `titles` array and it's always
    the title whose `lang` matches the VN's `olang` field. This field is
    included for convenience, you can of course also use the `olang` field to
    grab the main title.

aliases
:   Array of strings, list of aliases.

olang
:   String, language the VN has originally been written in.

devstatus
:   Integer, development status. 0 meaning 'Finished', 1 is 'In development'
    and 2 for 'Cancelled'.

released
:   Release date, possibly null.

languages
:   Array of strings, list of languages this VN is available in. Does not
    include machine translations.

platforms
:   Array of strings, list of platforms for which this VN is available.

image
:   Object, can be null.

image.id
:   String, image identifier.

image.url
:   String.

image.dims
:   Pixel dimensions of the image, array with two integer elements indicating
    the width and height.

image.sexual
:   Number between 0 and 2 (inclusive), average image flagging vote for sexual
    content.

image.violence
:   Number between 0 and 2 (inclusive), average image flagging vote for violence.

image.votecount
:   Integer, number of image flagging votes.

length
:   Integer, possibly null, rough length estimate of the VN between 1 (very
    short) and 5 (very long). This field is only used as a fallback for when
    there are no length votes, so you'll probably want to fetch
    `length_minutes` too.

length\_minutes
:   Integer, possibly null, average of user-submitted play times in minutes.

length\_votes
:   Integer, number of submitted play times.

description
:   String, possibly null, may contain [formatting codes](https://vndb.org/d9#4).

rating
:   Number between 10 and 100, null if nobody voted.

popularity
:   Number between 0 and 100.

votecount
:   Integer, number of votes.

screenshots
:   Array of objects, possibly empty.

screenshots.\*
:   The above `image.*` fields are also available for screenshots.

screenshots.thumbnail
:   String, URL to the thumbnail.

screenshots.thumbnail\_dims
:   Pixel dimensions of the thumbnail, array with two integer elements.

screenshots.release.\*
:   Release object. All [release fields](#release-fields) can be selected. It
    is very common for all screenshots of a VN to be assigned to the same
    release, so the fields you select here are likely to get duplicated several
    times in the response. If you want to fetch more than just a few fields, it
    is more efficient to only select `release.id` here and then grab detailed
    release info with a separate request.

tags
:   Array of objects, possibly empty. Only directly applied tags are returned,
    parent tags are not included.

tags.rating
:   Number, tag rating between 0 (exclusive) and 3 (inclusive).

tags.spoiler
:   Integer, 0, 1 or 2, spoiler level.

tags.lie
:   Boolean.

tags.\*
:   All [tag fields](#tag-fields) can be used here. If you're fetching tags for
    more than a single visual novel, it's usually more efficient to only select
    `tags.id` here and then fetch (and cache) further tag information as a
    separate request. Otherwise the same tag info may get duplicated many times
    in the response.

*Currently missing from the old API: VN relations, staff, anime relations and
external links. Also potentially useful: list of developers and VA's(?). Can
add if there's interest.*


## POST /release

Accepted values for `"sort"`: `id`, `title`, `released`.

### Filters {#release-filters}

-----------------------------------------------------------------------------
Name                [F]   Description
------------------  ----  -------------------------------------------------------
`id`                o     vndbid

`search`            m     String search.

`lang`              m     Match on available languages.

`platform`          m     Match on available platforms.

`released`          o     Release date.

`resolution`        o,i   Match on the image resolution, in pixels. Value must
                          be a two-element integer array to which the width and
                          height, respectively, are compared. For example,
                          `["resolution","<=",[640,480]]` matches releases with a
                          resolution smaller than or equal to 640x480.

`resolution_aspect` o,i   Same as the `resolution` filter, but additionally
                          requires that the aspect ratio matches that of the
                          given resolution.

`minage`            o,n,i Integer (0-18), age rating.

`medium`            m,n   String.

`voiced`            n     Integer, see `voiced` field.

`engine`            n     String.

`rtype`             m     String, see `vns.rtype` field. If this filter is used
                          when nested inside a visual novel filter, then this
                          matches the `rtype` of the particular visual novel.
                          Otherwise, this matches the `rtype` of any linked
                          visual novel.

`patch`                   Integer, only accepts the value `1`.

`freeware`                See `patch`.

`uncensored`        i     See `patch`.

`official`                See `patch`.

`has_ero`                 See `patch`.

`vn`                m     Match releases that are linked to at least one visual novel
                          matching the given [visual novel filters](#vn-filters).

`producer`          m     Match releases that have at least one producer
                          matching the given [producer filters](#producer-filters).
-----------------------------------------------------------------------------

*Undocumented: animation, extlinks*

### Fields {#release-fields}

id
:   vndbid.

title
:   String, main title as displayed on the site, typically romanized from the
    original script.[^title]

alttitle
:   String, can be null. Alternative title, typically the same as `title` but
    in the original script.[^title]

languages
:   Array of objects, languages this release is available in. There is always
    exactly one language that is considered the "main" language of this
    release, which is only used to select the titles for the `title` and
    `alttitle` fields.

languages.lang
:   String, language. Each language appears at most once.

languages.title
:   String, title in the original script. Can be null, in which case the title
    for this language is the same as the "main" language.

languages.latin
:   String, can be null, romanized version of `title`.

languages.mtl
:   Boolean, whether this is a machine translation.

languages.main
:   Boolean, whether this language is used to determine the "main" title for
    the release entry.

platforms
:   Array of strings.

media
:   Array of objects.

media.medium
:   String.

media.qty
:   Integer, quantity. This is `0` for media where a quantity does not make
    sense, like "internet download".

vns
:   Array of objects, the list of visual novels this release is linked to.

vns.rtype
:   The release type for this visual novel, can be `"trial"`, `"partial"` or
    `"complete"`.

vns.\*
:   All [visual novel fields](#vn-fields) are available.

producers
:   Array of objects.

producers.developer
:   Boolean.

producers.publisher
:   Boolean.

producers.\*
:   All [producer fields](#producer-fields) are available.

released
:   Release date.

minage
:   Integer, possibly null, age rating.

patch
:   Boolean.

freeware
:   Boolean.

uncensored
:   Boolean, can be null.

official
:   Boolean.

has\_ero
:   Boolean.

resolution
:   Can either be null, the string `"non-standard"` or an array of two integers
    indicating the width and height.

engine
:   String, possibly null.

notes
:   String, possibly null, may contain [formatting codes](https://vndb.org/d9#4).

*Missing: External links, gtin, catalog number, animation, voiced.*



## POST /producer

Accepted values for `"sort"`: `id`, `name`.

### Filters {#producer-filters}

-----------------------------------------------------------------------------
Name                [F]   Description
------------------  ----  -------------------------------------------------------
`id`                o     vndbid

`search`            m     String search.

`lang`                    Language.

`type`                    Producer type, see the `type` field below.
-----------------------------------------------------------------------------

### Fields

id
:   vndbid.

name
:   String.

original
:   String, possibly null, name in the original script.

aliases
:   Array of strings.

lang
:   String, primary language.

type
:   String, producer type, `"co"` for company, `"in"` for individual and `"ng"`
    for amateur group.

description
:   String, possibly null, may contain [formatting codes](https://vndb.org/d9#4).

*Missing: External links, relations.*


## POST /character

Accepted values for `"sort"`: `id`, `name`.

### Filters {#character-filters}

-----------------------------------------------------------------------------
Name                [F]   Description
------------------  ----  -------------------------------------------------------
`id`                o     vndbid

`search`            m     String search.

`role`              m     String, see `vns.role` field. If this filter is used
                          when nested inside a visual novel filter, then this
                          matches the `role` of the particular visual novel.
                          Otherwise, this matches the `role` of any linked
                          visual novel.

`blood_type`              String.

`sex`                     String.

`height`            o,n,i Integer, cm.

`weight`            o,n,i Integer, kg.

`bust`              o,n,i Integer, cm.

`waist`             o,n,i Integer, cm.

`hips`              o,n,i Integer, cm.

`cup`               o,n,i String, cup size.

`age`               o,n,i Integer.

`trait'             m     Traits applied to this character, also matches parent
                          traits. See below for more details.

`dtrait`            m     Traits applied directly to this character, does not
                          match parent traits. See below for details.

`birthday`          n     Array of two integers, month and day. Day may be `0`
                          to find characters whose birthday is in a given month.

`seiyuu`            m     Match characters that are voiced by the matching
                          [staff filters](#staff-filters). Voice actor
                          information is actually specific to visual novels,
                          but this filter does not (currently) correlate
                          against the parent entry when nested inside a visual
                          novel filter.

`vn`                m     Match characters linked to visual novels described by
                          [visual novel filters](#vn-filters).
-----------------------------------------------------------------------------

The `trait` and `dtrait` filters accept either a plain trait ID or a
two-element array containing the trait ID and maximum spoiler level. These work
similar to the tag filters for [visual novels](#vn-filters), except that traits
don't have a rating.

### Fields

id
:   vndbid.

name
:   String.

original
:   String, possibly null, name in the original script.

aliases
:   Array of strings.

description
:   String, possibly null, may contain [formatting codes](https://vndb.org/d9#4).

image.\*
:   Object, possibly null, same sub-fields as the `image` [visual novel field](#vn-fields).

blood\_type
:   String, possibly null, `"a"`, `"b"`, `"ab"` or `"o"`.

height
:   Integer, possibly null, cm.

weight
:   Integer, possibly null, kg.

bust
:   Integer, possibly null, cm.

waist
:   Integer, possibly null, cm.

hips
:   Integer, possibly null, cm.

cup
:   String, possibly null, `"AAA"`, `"AA"`, or any single letter in the alphabet.

age
:   Integer, possibly null, years.

vns
:   Array of objects, visual novels this character appears in. The same visual
    novel may be listed multiple times with a different release; the spoiler
    level and role can be different per release.

vns.spoiler
:   Integer.

vns.role
:   String, `"main"` for protagonist, `"primary"` for main characters, `"side"`
    or `"appears"`.

vns.\*
:   All [visual novel fields](#vn-fields) are available here.

vns.release.\*
:   Object, usually null, specific release that this character appears in. All
    [release fields](#release-fields) are available here.

traits
:   Array of objects, possibly empty.

traits.spoiler
:   Integer, 0, 1 or 2, spoiler level.

traits.lie
:   Boolean.

traits.\*
:   All [trait fields](#trait-fields) are available here.

*Missing: sex, instances, voice actor*


## POST /staff

*TODO*

### Filters {#staff-filters}

### Fields


## POST /tag

Accepted values for `"sort"`: `id`, `name`, `vn_count`.

### Filters

-----------------------------------------------------------------------------
Name                [F]   Description
------------------  ----  -------------------------------------------------------
`id`                o     vndbid

`search`            m     String search.

`category`                String, see `category` field.
-----------------------------------------------------------------------------

### Fields {#tag-fields}

id
:   vndbid.

name
:   String.

aliases
:   Array of strings.

description
:   String, may contain [formatting codes](https://vndb.org/d9#4).

category
:   String, `"cont"` for content, `"ero"` for sexual content and `"tech"` for technical tags.

searchable
:   Bool.

applicable
:   Bool.

vn\_count
:   Integer, number of VNs this tag has been applied to, including any child tags.

*Missing: some way to fetch parent/child tags. Not obvious how to do this
efficiently because tags form a DAG rather than a tree.*


## POST /trait

Accepted values for `"sort"`: `id`, `name`, `char_count`.

### Filters

-----------------------------------------------------------------------------
Name                [F]   Description
------------------  ----  -------------------------------------------------------
`id`                o     vndbid

`search`            m     String search.
-----------------------------------------------------------------------------

### Fields {#trait-fields}

id
:   vndbid

name
:   String. Trait names are not necessarily self-describing, so they should
    always be displayed together with their "group" (see below), which is the
    top-level parent that the trait belongs to.

aliases
:   Array of strings.

description
:   String, may contain [formatting codes](https://vndb.org/d9#4).

searchable
:   Bool.

applicable
:   Bool.

group_id
:   vndbid

group_name
:   String

char\_count
:   Integer, number of characters this trait has been applied to, including
    child traits.


## POST /ulist

Fetch a user's list. This API is very much like `POST /vn`, except it requires
the `"user"` parameter to be set and it has a different response structure. All
[visual novel filters](#vn-filters) can be used here.

If the user has visual novel entires on their list that have been deleted from
the database, these will not be returned through the API even though they do
show up on the website.

Accepted values for `"sort"`: `id`, `title`, `released`, `popularity`,
`rating`, `votecount`, `voted`, `vote`, `added`, `lastmod`, `started`,
`finished`.

Very important example on how to fetch Yorhel's top 10 voted visual novels:

```sh
curl %endpoint%/ulist --header 'Content-Type: application/json' --data '{
    "user": "u2",
    "fields": "id, vote, vn.title",
    "filters": [ "label", "=", 7 ],
    "sort": "vote",
    "reverse": true,
    "results": 10
}'
```

### Fields

id
:   Visual novel ID.

added
:   Integer, unix timestamp.

voted
:   Integer, can be null, unix timestamp of when the user voted on this VN.

lastmod
:   Integer, unix timestamp when the user last modified their list for this VN.

vote
:   Integer, can be null, 10 - 100.

started
:   String, start date, can be null, "YYYY-MM-DD" format.

finished
:   String, finish date, can be null.

notes
:   String, can be null.

labels
:   Array of objects, user labels assigned to this VN.

labels.id
:   Integer.

labels.label
:   String.

vn\.*
:   Visual novel info, all [visual novel fields](#vn-fields) can be selected
    here.

releases
:   Array of objects, releases of this VN that the user has added to their list.

releases.list_status
:   Integer, 0 for "Unknown", 1 for "Pending", 2 for "Obtained", 3 for "On
    loan", 4 for "Deleted".

releases.\*
:   All [release fields](#release-fields) can be selected here.


# HTTP Response Codes

Successful responses always return `200 OK` with a JSON body, but errors may
happen. Error response codes are typically followed with a `text/plain` or
`text/html` body. The following is a non-exhaustive list of error codes you can
expect to see:

  Code  Reason
------  -------
   400  Invalid request body or query, the included error message hopefully points at the problem.
   404  Invalid API path or HTTP method
   429  Throttled
   500  Server error, usually points to a bug if this persists
   502  Server is down, should be temporary

# Tips & Troubleshooting

## "Too much data selected"

The server calculates a rough estimate of the number of JSON keys it would
generate in response to your query and throws an error if that estimation
exceeds a certain theshold, i.e. if the response is expected to be rather
large.  This estimation is entirely based on the `"fields"` and `"results"`
parameters, so you can work around this error by either selecting fewer fields
or fewer results.

## List of identifiers

If you have a (potentially large) list of database identifiers you'd like to
fetch, it is faster and more efficient to fetch 100 entries in a single API
call than it is to make 100 separate API calls. Simply create a filter
containing the identifiers, like in the following example:

```sh
curl %endpoint%/vn --header 'Content-Type: application/json' --data '{
  "fields": "title",
  "filters": ["or"
     , ["id","=","v1"]
     , ["id","=","v2"]
     , ["id","=","v3"]
     , ["id","=","v4"]
     , ["id","=","v5"] ],
  "results": 100
}'
```

Do not add more than 100 identifiers in a single query. You'll especially want
to avoid sending the same list of identifiers multiple times but with higher
`"page"` numbers, see also the next point.

## Pagination

While the API supports pagination through the `"page"` parameter, this is often
not the most efficient way to retrieve a large list of entries. Results are
sorted on `"id"` by default so you can also implement pagination by filtering
on this field. For example, if the last item you've received had id `"v123"`,
you can fetch the next page by filtering on `["id",">","v123"]`.

This approach tends to not work as well when sorting on other fields, so
`"page"`-based pagination is often still the better solution in those cases.



*TODO: Footnotes with multiple references get duplicated. Pandoc is [being
weird](https://github.com/jgm/pandoc/issues/1603). Need a workaround, because
this will get annoying really fast. :(*

[F]: #filter-flags

[^title]: Title fields may be subject to user language preferences when
  authentication gets implemented later on. You can always fetch the full list
  of titles and apply your own selection algorithm.
