---
title: VNDB.org API v1 (Nyan)
header-includes: |
  <style>
  body { max-width: 900px }
  td { vertical-align: top }
  header, header h1 { margin: 0 }
  @media (min-width: 1100px) {
      body { margin: 0 0 0 270px }
      nav { box-sizing: border-box; position: fixed; padding: 50px 20px 10px 10px; top: 0; left: 0; height: 100%; overflow: scroll }
  }
  </style>
---

# DEPRECATION WARNING

This old version 1 API is deprecated and may be removed in the future. Please
migrate to the [new HTTPS API](https://api.vndb.org/kana).

# Introduction

This document describes the legacy TCP API of VNDB.

**Usage terms**

This service is free for non-commercial use. The API is provided on a
best-effort basis, no guarantees are made about the stability or applicability
of this service.

The data obtained through this API is subject to our [Data
License](https://vndb.org/d17#4).

**Design goals**

- Simple in implementation of both client and server. "Simple" here means that
  it shouldn't take much code to write a secure and full implementation and
  that client applications shouldn't require huge dependency trees just to use
  this API.
- Powerful: Not as powerful as raw SQL, but not as rigid as commonly used REST
  or RPC protocols.
- High-level: common applications need to perform only few actions to get what
  they want.
- Fast: minimal bandwidth overhead and simple and customizable queries.

**Design overview**

- TCP-based, all communication between the client and the server is done using
  one TCP connection. This connection stays alive until it is explicitely
  closed by either the client or the server.
- Request/response, client sends a request and server replies with a response.
- Session-based: clients are required to login before issuing commands to the
  server. A session is created by issuing the 'login' command, this session
  stays valid for the lifetime of the TCP connection.
- **Everything** sent between the client and the server is encoded in UTF-8.

**Limits**

The following limits are enforced by the server, in order to limit the server
resources and prevent abuse of this service.

- 10 connections per IP. All connections that are opened after reaching this
  limit will be immediately closed.
- 200 commands per 10 minutes per ip. Server will reply with a 'throttled'
  error (type="cmd") when reaching this limit.
- 1 second of SQL time per minute per ip. SQL time is the total time taken to
  run the database queries for each command.  This depends on both the command
  (filters and get flags) and server load, and is thus not very predictable.
  Server will reply with a 'throttled' error with type="sql" upon reaching this
  limit.
- Each command returns at most 25 results, with the exception of get
  votelist/vnlist/wishlist/ulist, which returns at most 100 results.

These limits may sound strict, but in practice you won't have to worry much
about it. As long as your application properly waits when the server replies
with a "throttle" error, everything will be handled automatically. In the event
that your application does require more resources, don't hesitate to ask.

**Connection info:**

Host
: api.vndb.org

Port (plain tcp)
: 19534 ('VN')

Port (TLS)
: 19535
: For improved security, make sure to verify that the certificate is valid for
'api.vndb.org' and is signed by a trusted root (in particular, by [Let's
Encrypt](https://letsencrypt.org/certificates/)).



# Request/response syntax

The VNDB API uses the JSON format for data in various places, this document
assumes you are familiar with it. See
[JSON.org](https://www.json.org/json-en.html) for a quick overview and [RFC
4627](https://www.ietf.org/rfc/rfc4627.txt?number=4627) for the glory details.

The words _object_, _array_, _value_, _string_, _number_ and _integer_ refer to
the JSON data types. In addition the following definitions are used in this
document:

_request_ or _command_
: Message sent from the client to the server.

_response_
: Message sent from the server to the client.

_whitespace_
: Any sequence of the following characters: space, tab, line feed and carriage
return.  (hexadecimal: 20, 09, 0A, 0D, respectively). This is in line with the
definition of whitespace in the JSON specification.

_date_
: A _string_ signifying a date (in particular: release date). The following
formats are used: "yyyy" (when day and month are unknown), "yyyy-mm" (when day
is unknown) "yyyy-mm-dd", and "tba" (To Be Announced). If the year is not known
and the date is not "tba", the special value **null** is used.

**Message format**

A message is formatted as a command or response name, followed by any number of
arguments, followed by the End Of Transmission character (04 in hexadecimal).
Arguments are separated by one or more whitespace characters, and any sequence
of whitespace characters is allowed before and after the message.

The command or response name is an unescaped string containing only lowercase
alphabetical ASCII characters, and indicates what kind of command or response
this message contains.

An argument can either be an unescaped string (not containing whitespace), any
JSON value, or a filter string. The following two examples demonstrate a
'login' command, with an object as argument. Both messages are equivalent, as
the whitespace is ignored. '0x04' is used to indicate the End Of Transmission
character.

```
login {"protocol":1,"username":"ayo"}0x04
```
```
login {
 "protocol" : 1,
 "username" : "ayo"
}
0x04
```

The 0x04 byte will be ommitted in the other examples in this document. It is
however still required.

**Filter string syntax**

Some commands accept a filter string as argument. This argument is formatted
similar to boolean expressions in most programming languages. A filter consists
of one or more _expressions_, separated by the boolean operators "and" or "or"
(lowercase). Each filter expression can be surrounded by parentheses to
indicate precedence, the filter argument itself must be surrounded by
parentheses.

An _expression_ consists of a _field name_, followed by an _operator_ and a
_value_. The field name must consist entirely of lowercase alphanumeric
characters and can also contain an underscore. The operator must be one of the
following characters: =, !=, <, <=, >, >= or ~.  The _value_ can be any valid
JSON value. Whitespace characters are allowed, but not required, between all
expressions, field names, operators and values.

The following two filters are equivalent:

```
 (title~"osananajimi"or(id=2))
```
```
 (
   id = 2
   or
   title ~ "osananajimi"
 )
```

More complex filters are also possible:

```
 ((platforms = ["win", "ps2"] or languages = "ja") and released > "2009-01-10")
```

See the individual commands for more details.


# The 'login' command
```
 login {"protocol":1,"client":"test","clientver":0.1,"username":"ayo","password":"hi-mi-tsu!"}
```

Every client is required to login before issuing other commands. The login
command accepts a JSON object as argument. This object has the following
members:

protocol
: An integer that indicates which protocol version the client implements. Must be 1.

client
: A string identifying the client application. Between the 3 and 50 characters,
must contain only alphanumeric ASCII characters, space, underscore and hyphens.
When writing a client, think of a funny (unique) name and hardcode it into your
application.

clientver
: A number or string indicating the software version of the client.

username
: (optional) String containing the username of the person using the client.
When this field is provided, the client must also provide either a "password"
or "sessiontoken".

password
: (optional) String, password of that user in plain text.

sessiontoken
: (optional) String, to log in with a session token instead of password.

createsession
: (optional) Boolean, only available when logging in with a password. This will
create a new session token so that future logins can be done with the
"sessiontoken" field instead of providing a password.

The server can reply with one of the following responses:

ok
: No arguments, returned when the login command is successful and
"createsession" was not specified.

session
: Returned when the login is successful and the "createsession" field was
specified. The response has one argument: the session token encoded as a hex
string. The token will automatically expire one month after its last use, when
the 'logout' command is used (see below) or when the user changes their
password.

error
: Login failed, see below for error codes.

Note that logging in using a username is optional, but some commands are only
available when logged in. It is strongly recommended to connect with TLS when
logging into an account.

Example login request and response without authentication:

```
 login {"protocol":1,"client":"Awesome Client","clientver":"1.0"}
```
```
 ok
```

Example login to obtain a session token:

```
 login {"protocol":1,"client":"Awesome Client","clientver":"1.0","username":"ayo","password":"xyz","createsession":true}
```
```
 session df0cc97e1f0c9f1d59ab67d2be3bb1d437892505
```

Later connections can use that token to log in:

```
 login {"protocol":1,"client":"Awesome Client","clientver":"1.0","username":"ayo","sessiontoken":"df0cc97e1f0c9f1d59ab67d2be3bb1d437892505"}
```
```
 ok
```

## logout

When logged in with a session (either by specifying "createsession" or
"sessiontoken" in the login command), the client can invalidate the token
associated with the session by sending the 'logout' command without arguments:

```
 logout
```

The server will respond with 'ok' and disconnect.


# The 'dbstats' command

This command gives the global database statistics that are visible in the main
menu of the site. The command is simply:

```
 dbstats
```

And the response has the following format:

```
 dbstats stats
```

Where _stats_ is a JSON object with integer values. Example response:

```
 dbstats {"users":0,
          "threads":0,
          "tags":1627,
          "releases":28071,
          "producers":3456,
          "chars":14046,
          "posts":0,
          "vn":13051,
          "traits":1272}
```

The *users*, *threads* and *posts* stats are always '0' and only included for
backwards compatibility.

# The 'get' command

This command is used to fetch data from the database. It accepts 4 arguments:
the type of data to fetch (e.g. visual novels or producers), what part of that
data to fetch (e.g. only the VN titles, or the descriptions and relations as
well), a filter expression, and lastly some options.

```
 get type flags filters options
```

_type_ and _flags_ are unescaped strings. The accepted values for _type_ are
documented below.  _flags_ is a comma-separated list of flags indicating what
info to fetch. The filters, available flags and their meaning are documented
separately for each type. The last _options_ argument is optional, and
influences the behaviour of the returned results. When present, _options_
should be a JSON object with the following members (all are optional):

page
: integer, used for pagination. Page 1 (the default) returns the first 10
results (1-10), page 2 returns the following 10 (11-20), etc. (The actual
number of results per page can be set with the "results" option below).

results
: integer, maximum number of results to return. Also affects the "page" option
above. For example: with "page" set to 2 and "results" set to 5, the second
five results (that is, results 6-10) will be returned. Default: 10.

sort
: string, the field to order the results by. The accepted field names differ
per type, the default sort field is the ID of the database entry.

reverse
: boolean, default false. Set to true to reverse the order of the results.

The following example will fetch basic information and information about the
related anime of the visual novel with id = 17:

```
 get vn basic,anime (id = 17)
```

The server will reply with a 'results' message, this message is followed by a
JSON object describing the results. This object has three members: 'num', which
is an integer indicating the number of results returned, 'more', which is true
when there are more results available (i.e. increasing the _page_ option
described above will give new results) and 'items', which contains the results
as an array of objects. For example, the server could reply to the previous
command with the following message:

```
 results {"num":1, "more":false, "items":[{
   "id": 17, "title": "Ever17 -the out of infinity-", "original": null,
   "released": "2002-08-29", "languages": ["en","ja","ru","zh"],
   "platforms": ["drc","ps2","psp","win"],"anime": []
 }]}
```

Note that the actual result from the server can (and likely will) be formatted
differently and that the order of the members may not be the same. What each
member means and what possible values they can have differs per type and is
documented below.


## get vn

The following members are returned from a 'get vn' command:

| Member | Flag | Type | null? | Description
|--|--|--|--|-----------
id | - | integer | no | Visual novel ID
title | basic | string | no | Main title
original | basic | string | yes | Original/official title.
released | basic | date (string) | yes | Date of the first release.
languages | basic | array of strings | no | Can be an empty array when nothing has been released yet.
orig\_lang | basic | array of strings | no | Original language of the VN. Always contains a single language,
platforms | basic | array of strings | no | Can be an empty array when unknown or nothing has been released yet.
aliases | details | string | yes | Aliases, separated by newlines.
length | details | integer | yes | Length of the game, 1-5, broad category between "very short" and "very long". This field is not displayed on the site if there are length votes available (see below)
length\_minutes | details | integer | yes | Average play time from length votes
length\_votes | details | integer | no | Number of length votes
description | details | string | yes | Description of the VN. Can include formatting codes as described in [d9#3](https://vndb.org/d9#3).
links | details | object | no | Contains the following members: <br>"wikipedia", string, name of the related article on the English Wikipedia (deprecated, use wikidata instead).<br>"encubed", string, the URL-encoded tag used on [encubed](http://novelnews.net/) (deprecated).<br>"renai", string, the name part of the url on [renai.us](http://renai.us/).<br>"wikidata", string, Wikidata identifier.<br>All members can be **null** when no links are available or known to us.
image | details | string | yes | HTTP link to the VN image.
image\_nsfw | details | boolean | no | (deprecated) Whether the VN image is flagged as NSFW or not.
image\_flagging | details | object | yes | Image flagging summary of the main VN image, object with the following fields:<br>"votecount", integer, number of flagging votes.<br>"sexual\_avg", number, sexual score between 0 (safe) and 2 (explicit).<br>"violence\_avg", number, violence score between 0 (tame) and 2 (brutal).<br>The two averages may be **null** if no votes have been cast yet.
image\_width | details | integer | yes |
image\_height | details | integer | yes |
titles | titles | array of objects | no | Full list of titles associated with this VN. Each language is included only once, the "main" title is the one indicated by the "orig\_lang" member. Each object has the following members:<br>"lang": string, language of this title.<br>"title", string, title in the original script<br>"latin", string, possibly null, romanized version of "title"<br>"official", boolean, whether this is an official title.
anime | anime | array of objects | no | (Possibly empty) list of anime related to the VN, each object has the following members:<br>"id", integer, [AniDB](http://anidb.net/) ID<br>"ann\_id", deprecated, always null<br>"nfo\_id", deprecated, always null<br>"title\_romaji", string<br>"title\_kanji", string<br>"year", integer, year in which the anime was aired<br>"type", string<br>All members except the "id" can be **null**. Note that this data is courtesy of AniDB, and may not reflect the latest state of their information due to caching.
relations | relations | array of objects | no | (Possibly empty) list of related visual novels, each object has the following members:<br>"id", integer<br>"relation", string, relation to the VN<br>"title", string, (romaji) title<br>"original", string, original/official title, can be **null**<br>"official", boolean.
tags | tags | array of arrays | no | (Possibly empty) list of tags linked to this VN. Each tag is represented as an array with three elements:<br> tag id (integer),<br>score (number between 0 and 3),<br>spoiler level (integer, 0=none, 1=minor, 2=major)<br>Only tags with a positive score are included. Note that this list may be relatively large - more than 50 tags for a VN is quite possible.<br>General information for each tag is available in the [tags dump](https://vndb.org/d14#2). Keep in mind that it is possible that a tag has only recently been added and is not available in the dump yet, though this doesn't happen often.
rating | stats | number | no | Bayesian rating, between 1 and 10.
votecount | stats | integer | no | Number of votes.
screens | screens | array of objects | no | (Possibly empty) list of screenshots, each object has the following members:<br>"id", string, image ID<br>"image", string, URL of the full-size screenshot<br>"rid", integer, release ID<br>"nsfw", boolean (depecated)<br>"flagging", object, same format as "image\_flagging" field mentioned above<br>"height", integer, height of the full-size screenshot<br>"width", integer, width of the full-size screenshot<br>"thumbnail", string, URL to the thumbnail<br>"thumbnail\_width", integer<br>"thumbnail\_height", integer
staff | staff | array of objects | no | (Possibly empty) list of staff related to the VN, each object has the following members:<br>"sid", integer, staff ID<br>"aid", integer, alias ID<br>"name", string<br>"original", string, possibly null<br>"role", string<br>"note", string, possibly null

Sorting is possible on the following fields: id, title, released, rating, votecount.

'get vn' accepts the following filter expressions:

| Field | Value | Operators | Notes |
|--|--|--|---------------
id | integer<br>array of integers | = != > >= < <=<br>= != | When you need to fetch info about multiple VNs, it is recommended to do so in one command using an array of integers as value. e.g. (id = [7,11,17]).
title | string | = != ~ |
original | null<br>string | = !=<br>= != ~ |
firstchar | null<br><string> | = !=<br>= != | Filter by the first character of the title, similar to the [VN browser interface](http://vndb.org/v/all). The character must either be a lowercase 'a' to 'z', or null to match all titles not starting with an alphabetic character.
released | null<br>date (string) | = !=<br>= != > >= < <= | Note that matching on partial dates (released = "2009") doesn't do what you want, use ranges instead, e.g. (released > "2008" and released <= "2009").
platforms | null<br>string<br>array of strings | <br>= != |
languages | null<br>string<br>array of strings | <br>= != |
orig\_lang | string<br>array of strings | = != |
search | string | ~ | This is not an actual field, but performs a search on the titles of the visual novel and its releases. Note that the algorithm of this search may change and that it can use a different algorithm than the search function on the website.
tags | int<br>array of ints | = != | Find VNs by tag. When providing an array of ints, the '=' filter will return VNs that are linked to any (not all) of the given tags, the '!=' filter will return VNs that are not linked to any of the given tags. You can combine multiple tags filters with 'and' and 'or' to get the exact behavior you need.<br> This filter may used cached data, it may take up to 24 hours before a VN will have its tag updated with respect to this filter.<br> VNs that are linked to childs of the given tag are also included.<br> Be warned that this filter ignores spoiler settings, fetch the tags associated with the returned VN to verify the spoiler level.


## get release

Returned members:

| Member | Flag | Type | null? | Description
|--|--|--|--|---------------
id | - | integer | no | Release ID
title | basic | string | no | Release title (romaji)
original | basic | string | yes | Original/official title of the release.
released | basic | date (string) | yes | Release date
type | basic | string | no | (deprecated) "complete", "partial" or "trial". For releases linked to multiple VNs, the most-complete type will be selected.
patch | basic | boolean | no |
freeware | basic | boolean | no |
doujin | basic | boolean | no | Deprecated and meaningless, don't use.
official | basic | boolean | no |
languages | basic | array of strings | no |
website | details | string | yes | Official website URL
notes | details | string | yes | Random notes, can contain formatting codes as described in [d9#3](https://vndb.org/d9#3)
minage | details | integer | yes | Age rating, 0 = all ages.
gtin | details | string | yes | JAN/UPC/EAN code. This is actually an integer, but formatted as a string to avoid an overflow on 32bit platforms.
catalog | details | string | yes | Catalog number.
platforms | details | array of strings | no | Empty array when platform is unknown.
media | details | array of objects | no | Objects have the following two members:<br> "medium", string<br> "qty", integer, the quantity. **null** when it is not applicable for the medium.<br> An empty array is returned when the media are unknown.
resolution | details | string | yes |
voiced | details | integer | yes | 1 = Not voiced, 2 = Only ero scenes voiced, 3 = Partially voiced, 4 = Fully voiced
animation | details | array of integers | no | The array has two integer members, the first one indicating the story animations, the second the ero scene animations. Both members can be null if unknown or not applicable.<br> <br> When not null, the number indicates the following: 1 = No animations, 2 = Simple animations, 3 = Some fully animated scenes, 4 = All scenes fully animated.
lang | lang | array of objects | no | List of languages with associated metadata. Each object has the following members:<br>"lang": string, language the release is available in<br>"title", string, possibly null, title in the original script<br>"latin", string, possibly null, romanized version of "title"<br>"mtl", boolean, whether this is a machine translation<br>"main", boolean, whether this title is used as main title for the release entry.<br>There is always exactly one object where "main" is true.
vn | vn | array of objects | no | Array of visual novels linked to this release. Objects have the following members: id, rtype, title and original. The "rtype" field indicates whether the release is a "trial", "partial" or "complete" for the given VN. The other fields are the same as the members of the "get vn" command.
producers | producers | array of objects | no | (Possibly empty) list of producers involved in this release. Objects have the following members:<br> "id", integer<br> "developer", boolean,<br> "publisher", boolean,<br> "name", string, romaji name<br> "original", string, official/original name, can be **null**<br> "type", string, producer type
links | links | array of objects | no | List of external links, each represented as an object with string members "label" and "url". Multiple links with the same label may be present. The official website is also included in this list, if one is known.

Sorting is possible on the 'id', 'title' and 'released' fields.

Accepted filters:

| Field | Value | Operators | Notes |
|--|--|--|-------------
id | integer<br>array of integers | = != > >= < <=<br>= != |
vn | integer<br>array of integers | = != | Find releases linked to the given visual novel ID.
producer | integer | = | Find releases linked to the given producer ID.
title | string | = != ~ |
original | null<br>string | = !=<br>= != ~ |
released | null<br>date (string) | = !=<br>= != > >= < <= | Note about released filter for the vn type also applies here.
patch | boolean | = |
freeware | boolean | = |
doujin | boolean | = |
type | string | = != |
gtin | int | = != | Value can also be escaped as a string (if you risk an integer overflow otherwise)
catalog | string | = != |
languages | string<br>array of strings | = != |
platforms | string<br>array of strings | = != |


## get producer

Returned members:

| Member | Flag | Type | null? | Description
|--|--|--|--|--------------
id | - | integer | no | Producer ID
name | basic | string | no | (romaji) producer name
original | basic | string | yes | Original/official name
type | basic | string | no | Producer type
language | basic | string | no | Primary language
links | details | object | no | External links, object has the following members:<br> "homepage", official homepage,<br>"wikipedia", string, name of the related article on the English Wikipedia (deprecated, use wikidata instead).<br>"wikidata", string, Wikidata identifier.<br>All members can be **null**.
aliases | details | string | yes | List of alternative names, separated by a newline
description | details | string | yes | Description/notes of the producer, can contain formatting codes as described in [d9#3](https://vndb.org/d9#3)
relations | relations | array of objects | no | (possibly empty) list of related producers, each object has the following members:<br> "id", integer, producer ID,<br> "relation", string, relation to the current producer,<br> "name", string,<br> "original", string, can be **null**

Sorting is possible on the 'id' and 'name' fields.

The following filters are recognised:

| Field | Value | Operators | Notes |
|--|--|--|-----------------
id | integer<br>array of integers | = != > >= < <=<br>= != |
name | string | = != ~ |
original | null<br>string | = !=<br>= != ~ |
type | string | = != |
language | string<br>array of strings | = != |
search | string | ~ | Not an actual field. Performs a search on the name, original and aliases fields.


## get character

Returned members:

| Member | Flag | Type | null? | Description
|--|--|--|--|-----------------
id | - | integer | no | Character ID
name | basic | string | no | (romaji) name
original | basic | string | yes | Original (kana/kanji) name
gender | basic | string | yes | Character's sex (not gender); "m" (male), "f" (female) or "b" (both)
spoil\_gender | basic | string | yes | Actual sex, if this is a spoiler. Can also be "unknown" if their actual sex is not known but different from their apparent sex.
bloodt | basic | string | yes | Blood type, "a", "b", "ab" or "o"
birthday | basic | array | no | Array of two numbers: day of the month (1-31) and the month (1-12). Either can be null.
aliases | details | string | yes | Deprecated, always null.
description | details | string | yes | Description/notes, can contain formatting codes as described in [d9#3](https://vndb.org/d9#3). May also include [spoiler] tags!
age | details | int | yes | years
image | details | string | yes | HTTP link to the character image.
image\_flagging | details | object | yes | Image flagging summary, see the similar "image\_flagging" field of "get vn".
image\_width | details | integer | yes |
image\_height | details | integer | yes |
bust | meas | integer | yes | cm
waist | meas | integer | yes | cm
hip | meas | integer | yes | cm
height | meas | integer | yes | cm
weight | meas | integer | yes | kg
cup\_size | meas | string | yes |
traits | traits | array of arrays | no | (Possibly empty) list of traits linked to this character. Each trait is represented as an array of two elements: The trait id (integer) and the spoiler level (integer, 0-2). General information for each trait is available in the [traits dump](https://vndb.org/d14#3).
vns | vns | array of arrays | no | List of VNs linked to this character. Each VN is an array of 4 elements: VN id, release ID (0 = "all releases"), spoiler level (0-2) and the role (string).<br> Available roles: "main", "primary", "side" and "appears".
voiced | voiced | array of objects | no | List of voice actresses (staff) that voiced this character, per VN. Each staff/VN is represented as a object with the following members:<br> "id", integer, staff ID<br> "aid", integer, the staff alias ID being used<br> "vid", integer, VN id<br> "note", string<br> The same voice actor may be listed multiple times if this entry is character to multiple visual novels. Similarly, the same visual novel may be listed multiple times if this character has multiple voice actors in the same VN.
instances | instances | array of objects | no | List of instances of this character (excluding the character entry itself). Each instance is represented as an object with the following members:<br> "id", integer, character ID<br> "spoiler", integer, 0=none, 1=minor, 2=major<br> "name", string, character name<br> "original", string, character's original name.

Sorting is possible on the 'id' and 'name' fields.

The following filters are recognised:

| Field | Value | Operators | Notes |
|--|--|--|-----------------
id | integer<br>array of integers | = != > >= < <=<br>= != |
name | string | = != ~ |
original | null<br>string | = !=<br>= != ~ |
search | string | ~ | Not an actual field. Performs a search on the name, original and aliases fields.
vn | integer<br>array of integers | = | Find characters linked to the given visual novel ID(s). Note that this may also include characters that are normally hidden by spoiler settings.
traits | int<br>array of ints | = != | Find chars by traits. When providing an array of ints, the '=' filter will return chars that are linked to any (not all) of the given traits, the '!=' filter will return chars that are not linked to any of the given traits. You can combine multiple trait filters with 'and' and 'or' to get the exact behavior you need.<br> This filter may use cached data, it may take up to 24 hours before a char entry will have its traits updated with respect to this filter.<br> Chars that are linked to childs of the given trait are also included.<br> Be warned that this filter ignores spoiler settings, fetch the traits associated with the returned char to verify the spoiler level.


## get staff

Unlike other database entries, staff have more than one unique identifier.

There is the main 'staff ID', which uniquely identifies a person and is what
the staff pages on the site represent.

Additionally, every staff name and alias also has its own unique identifier,
which is referenced from other database entries to identify which alias was
used. This identifier is generally hidden on the site and aliases do not have
their own page, but the IDs are exposed in this API in order to facilitate
linking between VNs/characters and staff.

Returned members:

| Member | Flag | Type | null? | Description
|--|--|--|--|-------------------
id | - | integer | no | Staff ID
name | basic | string | no | Primary (romaji) staff name
original | basic | string | yes | Primary original name
gender | basic | string | yes |
language | basic | string | no | Primary language
links | details | object | no | External links, object has the following members:<br> "homepage", official homepage,<br>"wikipedia", string, name of the related article on the English Wikipedia (deprecated, use wikidata instead).<br> "twitter", name of the twitter account.<br> "anidb", [AniDB](http://anidb.net/) creator ID.<br> "pixiv", integer, id of the pixiv account.<br> "wikidata", string, Wikidata identifier.<br>All values can be **null**.
description | details | string | yes | Description/notes of the staff, can contain formatting codes as described in [d9#3](https://vndb.org/d9#3)
aliases | aliases | array of arrays | no | List of names and aliases. Each name is represented as an array with the following elements: Alias ID, name (romaji) and the original name.<br> This list also includes the "primary" name.
main\_alias | aliases | integer | no | ID of the alias that is the "primary" name of the entry
vns | vns | array of objects | no | List of visual novels that this staff entry has been credited in (excluding character voicing). Each vn is represented as an object with the following members:<br> "id", integer, visual novel id<br> "aid", integer, alias ID of this staff entry<br> "role", string<br> "note", string, may be null if unset<br> The same VN entry may appear multiple times if the staff has been credited for multiple roles.
voiced | voiced | array of objects | no | List of characters that this staff entry has voiced. Each object has the following members:<br> "id", integer, visual novel id<br> "aid", integer, alias ID of this staff entry<br> "cid", integer, character ID<br> "note", string, may be null if unset<br> The same VN entry may appear multiple times if the staff has been credited for multiple characters. Similarly, the same character may appear multiple times if it has been linked to multiple VNs.

Sorting is possible on the 'id' field.

The following filters are recognised:

| Field | Value | Operators | Notes |
|--|--|--|---------------
id | integer<br>array of integers | = != > >= < <=<br>= != |
aid | integer<br>array of integers | =<br>= |
search | string | ~ | Searched through all aliases, both the romanized and original names.


## get quote

Returned members:

| Member | Flag | Type | null? | Description
|--|--|--|--|----------------
id | - | integer | no | VN ID
title | basic | string | no | VN title
quote | basic | string | no |

Sorting is possible on the 'id' and the pseudo 'random' field (default).

The following filters are recognised:

| Field | Value | Operators | Notes |
|--|--|--|---------------
id | integer<br>array of integers | = != > >= < <=<br>= != |

Note that a filter is required for all *get* commands, so to get a random quote, use:
```
get quote basic (id>=1) {"results":1}
```

## get user

Returned members:

| Member | Flag | Type | null? | Description
|--|--|--|--|-----------------
id | basic | integer | no | User ID
username | basic | string | no

The returned list is always sorted on the 'id' field.

The following filters are recognised:

| Field | Value | Operators | Notes |
|--|--|--|----------------
id | integer<br>array of integers | = | The special value '0' is recognized as the currently logged in user.
username | string<br>array of strings | = != ~<br>= |


## get ulist-labels

Fetch the labels for a user. Returned members:

| Member | Flag | Type | null? | Description
|--|--|--|--|-----------------
uid | basic | integer | no | User ID
id | basic | integer | no | Label ID
label | basic | string | no |
private | basic | boolean | no |

The returned list is always sorted on the 'id' field.

The following filters are recognised:

| Field | Value | Operators | Notes |
|--|--|--|-------------------
uid | integer | = | The special value '0' is recognized as the currently logged in user.

Labels marked as private are only returned for the currently logged in user.

Label ids are local to the user, id < 10 are built-in labels and are the same
for every user, id >= 10 or above are custom labels created by the user or a
migration script.


## get ulist

This command replaces the (obsolete and now undocumented) "get votelist", "get
vnlist" and "get wishlist" commands.

Returned members:

| Member | Flag | Type | null? | Description
|--|--|--|--|-----------------
uid | basic | integer | no | User ID
vn | basic | integer | no | Visual Novel ID
added | basic | integer | no | Unix timestamp of when this item has been added.
lastmod | basic | integer | no | Unix timestamp of when this item has been last modified.
voted | basic | integer | yes | Unix timestamp when the vote has been cast.
vote | basic | integer | yes | Vote between 10 and 100.
notes | basic | string | yes |
started | basic | string | yes | YYYY-MM-DD
finished | basic | string | yes | YYYY-MM-DD
labels | labels | array of objects | no | List of labels assigned to this VN entry, each object has the following fields:<br>"id", integer, label ID<br>"label", string, label name.

Sorting is possible on the following fields: uid, vn, added, lastmod, voted, vote.

The following filters are recognised:

| Field | Value | Operators | Notes |
|--|--|--|-------------------------
uid | integer | = | The special value '0' is recognized as the currently logged in user.
vn | integer<br>array of integers | = != > < >= <=<br>= != | Visual novel ID.
label | integer | = | Label assigned to the VN. As a technical limitation, this filter does not return private labels even when the user is logged in.


# The 'set' command

The set command can be used to modify stuff in the database. It can only be
used when logged in as a user. The command has the following syntax:

```
 set type id fields
```

Here, _type_ is similar to the type argument to the 'get' command, _id_ is the
(integer) identifier of the database entry to change, and _fields_ is an object
with the fields to set or modify. If the _fields_ object is not present, the
set command works as a 'delete'. The interpretation of the _id_ and _fields_
arguments depend on the _type_, and are documented in the sections below.

But before that, let me present some examples to get a feel on what the
previous paragraph meant. The following example adds a '10' vote on
[v17](https://vndb.org/v17), or changes the vote to a 10 if a previous vote was
already present:

```
 set ulist 17 {"vote":100}
```

And here's how to remove Ever17 from the list:

```
 set ulist 17
```

'set' replies with a simple 'ok' on success, or with an 'error' (see below) on
failure. Note that, due to my laziness, no error is currently returned if the
identifier does not exist. So voting on a VN that does not exist will return an
'ok', but no vote is actually added. This behaviour may change in the future.
Note that this API doesn't care whether the VN has been deleted or not, so you
can manage votes and stuff for deleted VNs (Which isn't very helpful, because
'get vn' won't return a thing for deleted VNs).


## set ulist

This command replaces the "set votelist", "set vnlist" and "set wishlist"
commands.

This command facilitates adding, removing and modifying your VN list. The
_identifier_ argument is the visual novel ID, and the following fields are
recognized:

| Field | Type | Description
|--|--|----------------
notes | string | Same as the 'notes' member returned by 'get ulist'. An empty string is considered equivalent to 'null'.
started | string | Same as the 'started' member returned by 'get ulist'.
finished | string | Same as the 'started' member returned by 'get ulist'.
vote | integer | Same as the 'vote' member returned by 'get ulist', in the range 10 to 100.
labels | array of integers | List of label IDs to assign to this VN. This will overwrite any previously assigned labels. Label id 7 ("Voted") is automatically assigned based on whether the vote field is set, so it does not need to be included here. An attempt to assign it anyway will be ignored. Attempts to assign an unknown label ID will be silently ignored, but this is subject to change.

When removing a ulist item, any releases associated with the VN will be removed
from the users' list as well. The release list functionality is not currently
exposed to the API, so is only visible when the web interface is used.



# The 'error' response

Every command to the server can receive an 'error' response, this response has
one argument: a JSON object containing at least a member named "id", which
identifies the error, and a "msg", which contains a human readable message
explaining what went wrong. Other members are also possible, depending on the
value of "id".  Example error message:

```
 error {"id":"parse", "msg":"Invalid command or argument"}
```

Note that the value of "msg" is not directly linked to the error identifier:
the message explains what went wrong in more detail, there are several
different messages for the same id. The following error identifiers are
currently defined:

parse
: Syntax error, unknown command or invalid argument type.

missing
: A JSON object argument is missing a required member. The name of which is
given in the additional "field" member.

badarg
: A JSON value is of the wrong type or in the wrong format. The name of the
incorrect field is given in a "field" member.

needlogin
: Need to be logged in to issue this command.

throttled
: You have used too many server resources within a short time, and need to wait
a bit before sending the next command.  The type of throttle is given in the
"type" member, and the "minwait" and "fullwait" members tell you how long you
need to wait before sending the next command and when you can start bursting
again (this is the recommended waiting time), respectively.  Both values are in
seconds, with a precision of 0.1 seconds.

auth
: (login) Incorrect username/password combination.

loggedin
: (login) Already logged in. Only one successful login command can be issues on
one connection.

gettype
: (get) Unknown type argument to the 'get' command.

getinfo
: (get) Unknown info flag to the 'get' command. The name of the unrecognised
flag is given in an additional "flag" member.

filter
: (get) Unknown filter field or invalid combination of field/operator/argument
type. Includes three additional members: "field", "op" and "value" of the
incorrect expression.

settype
: (set) Unknown type argument to the 'set' command.



# Change Log

This section lists the changes made in each version of the VNDB code. Check out
the [announcements board](https://vndb.org/t/an) for more information about
updates.

**2023-07-11**

- Deprecated "popularity" member of "get vn stats"
- Deprecated "popularity" sort option of "get vn"

**2022-10-04**

- Add "official" member to "get release basic"
- Add "id" and "thumbnail(|\_width|height)" members to "get vn screens"
- Add "image\_(width|height)" members to "get vn details"
- Add "image\_(width|height)" members to "get character details"

**2022-10-02**

- Add "get vn titles"
- Add "length\_minutes" and "length\_votes" members to "get vn basic"
- Add "get release lang"
- Add "get release links"

**2021-12-15**

- Add support for creating and logging in with session tokens in the "login" command.

**2021-11-15**

- The "vn" object returned by "get release" now includes an "rtype" field.
- The "type" field returned by "get release" has been deprecated in favor of the above.

**2021-01-30**

- The "orig\_lang" field in "get vn" now always returns exactly one language.

**2020-12-29**

- Add "get quote" command.

**2020-11-13**

- New fields for "get character": age, cup\_size and spoil\_gender.

**2020-07-09**

- Deprecated the "image\_nsfw" and "nsfw" flags given by "get vn details,screens"
- Added "image\_flagging" fields to "get vn details" and "get character details"
- Added "flagging" field to "get vn screens"

**2020-04-09**

- The "dbstats" command no longer returns stats for *users*, *threads* and *posts*.

**2020-01-01**

- Deprecated the get/set votelist/wishlist/vnlists commands
- The "get ulist-labels", "get ulist" and "set ulist" commands should now be
  used in new code
- See [t13365](https://vndb.org/t13365) for more details

**2019-12-05**

- Early API support for the [new lists feature](https://vndb.org/t13136). The
  votelist/wishlist/vnlist commands will be updated when it goes out of beta.
- Add "get ulist-labels"
- Add "get ulist"
- Add "set ulist"

**2019-10-07**

- Add wikidata links to "get vn/producer/staff"
- Add pixiv links to "get staff"

**2018-06-13**

- Add "get character instances"

**2018-02-07**

- The 'aliases' member for "get producer" is now uses newline as separation rather than a comma

**2017-08-14**

- Add 'uid' field to "get votelist/vnlist/wishlist" commands
- Add 'vn' filter to the same commands
- The 'uid' filter for these commands is now optional, making it possible to find all list entries for a particular VN

**2017-06-21**

- Add "resolution", "voiced", "animation" members to "get release" command
- Add "platforms" filter to "get release" command
- Accept arrays for the "vn" filter to the "get release" command
- Add "search" filter to "get staff"

**2017-05-22**

- Add "vns" and "voiced" flags to "get staff" command
- Add "voiced" flag to "get character" command

**2017-04-28**

- Add "get staff" command
- Add "staff" flag to "get vn" command

**2.27**

- Add "username" filter to "get user"
- Add "traits" filter to "get character"

**2.25**

- Add "tags" filter to "get vn"
- Increased connection limit per IP from 5 to 10
- Increased command limit from 100 to 200 commands per 10 minutes
- Added support for TLS
- Added "screens" flag and member to "get vn"
- Added "vns" flag and member to "get character"
- Allow sorting "get vn" on popularity, rating and votecount
- Added basic "get user" command
- Added "official" field to "get vn relations"

**2.23**

- Added new 'dbstats' command
- Added new 'get' types: character, votelist, vnlist and wishlist
- Added 'set' command, with types: votelist, vnlist and wishlist
- New error id: 'settype'
- Added "tags" flag and member to "get vn"
- Added "stats" flag to "get vn"
- Added "firstchar" filter to "get vn"
- Added "vn" filter to "get character"

**2.15**

- Fixed a bug with the server not allowing extra whitespace after a "get .. " command
- Allow non-numbers as "clientver" for the login command
- Added "image\_nsfw" member to "get vn"
- Added "results" option to the "get .. {<options>}"
- Increased the maximum number of results for the "get .." command to 25
- Added "orig\_lang" member and filter to the "get vn .." command
- Throttle the commands and sqltime per IP instead of per user
- Removed the limit on the number of open sessions per user
- Allow the API to be used without logging in with a username/password

**2.12**

- Added "image" member to "get vn"
- A few minor fixes in some error messages
- Switched to a different (and faster) search algorithm for "get vn .. (search ~ ..)"
