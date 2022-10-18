package VNWeb::API::Index;

use v5.26;
use warnings;
use TUWF;
use Time::HiRes 'time', 'alarm';
use VNDB::Config;
use VNDB::Func;
use VNWeb::DB;
use VNWeb::Validation;
use VNWeb::AdvSearch;

return 1 if $main::NOAPI;


TUWF::get qr{/api/kana}, sub {
    state $data = do {
        open my $F, '<', config->{root}.'/static/g/api-kana.html' or die $!;
        local $/=undef;
        my $url = config->{api_endpoint}||tuwf->reqURI;
        <$F> =~ s/%endpoint%/$url/rg;
    };
    tuwf->resHeader('Content-Type' => "text/html; charset=UTF-8");
    tuwf->resBinary($data, 'auto');
};


TUWF::options qr{/api/kana.*}, sub {
    tuwf->resStatus(204);
    tuwf->resHeader('Access-Control-Allow-Origin', '*');
    tuwf->resHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
    tuwf->resHeader('Access-Control-Allow-Headers', 'Content-Type');
    tuwf->resHeader('Access-Control-Max-Age', 86400);
};



# Production API is currently running as a single process, so we can safely and
# efficiently keep the throttle state as a local variable.
# This throttle state only handles execution time limiting; request limiting
# is done in nginx.
my %throttle; # IP -> SQL time
my $throttle_start;

sub add_throttle {
    my $now = time;
    my $time = $now - $throttle_start;
    my $norm = norm_ip tuwf->reqIP();
    $throttle{$norm} = $now if !$throttle{$norm} || $throttle{$norm} < $now;
    $throttle{$norm} += $time * config->{api_throttle}[0];
    $time;
}

sub check_throttle {
    $throttle_start = time;
    err(429, 'Throttled on query execution time.')
        if ($throttle{ norm_ip tuwf->reqIP }||0) >= time + (config->{api_throttle}[0] * config->{api_throttle}[1]);
}

sub err {
    my($status, $msg) = @_;
    my $time = add_throttle;
    tuwf->resStatus($status);
    tuwf->resHeader('Content-type', 'text');
    print { tuwf->resFd } $msg, "\n";
    tuwf->log(sprintf '%4dms [%s] %d %s "%s"', $time, tuwf->reqIP(), $status, $msg, tuwf->reqHeader('user-agent')||'');
    tuwf->done;
}

sub count_request {
    my($rows, $call) = @_;
    close tuwf->resFd;
    my $time = add_throttle;
    tuwf->log(sprintf '%4dms %3dr%6db [%s] %s "%s"',
        $time*1000, $rows, length(tuwf->{_TUWF}{Res}{content}),
        tuwf->reqIP(), $call, tuwf->reqHeader('user-agent')||'-'
    );
}


sub api_get {
    my($path, $schema, $sub) = @_;
    my $s = tuwf->compile({ type => 'hash', keys => $schema });
    TUWF::get qr{/api/kana\Q$path}, sub {
        check_throttle;
        my $start = time;
        my $res = $sub->();
        $s->analyze->coerce_for_json($res, unknown => 'reject');
        tuwf->resJSON($res);
        tuwf->resHeader('Access-Control-Allow-Origin', '*') if tuwf->reqHeader('Origin');
        count_request(1, '-');
    };
}


# %opt:
#   filters => AdvSearch query type
#   sql => sub { sql 'SELECT id', $_[0], 'FROM x', $_[1], 'WHERE', $_[2] },
#       Main query to fetch items,
#           $_[0] is the list of fields to fetch (including a preceding comma)
#           $_[1] is a list of JOIN clauses
#           $_[2] the filters for in the WHERE clause
#           $_[3] points to the request parameters
#       'ORDER BY' and 'LIMIT' clauses are appended to the returned query.
#       Query must always return a column named 'id'.
#   joins => {
#       $name => $sql,
#       # List of optional JOIN clauses that can be referenced by fields.
#       # These should always be 1-to-1 joins, i.e. no filtering or expansion may take place.
#   },
#   fields => {
#       $name => { %field_definition },
#   },
#   sort => [
#       $name => $sql,
#           SQL may include '?o' and '!o' placeholders, see TableOpts.pm.
#       First sort option listed is the default.
#   ],
#
# %field_definition for simple fields:
#   select => 'SQL string',
#   col    => 'name',  # Name of the column returned by 'SQL string',
#                      # if it does not match the $name of the field.
#   join   => 'name',  # This field requires a JOIN clause, refers to the 'joins' list above.
#   proc   => sub {},  # Subroutine to do some formatting/processing of the value.
#                      #   $_[0] is the value as returned from the DB, should be modified in-place.
#
# %field_definition for nested 1-to-1 objects:
#   fields => {},    # Same as the parents' "fields" definitions.
#                    # Can only be used to nest simple fields at a single level.
#   nullif => 'SQL string',
#                    # The entire object itself is set to null if this SQL value is true.
#                    # The SQL string must return a column named "${fieldname}_nullif}".
#
# %field_definition for nested 1-to-many objects:
#   enrich   => sub { sql 'SELECT id', $_[0], 'FROM x', $_[1], 'WHERE id IN', $_[2] },
#                # Subroutine that returns an SQL statement
#                #    $_[0] is the list of fields to fetch
#                #    $_[1] is a list of JOIN clauses
#                #    $_[2] is a list of identifiers to fetch
#                #    $_[3] points to the request parameters
#   key      => 'id',  # $key argument to enrich()
#   col      => 'id',  # $merge_col argument to enrich()
#   select   => 'SQL', # SQL to return $key, if it's not already part of the object.
#                      # (The $key will then not be included in the output)
#   atmostone=> 1,     # If this is a 1-to-[01] relation, removes the array in JSON output
#                      # and sets the object to null if there's no result.
#   joins    => {},    # Nested join definitions
#   fields   => {},    # Nested field definitions
#   inherit  => '/path'# Inherit joins+fields from another API.
#   proc     => sub {} # Subroutine to do processing on the final value.
#   num      => 1,     # Estimate of the number of objects that will be returned.
sub api_query {
    my($path, %opt) = @_;

    state %objs;
    $objs{$path} = \%opt;

    my %sort = $opt{sort}->@*;
    my $req_schema = tuwf->compile({ type => 'hash', unknown => 'reject', keys => {
        filters => { required => 0, advsearch => $opt{filters} },
        fields => { required => 0, default => {}, func => sub { parse_fields($opt{fields}, $_[0]) } },
        sort => { required => 0, default => $opt{sort}[0], enum => [ keys %sort ] },
        reverse => { required => 0, default => 0, jsonbool => 1 },
        results => { required => 0, default => 10, uint => 1, range => [0,100] },
        page => { required => 0, default => 1, uint => 1, range => [1,1e6] },
        count => { required => 0, default => 0, jsonbool => 1 },
        user => { required => 0, vndbid => 'u' },
        compact_filters => { required => 0, default => 0, jsonbool => 1 },
        normalized_filters => { required => 0, default => 0, jsonbool => 1 },
        time => { required => 0, default => 0, jsonbool => 1 },
    }});

    TUWF::post qr{/api/kana\Q$path}, sub {
        # Resolve all 'inherit' fields on first API hit.
        state $inherit_done = (sub {
            for my $f (values $_[0]->%*) {
                if($f->{inherit}) {
                    my $o = $objs{$f->{inherit}};
                    $f->{fields}{$_} = $o->{fields}{$_} for keys %{ $o->{fields}||{} };
                    $f->{joins}{$_} = $o->{joins}{$_} for keys %{ $o->{joins}||{} };
                }
                __SUB__->($f->{fields}, $_[1]) if $f->{fields} && !$_[1]{$f}++;
            }
        })->($opt{fields}, {});

        check_throttle;
        tuwf->req->{advsearch_uid} = eval { tuwf->reqJSON->{user} };
        my $req = tuwf->validate(json => $req_schema);
        if(!$req) {
            eval { $req->data }; warn $@;
            my($err) = $req->err->{errors} ? $req->err->{errors}->@* : ();
            err 400, "Invalid '$err->{key}' member: $err->{msg}" if $err->{key} && $err->{msg};
            err 400, "Invalid '$err->{key}' member." if $err->{key};
            err 400, 'Invalid query.';
        };
        $req = $req->data;

        my $numfields = count_fields($opt{fields}, $req->{fields}, $req->{results});
        err 400, sprintf 'Too much data selected (estimated %.0f fields)', $numfields if $numfields > 100_000;

        my $sort = $sort{$req->{sort}};
        my $order = $req->{reverse} ? 'DESC' : 'ASC';
        my $opposite_order = $req->{reverse} ? 'ASC' : 'DESC';
        $sort = $sort =~ /[?!]o/ ? ($sort =~ s/\?o/$order/rg =~ s/!o/$opposite_order/rg) : "$sort $order";

        my($select, $joins) = prepare_fields($opt{fields}, $opt{joins}, $req->{fields});

        my($results,$more,$count);
        eval {
            local $SIG{ALRM} = sub { die "Timeout\n"; };
            alarm 3;
            ($results, $more) = $req->{results} == 0 ? ([], 0) :
                tuwf->dbPagei($req, $opt{sql}->($select, $joins, $req->{filters}->sql_where(), $req), 'ORDER BY', $sort);
            $count = $req->{count} && (
                !$more && $req->{results} && @$results <= $req->{results} ? ($req->{results}*($req->{page}-1))+@$results :
                tuwf->dbVali('SELECT count(*) FROM (', $opt{sql}->('', '', $req->{filters}->sql_where), ') x')
            );
            proc_results($opt{fields}, $req->{fields}, $req, $results);
            alarm 0;
            1;
        } || do {
            alarm 0;
            err 500, 'Processing timeout' if $@ =~ /^Timeout/ || $@ =~ /canceling statement due to statement timeout/;
            die $@;
        };

        tuwf->resJSON({
            results => $results,
            more => $more?\1:\0,
            $req->{count} ? (count => $count) : (),
            $req->{compact_filters} ? (compact_filters => $req->{filters}->query_encode) : (),
            $req->{normalized_filters} ? (normalized_filters => $req->{filters}->json) : (),
            $req->{time} ? (time => int(1000*(time()-$throttle_start))) : (),
        });
        tuwf->resHeader('Access-Control-Allow-Origin', '*') if tuwf->reqHeader('Origin');
        count_request(scalar @$results, sprintf '[%s] {%s %s r%dp%d} %s', fmt_fields($req->{fields}),
            $req->{sort}, $req->{reverse}?'asc':'desc', $req->{results}, $req->{page},
            $req->{filters}->query_encode()||'-');
    };
}


sub parse_fields {
    my @tokens = split /\s*([,.{}])\s*/, $_[1];
    $_[1] = {};
    return (sub {
        my($lvl, $f, $out) = @_;
        my $nf = $f;
        my $of = $out;
        while(defined (my $t = shift @tokens)) {
            next if !length $t;
            if($t eq '}') {
                return { msg => "Expected (sub)field, got '}'" } if $nf;
                return $lvl > 0 ? 1 : { msg => "Unmatched '}'" } ;
            } elsif($t eq '{') {
                return { msg => "Unexpected '{' after non-object field" } if !$nf;
                my $r = __SUB__->($lvl+1, $nf, $of);
                return $r if ref $r;
                ($nf, $of) = ();
            } elsif($t eq ',') {
                return { msg => 'Expected (sub)field, got comma' } if $nf;
                ($nf, $of) = ($f, $out);
            } else {
                return { msg => 'Unexpected (sub)field after non-object field' } if !$nf;
                if($t eq '.') {
                    $t = shift(@tokens) // return { msg => "Expected name after '.'" };
                }
                my $d = $nf->{$t} // return { msg => "Field '$t' not found", name => $t };
                $nf = $d->{fields};
                $of->{$t} ||= {};
                $of = $of->{$t};
            }
        }
        return { msg => "Expected sub-field" } if $nf;
        return $lvl > 0 ? { msg => "Unmatched '{'" } : 1;
    })->(0, $_[0], $_[1]);
}

sub fmt_fields {
    (sub {
        join ',', map $_ . (
            keys $_[0]{$_}->%* == 0 ? '' :
            keys $_[0]{$_}->%* == 1 ? '.'.__SUB__->($_[0]{$_}) : '{'.__SUB__->($_[0]{$_}).'}'
        ), sort keys $_[0]->%*;
    })->($_[0]);
}


# Calculate an estimate of how many fields will be returned in the response,
# based on which fields are enabled.
sub count_fields {
    my($fields, $enabled, $num) = @_;
    my $n = ($fields->{id} && !$enabled->{id} ? 1 : 0) + keys %$enabled;
    $n += count_fields($fields->{$_}{fields}, $enabled->{$_}, $fields->{$_}{num})
        for (grep $fields->{$_}{fields}, keys %$enabled);
    $n * ($num // 1);
}


sub prepare_fields {
    my($fields, $joins, $enabled) = @_;
    my(@select, %join);
    (sub {
        for my $f (keys $_[1]->%*) {
            my $d = $_[0]{$f};
            $join{$d->{join}} = 1 if $d->{join};
            push @select, $d->{select} if $d->{select};
            push @select, $d->{nullif} if $d->{nullif};
            __SUB__->($d->{fields}, $_[1]{$f}) if $d->{fields} && !$d->{enrich};
        }
    })->($fields, $enabled);
    return (
        join('', map ",$_", @select),
        join(' ', map $joins->{$_}, keys %join),
    );
}


sub proc_field {
    my($n, $d, $obj, $out) = @_;
    $out->{$n} = delete $obj->{$d->{col}} if $d->{col};
    $d->{proc}->($out->{$n}) if $d->{proc};
}


sub proc_results {
    my($fields, $enabled, $req, $results) = @_;
    for my $f (keys %$enabled) {
        my $d = $fields->{$f};

        # nested 1-to-many objects
        if($d->{enrich}) {
            my($select, $join) = prepare_fields($d->{fields}, $d->{joins}, $enabled->{$f});
            # DB::enrich() logic has been duplicated here to allow for
            # efficient handling of nested proc_results() and `atmostone`.
            my %ids = map defined($_->{$d->{key}}) ? ($_->{$d->{key}},[]) : (), @$results;
            my $rows = keys %ids ? tuwf->dbAlli($d->{enrich}->($select, $join, [keys %ids], $req)) : [];
            proc_results($d->{fields}, $enabled->{$f}, $req, $rows);
            push $ids{ delete $_->{$d->{col}} }->@*, $_ for @$rows;
            if($d->{atmostone}) {
                if($d->{select}) { $_->{$f} = $ids{ delete $_->{$d->{key}} // '' }[0] for @$results }
                else             { $_->{$f} = $ids{        $_->{$d->{key}} // '' }[0] for @$results }
            } else {
                if($d->{select}) { $_->{$f} = $ids{ delete $_->{$d->{key}} // '' }||[] for @$results }
                else             { $_->{$f} = $ids{        $_->{$d->{key}} // '' }||[] for @$results }
            }
            $d->{proc}->($_->{$f}) for $d->{proc} ? @$results : ();

        # nested 1-to-1 objects
        } elsif($d->{fields}) {
            for my $o (@$results) {
                if($d->{nullif} && delete $o->{"${f}_nullif"}) {
                    $o->{$f} = undef;
                    delete $o->{ $d->{fields}{$_}{col}||$_ } for keys $enabled->{$f}->%*;
                } else {
                    $o->{$f} = {};
                    proc_field($_, $d->{fields}{$_}, $o, $o->{$f}) for keys $enabled->{$f}->%*;
                }
            }

        # simple fields
        } else {
            proc_field($f, $d, $_, $_) for @$results;
        }
    }
}


my @STATS = qw{traits producers tags chars staff vn releases};
api_get '/stats', { map +($_, { uint => 1 }), @STATS }, sub {
    +{ map +($_->{section}, $_->{count}),
        tuwf->dbAlli('SELECT * FROM stats_cache WHERE section IN', \@STATS)->@* };
};



my @BOOL = (proc => sub { $_[0] = $_[0] ? \1 : \0 if defined $_[0] });
my @INT = (proc => sub { $_[0] *= 1 if defined $_[0] }); # Generally unnecessary, DBD::Pg does this already
my @RDATE = (proc => sub { $_[0] = $_[0] ? rdate $_[0] : undef });
my @NSTR = (proc => sub { $_[0] = undef if !length $_[0] }); # Empty string -> null
my @MSTR = (proc => sub { $_[0] = [ grep length($_), split /\n/, $_[0] ] }); # Multiline string -> array
my @NINT = (proc => sub { $_[0] = $_[0] ? $_[0]*1 : undef });  # 0 -> null

sub IMG {
    my($main_col, $join_id, $join_prefix) = @_;
    return (
        id        => { select => "$main_col AS image_id", col => 'image_id' },
        url       => { select => "$main_col AS image_url", col => 'image_url', proc => sub { $_[0] = imgurl $_[0] } },
        dims      => { join => $join_id, col => 'image_dims', select => "ARRAY[${join_prefix}width, ${join_prefix}height] AS image_dims" },
        sexual    => { join => $join_id, select => "${join_prefix}c_sexual_avg::real/100 AS image_sexual", col => 'image_sexual' },
        violence  => { join => $join_id, select => "${join_prefix}c_violence_avg::real/100 AS image_violence", col => 'image_violence' },
        votecount => { join => $join_id, select => "${join_prefix}c_votecount AS image_votecount", col => 'image_votecount' },
    );
}


api_query '/vn',
    filters => 'v',
    sql => sub { sql 'SELECT v.id', $_[0], 'FROM vnt v', $_[1], 'WHERE NOT v.hidden AND (', $_[2], ')' },
    joins => {
        image => 'LEFT JOIN images i ON i.id = v.image',
    },
    fields => {
        id => {},
        title => { select => 'v.title' },
        alttitle => { select => 'v.alttitle' },
        titles => {
            enrich => sub { sql 'SELECT vt.id', $_[0], 'FROM vn_titles vt', $_[1], 'WHERE vt.id IN', $_[2] },
            key => 'id', col => 'id', num => 3,
            joins => {
                main => 'JOIN vn v ON v.id = vt.id',
            },
            fields => {
                lang  => { select => 'vt.lang' },
                title => { select => 'vt.title' },
                latin => { select => 'vt.latin' },
                official => { select => 'vt.official', @BOOL },
                main => { join => 'main', select => 'vt.lang = v.olang AS main', @BOOL },
            },
        },
        aliases => { select => 'v.alias AS aliases', @MSTR },
        olang => { select => 'v.olang' },
        devstatus => { select => 'v.devstatus' },
        released => { select => 'v.c_released AS released', @RDATE },
        languages => { select => 'v.c_languages::text[] AS languages' },
        platforms => { select => 'v.c_platforms::text[] AS platforms' },
        image => {
            fields => { IMG 'v.image', 'image', 'i.' },
            nullif => 'v.image IS NULL AS image_nullif',
        },
        length => { select => 'v.length', proc => sub { $_[0] = undef if !$_[0] } },
        length_minutes => { select => 'v.c_length AS length_minutes' },
        length_votes => { select => 'v.c_lengthnum AS length_votes' },
        description => { select => 'v.desc AS description', @NSTR },
        rating      => { select => 'v.c_rating AS rating', proc => sub { $_[0] /= 10 if defined $_[0] } },
        popularity  => { select => 'v.c_popularity AS popularity', proc => sub { $_[0] /= 100 if defined $_[0] } },
        votecount   => { select => 'v.c_votecount AS votecount' },
        screenshots => {
            enrich => sub { sql 'SELECT vs.id AS vid', $_[0], 'FROM vn_screenshots vs', $_[1], 'WHERE vs.id IN', $_[2] },
            key => 'id', col => 'vid', num => 10,
            joins => {
                image => 'JOIN images i ON i.id = vs.scr',
            },
            fields => {
                IMG('vs.scr', 'image', 'i.'),
                thumbnail => { select => "vs.scr AS thumbnail", col => 'thumbnail', proc => sub { $_[0] = imgurl $_[0], 1 } },
                thumbnail_dims => { join => 'image', col => 'thumbnail_dims'
                                  , select => "ARRAY[i.width, i.height] AS thumbnail_dims"
                                  , proc => sub { @{$_[0]} = imgsize @{$_[0]}, config->{scr_size}->@* } },
                release => {
                    select => 'vs.rid AS screen_rid',
                    enrich => sub { sql 'SELECT r.id AS screen_rid, r.id', $_[0], 'FROM releasest r', $_[1], 'WHERE NOT r.hidden AND r.id IN', $_[2] },
                    key => 'screen_rid', col => 'screen_rid', atmostone => 1,
                    inherit => '/release',
                }
            },
        },
        tags => {
            enrich => sub { sql 'SELECT tv.vid, t.id', $_[0], 'FROM tags_vn_direct tv JOIN tags t ON t.id = tv.tag', $_[1], 'WHERE tv.vid IN', $_[2] },
            key => 'id', col => 'vid', num => 50,
            inherit => '/tag',
            fields => {
                rating   => { select => 'tv.rating' },
                spoiler  => { select => 'tv.spoiler' },
                lie      => { select => 'tv.lie', @BOOL },
            },
        },
    },
    sort => [
        id => 'v.id',
        title => 'v.sorttitle ?o, v.id',
        released => 'v.c_released ?o, v.id',
        popularity => 'v.c_pop_rank !o NULLS LAST, v.id',
        rating => 'v.c_rat_rank !o NULLS LAST, v.id',
        votecount => 'v.c_votecount ?o, v.id',
    ];


api_query '/release',
    filters => 'r',
    sql => sub { sql 'SELECT r.id', $_[0], 'FROM releasest r', $_[1], 'WHERE NOT r.hidden AND (', $_[2], ')' },
    fields => {
        id       => {},
        title    => { select => 'r.title' },
        alttitle => { select => 'r.alttitle' },
        languages => {
            enrich => sub { sql 'SELECT rt.id', $_[0], 'FROM releases_titles rt', $_[1], 'WHERE rt.id IN', $_[2] },
            key => 'id', col => 'id', num => 3,
            joins => {
                main => 'JOIN releases r ON r.id = rt.id',
            },
            fields => {
                lang  => { select => 'rt.lang' },
                title => { select => 'rt.title' },
                latin => { select => 'rt.latin' },
                mtl   => { select => 'rt.mtl', @BOOL },
                main  => { join => 'main', select => 'rt.lang = r.olang AS main', @BOOL },
            },
        },
        platforms => {
            enrich => sub { sql 'SELECT id, platform FROM releases_platforms WHERE id IN', $_[2] },
            key => 'id', col => 'id', proc => sub { $_[0] = [ map $_->{platform}, $_[0]->@* ] },
        },
        media => {
            enrich => sub { sql 'SELECT id', $_[0], 'FROM releases_media WHERE id IN', $_[2] },
            key => 'id', col => 'id', num => 3,
            fields => {
                medium => { select => 'medium' },
                qty => { select => 'qty' },
            },
        },
        vns => {
            enrich => sub { sql 'SELECT rv.id AS rid, v.id', $_[0], 'FROM releases_vn rv JOIN vnt v ON v.id = rv.vid', $_[1], 'WHERE rv.id IN', $_[2] },
            key => 'id', col => 'rid', num => 3,
            inherit => '/vn',
            fields => {
                rtype => { select => 'rv.rtype' },
            },
        },
        producers  => {
            enrich => sub { sql 'SELECT rp.id AS rid, p.id', $_[0], 'FROM releases_producers rp JOIN producers p ON p.id = rp.pid', $_[1], 'WHERE rp.id IN', $_[2] },
            key => 'id', col => 'rid', num => 3,
            inherit => '/producer',
            fields => {
                developer => { select => 'rp.developer', @BOOL },
                publisher => { select => 'rp.publisher', @BOOL },
            },
        },
        released   => { select => 'r.released', @RDATE },
        minage     => { select => 'r.minage' },
        patch      => { select => 'r.patch', @BOOL },
        freeware   => { select => 'r.freeware', @BOOL },
        uncensored => { select => 'r.uncensored', @BOOL },
        official   => { select => 'r.official', @BOOL },
        has_ero    => { select => 'r.has_ero', @BOOL },
        resolution => { select => 'ARRAY[r.reso_x,r.reso_y] AS resolution'
                      , proc => sub { $_[0] = $_[0][1] == 0 ? undef : 'non-standard' if $_[0][0] == 0 } },
        engine     => { select => 'r.engine', @NSTR },
        notes      => { select => 'r.notes', @NSTR },
    },
    sort => [
        id       => 'r.id',
        title    => 'r.sorttitle ?o, r.id',
        released => 'r.released ?o, r.id',
    ];


api_query '/producer',
    filters => 'p',
    sql => sub { sql 'SELECT p.id', $_[0], 'FROM producers p', $_[1], 'WHERE NOT p.hidden AND (', $_[2], ')' },
    fields => {
        id       => {},
        name     => { select => 'p.name' },
        original => { select => 'p.original', @NSTR },
        aliases  => { select => 'p.alias AS aliases', @MSTR },
        lang     => { select => 'p.lang' },
        type     => { select => 'p.type' },
        description => { select => 'p.desc AS description', @NSTR },
    },
    sort => [
        id       => 'p.id',
        name     => 'p.name ?o, p.id',
    ];


api_query '/character',
    filters => 'c',
    sql => sub { sql 'SELECT c.id', $_[0], 'FROM chars c', $_[1], 'WHERE NOT c.hidden AND (', $_[2], ')' },
    joins => {
        image => 'LEFT JOIN images i ON i.id = c.image',
    },
    fields => {
        id       => {},
        name     => { select => 'c.name' },
        original => { select => 'c.original', @NSTR },
        aliases  => { select => 'c.alias AS aliases', @MSTR },
        description => { select => 'c.desc AS description', @NSTR },
        image => {
            fields => { IMG 'c.image', 'image', 'i.' },
            nullif => 'c.image IS NULL AS image_nullif',
        },
        blood_type => { select => 'c.bloodt', proc => sub { $_[0] = undef if $_[0] eq 'unknown' } },
        height   => { select => 'c.height', @NINT },
        weight   => { select => 'c.weight' },
        bust     => { select => 'c.s_bust AS bust', @NINT },
        waist    => { select => 'c.s_waist AS waist', @NINT },
        hips     => { select => 'c.s_hip AS hips', @NINT },
        cup      => { select => 'c.cup_size AS cup', @NSTR },
        age      => { select => 'c.age' },
        vns      => {
            enrich => sub { sql 'SELECT cv.id AS cid, v.id', $_[0], 'FROM chars_vns cv JOIN vnt v ON v.id = cv.vid', $_[1], 'WHERE NOT v.hidden AND cv.id IN', $_[2] },
            key => 'id', col => 'cid', num => 3,
            inherit => '/vn',
            fields => {
                spoiler => { select => 'cv.spoil AS spoiler' },
                role    => { select => 'cv.role' },
                release => {
                    select => 'cv.rid',
                    enrich => sub { sql 'SELECT r.id AS rid, r.id', $_[0], 'FROM releasest r', $_[1], 'WHERE NOT r.hidden AND r.id IN', $_[2] },
                    key => 'rid', col => 'rid', atmostone => 1,
                    inherit => '/release',
                }
            },
        },
        traits   => {
            enrich => sub { sql 'SELECT ct.id AS cid', $_[0], 'FROM chars_traits ct JOIN traits t ON t.id = ct.tid', $_[1], 'WHERE NOT t.hidden AND ct.id IN', $_[2] },
            key => 'id', col => 'cid', num => 30,
            joins => {
                group => 'LEFT JOIN traits g ON g.id = t.group',
            },
            fields => {
                id       => { select => 'ct.tid AS id' },
                spoiler  => { select => 'ct.spoil AS spoiler' },
                name     => { select => 't.name' },
                group_id => { join => 'group', select => 't."group" AS group_id' },
                group_name=>{ join => 'group', select => 'g.name AS group_name' },
            },
        },
    },
    sort => [
        id       => 'c.id',
        name     => 'c.name ?o, c.id',
    ];


api_query '/tag',
    filters => 'g',
    sql => sub { sql 'SELECT t.id', $_[0], 'FROM tags t', $_[1], 'WHERE NOT hidden AND (', $_[2], ')' },
    fields => {
        id          => {},
        name        => { select => 't.name' },
        aliases     => { select => 't.alias AS aliases', @MSTR },
        description => { select => 't.description' },
        category    => { select => 't.cat AS category' },
        searchable  => { select => 't.searchable', @BOOL },
        applicable  => { select => 't.applicable', @BOOL },
        vn_count    => { select => 't.c_items AS vn_count' },
    },
    sort => [
        id       => 't.id',
        name     => 't.name',
        vn_count => 't.c_items ?o, t.id',
    ];


api_query '/ulist',
    filters => 'v',
    sql => sub {
        err 400, 'Missing "user" parameter.' if !$_[3]{user};
        sql 'SELECT v.id', $_[0], '
               FROM ulist_vns uv
               JOIN vnt v ON v.id = uv.vid', $_[1], '
              WHERE NOT v.hidden
                AND uv.uid =', \$_[3]{user}, '
                AND EXISTS(SELECT 1 FROM ulist_vns_labels uvl JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
                            WHERE uvl.uid = uv.uid AND uvl.vid = uv.vid AND NOT ul.private)
                AND (', $_[2], ')'
    },
    fields => {
        id       => {},
        added    => { select => "extract('epoch' from uv.added)::bigint AS added" },
        lastmod  => { select => "extract('epoch' from uv.lastmod)::bigint AS lastmod" },
        voted    => { select => "extract('epoch' from uv.vote_date)::bigint AS voted" },
        vote     => { select => 'uv.vote' },
        started  => { select => 'uv.started' },
        finished => { select => 'uv.finished' },
        notes    => { select => 'uv.notes', @NSTR },
        labels   => {
            enrich => sub { sql 'SELECT uvl.vid', $_[0], '
                                   FROM ulist_vns_labels uvl
                                   JOIN ulist_labels ul ON ul.uid = uvl.uid AND ul.id = uvl.lbl
                                  WHERE uvl.uid =', \$_[3]{user}, 'AND ul.uid =', \$_[3]{user}, '
                                    AND NOT ul.private
                                    AND uvl.vid IN', $_[2] },
            key => 'id', col => 'vid', num => 3,
            fields => {
                id    => { select => 'ul.id' },
                label => { select => 'ul.label' },
            },
        },
        vn       => {
            enrich => sub { sql 'SELECT v.id', $_[0], 'FROM vnt v', $_[1], 'WHERE v.id IN', $_[2] },
            key => 'id', col => 'id', atmostone => 1, inherit => '/vn',
        },
        releases => {
            enrich => sub { sql 'SELECT irv.vid, r.id', $_[0], '
                                   FROM rlists rl
                                   JOIN releasest r ON rl.rid = r.id', $_[1], '
                                   JOIN (SELECT DISTINCT id, vid FROM releases_vn rv WHERE rv.vid IN', $_[2], ') AS irv(id,vid) ON rl.rid = irv.id
                                  WHERE NOT r.hidden
                                    AND rl.uid =', \$_[3]{user} },
            key => 'id', col => 'vid', num => 3, inherit => '/release',
            fields => {
                list_status => { select => 'rl.status AS list_status' },
            },
        },
    },
    sort => [
        id         => 'v.id',
        title      => 'v.sorttitle ?o, v.id',
        released   => 'v.c_released ?o, v.id',
        popularity => 'v.c_pop_rank !o NULLS LAST, v.id',
        rating     => 'v.c_rat_rank !o NULLS LAST, v.id',
        votecount  => 'v.c_votecount ?o, v.id',
        voted      => 'uv.vote_date ?o, v.id',
        vote       => 'uv.vote ?o, v.id',
        added      => 'uv.added',
        lastmod    => 'uv.lastmod',
        started    => 'uv.started ?o, v.id',
        finished   => 'uv.finished ?o, v.id',
    ];

1;
