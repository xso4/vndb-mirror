package VNWeb::API::Index;

use v5.26;
use warnings;
use TUWF;
use Time::HiRes 'time';
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
        my $url = tuwf->reqURI;
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


# TODO: accounting, this function only logs for now.
# Should be called after resJSON so we have output stats.
sub count_request {
    my($start, $rows, $call) = @_;
    tuwf->resFd->flush;
    my $time = time-$start;
    tuwf->log(sprintf '%4dms %3dr%6db [%s] %s "%s"',
        $time*1000, $rows, length(tuwf->{_TUWF}{Res}{content}),
        tuwf->reqIP(), $call, tuwf->reqHeader('user-agent')||'-'
    );
}


sub err {
    my($status, $msg) = @_;
    tuwf->resStatus($status);
    tuwf->resHeader('Content-type', 'text');
    print { tuwf->resFd } $msg, "\n";
    tuwf->done;
}


sub api_get {
    my($path, $schema, $sub) = @_;
    my $s = tuwf->compile({ type => 'hash', keys => $schema });
    TUWF::get qr{/api/kana\Q$path}, sub {
        my $start = time;
        my $res = $sub->();
        $s->analyze->coerce_for_json($res, unknown => 'reject');
        tuwf->resJSON($res);
        tuwf->resHeader('Access-Control-Allow-Origin', '*') if tuwf->reqHeader('Origin');
        count_request($start, 1, '-');
    };
}


# %opt:
#   filters => AdvSearch query type
#   sql => sub { sql 'SELECT id', $_[0], 'FROM x', $_[1], 'WHERE', $_[2] },
#       Main query to fetch items,
#           $_[0] is the list of fields to fetch (including a preceding comma)
#           $_[1] is a list of JOIN clauses
#           $_[2] the filters for in the WHERE clause
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
#   enrich => sub { sql('SELECT id', $_[0], 'FROM x', $_[1], 'WHERE id IN') },
#             # Subroutine that returns the $sql argument to enrich()
#             #    $_[0] is the list of fields to fetch
#             #    $_[1] is a list of JOIN clauses
#   key    => 'id',  # $key argument to enrich()
#   col    => 'id',  # $merge_col argument to enrich()
#   joins  => {},    # Nested join definitions
#   fields => {},    # Nested field definitions
sub api_query {
    my($path, %opt) = @_;

    my %sort = $opt{sort}->@*;
    my $req_schema = tuwf->compile({ type => 'hash', keys => {
        filters => { required => 0, advsearch => $opt{filters} },
        fields => { required => 0, default => '', func => sub { parse_fields($opt{fields}, $_[0]) } },
        sort => { required => 0, default => $opt{sort}[0], enum => [ keys %sort ] },
        reverse => { required => 0, default => 0, jsonbool => 1 },
        results => { required => 0, default => 10, uint => 1, range => [1,100] },
        page => { required => 0, default => 1, uint => 1, range => [1,1e6] },
        count => { required => 0, default => 0, jsonbool => 1 },
        compact_filters => { required => 0, default => 0, jsonbool => 1 },
        normalized_filters => { required => 0, default => 0, jsonbool => 1 },
    }});

    TUWF::post qr{/api/kana\Q$path}, sub {
        my $start = time;
        # First make sure to reset any existing 'enabled' flags from a previous call,
        # so these can be filled again with parse_fields() during validation.
        # Writing directly to our config structure is a bit ugly, but at least it's simple and efficient.
        (sub {
            $_->{enabled} && (do{$_->{enabled} = 0} || $_->{fields}) && __SUB__->($_->{fields}) for values $_[0]->%*;
        })->($opt{fields});

        my $req = tuwf->validate(json => $req_schema);
        if(!$req) {
            eval { $req->data }; warn $@;
            my($err) = $req->err->{errors} ? $req->err->{errors}->@* : ();
            err 400, "Invalid '$err->{key}' member: $err->{msg}" if $err->{key} && $err->{msg};
            err 400, "Invalid '$err->{key}' member." if $err->{key};
            err 400, 'Invalid query.';
        };
        $req = $req->data;

        my $sort = $sort{$req->{sort}};
        my $order = $req->{reverse} ? 'DESC' : 'ASC';
        my $opposite_order = $req->{reverse} ? 'ASC' : 'DESC';
        $sort = $sort =~ /[?!]o/ ? ($sort =~ s/\?o/$order/rg =~ s/!o/$opposite_order/rg) : "$sort $order";

        my($select, $joins) = prepare_fields($opt{fields}, $opt{joins});

        # TODO: Handle query timeouts
        my($results, $more) = tuwf->dbPagei($req, $opt{sql}->($select, $joins, $req->{filters}->sql_where), 'ORDER BY', $sort);
        my $count = $req->{count} && tuwf->dbVali('SELECT count(*) FROM (', $opt{sql}->('', '', $req->{filters}->sql_where), ') x');

        proc_results($opt{fields}, $results);

        tuwf->resJSON({
            results => $results,
            more => $more?\1:\0,
            $req->{count} ? (count => $count) : (),
            $req->{compact_filters} ? (compact_filters => $req->{filters}->query_encode) : (),
            $req->{normalized_filters} ? (normalized_filters => $req->{filters}->json) : (),
        });
        tuwf->resHeader('Access-Control-Allow-Origin', '*') if tuwf->reqHeader('Origin');
        count_request($start, scalar @$results, sprintf '[%s] {%s %s r%dp%d} %s', $req->{fields},
            $req->{sort}, $req->{reverse}?'asc':'desc', $req->{results}, $req->{page},
            $req->{filters}->query_encode()||'-');
    };
}


sub parse_fields {
    my @tokens = split /\s*([,.{}])\s*/, $_[1];
    return (sub {
        my($lvl, $f) = @_;
        my $nf = $f;
        while(defined (my $t = shift @tokens)) {
            next if !length $t;
            if($t eq '}') {
                return { msg => "Expected (sub)field, got '}'" } if $nf;
                return $lvl > 0 ? 1 : { msg => "Unmatched '}'" } ;
            } elsif($t eq '{') {
                return { msg => "Unexpected '{' after non-object field" } if !$nf;
                my $r = __SUB__->($lvl+1, $nf);
                return $r if ref $r;
                $nf = undef;
            } elsif($t eq ',') {
                return { msg => 'Expected (sub)field, got comma' } if $nf;
                $nf = $f;
            } else {
                return { msg => 'Unexpected (sub)field after non-object field' } if !$nf;
                if($t eq '.') {
                    $t = shift(@tokens) // return { msg => "Expected name after '.'" };
                }
                my $d = $nf->{$t} // return { msg => "Field not found", name => $t };
                $d->{enabled} = 1;
                $nf = $d->{fields};
            }
        }
        return { msg => "Expected sub-field" } if $nf;
        return $lvl > 0 ? { msg => "Unmatched '{'" } : 1;
    })->(0, $_[0]);
}


sub prepare_fields {
    my($fields, $joins) = @_;
    my(@select, %join);
    (sub {
        for my $f (keys $_[0]->%*) {
            my $d = $_[0]{$f};
            next if !$d->{enabled};
            $join{$d->{join}} = 1 if $d->{join};
            push @select, $d->{select} if $d->{select};
            push @select, $d->{nullif} if $d->{nullif};
            __SUB__->($d->{fields}) if $d->{fields} && !$d->{enrich};
        }
    })->($fields);
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
    my($fields, $results) = @_;
    for my $f (keys %$fields) {
        my $d = $fields->{$f};
        next if !$d->{enabled};

        # nested 1-to-many objects
        if($d->{enrich}) {
            my($select, $join) = prepare_fields($d->{fields}, $d->{joins});
            enrich $f, $d->{key}, $d->{col}, $d->{enrich}->($select, $join), $results;
            proc_results($d->{fields}, [map $_->{$f}->@*, @$results]);

        # nested 1-to-1 objects
        } elsif($d->{fields}) {
            for my $o (@$results) {
                if($d->{nullif} && delete $o->{"${f}_nullif"}) {
                    $o->{$f} = undef;
                    delete $o->{ $d->{fields}{$_}{col}||$_ } for (keys $d->{fields}->%*);
                } else {
                    $o->{$f} = {};
                    proc_field($_, $d->{fields}{$_}, $o, $o->{$f})
                        for grep $d->{fields}{$_}{enabled}, keys $d->{fields}->%*;
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
my @INT = (proc => sub { $_[0] *= 1 if defined $_[0] });
my @RDATE = (proc => sub { $_[0] = $_[0] ? rdate $_[0] : undef });

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
        title => { select => 'v.title' },
        alttitle => { select => 'v.alttitle' },
        titles => {
            enrich => sub { sql 'SELECT vt.id', $_[0], 'FROM vn_titles vt', $_[1], 'WHERE vt.id IN' },
            key => 'id', col => 'id',
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
        aliases => { select => 'v.alias AS aliases', proc => sub { $_[0] = [ grep length($_), split /\n/, $_[0] ] } },
        olang => { select => 'v.olang' },
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
        description => { select => 'v.desc AS description', proc => sub { $_[0] = undef if !length $_[0] } },
        screenshots => {
            enrich => sub { sql 'SELECT vs.id AS vid', $_[0], 'FROM vn_screenshots vs', $_[1], 'WHERE vs.id IN' },
            key => 'id', col => 'vid',
            joins => {
                image => 'JOIN images i ON i.id = vs.scr',
            },
            fields => {
                IMG('vs.scr', 'image', 'i.'),
                thumbnail => { select => "vs.scr AS thumbnail", col => 'thumbnail', proc => sub { $_[0] = imgurl $_[0], 1 } },
                thumbnail_dims => { join => 'image', col => 'thumbnail_dims'
                                  , select => "ARRAY[i.width, i.height] AS thumbnail_dims"
                                  , proc => sub { @{$_[0]} = imgsize @{$_[0]}, config->{scr_size}->@* } },
                # TODO: release info
            },
        },
        tags => {
            enrich => sub { sql 'SELECT tv.vid', $_[0], 'FROM tags_vn_direct tv', $_[1], 'WHERE tv.vid IN' },
            key => 'id', col => 'vid',
            joins => {
                tag => 'JOIN tags t ON t.id = tv.tag',
            },
            fields => {
                id       => { select => 'tv.tag AS id' },
                rating   => { select => 'tv.rating' },
                spoiler  => { select => 'tv.spoiler' },
                lie      => { select => 'tv.lie', @BOOL },
                name     => { join => 'tag', select => 't.name' },
                category => { join => 'tag', select => 't.cat AS category' },
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

1;
