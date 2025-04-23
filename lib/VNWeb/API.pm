package VNWeb::API;

use v5.36;
use FU;
use Time::HiRes 'time', 'alarm';
use POSIX 'strftime';
use List::Util 'min';
use VNDB::Config;
use VNDB::Func;
use VNDB::ExtLinks;
use VNDB::Types;
use VNWeb::Auth;
use VNWeb::DB;
use VNWeb::Validation;
use VNWeb::AdvSearch;
use VNWeb::ULists::Lib 'ulist_filtlabels';

return 1 if !config->{api};


sub docpage($ver) {
    state %data;
    $data{$ver} ||= do {
        open my $F, '<', config->{gen_path}.'/api-'.$ver.'.html' or die $!;
        local $/=undef;
        my $url = config->{api_endpoint} || config->{url}.fu->path;
        <$F> =~ s/%endpoint%/$url/rg;
    };
    fu->set_body($data{$ver});
};
FU::get '/api/nyan' => sub { docpage 'nyan' };
FU::get '/api/kana' => sub { docpage 'kana' };


sub cors {
    return if !fu->header('origin');
    if(fu->header('cookie') || fu->header('authorization')) {
        fu->set_header('access-control-allow-origin', fu->header('origin'));
        fu->set_header('access-control-allow-credentials', 'true');
    } else {
        fu->set_header('access-control-allow-origin', '*');
    }
}


FU::options qr{/api/kana.*}, sub {
    fu->status(204);
    fu->set_header('access-control-allow-origin', fu->header('origin'));
    fu->set_header('access-control-allow-credentials', 'true');
    fu->set_header('access-control-allow-methods', 'POST, GET, OPTIONS');
    fu->set_header('access-control-allow-headers', 'Content-Type, Authorization');
    fu->set_header('access-control-max-age', 86400);
};



# Production API is currently running as a single process, so we can safely and
# efficiently keep the throttle state as a local variable.
# This throttle state only handles execution time limiting; request limiting
# is done in nginx.
my %throttle; # IP -> SQL time

sub add_throttle {
    my $now = time;
    my $time = $now - (fu->{throttle_start}||$now);
    my $norm = norm_ip fu->ip;
    $throttle{$norm} = $now if !$throttle{$norm} || $throttle{$norm} < $now;
    $throttle{$norm} += $time * config->{api_throttle}[0];
}

sub check_throttle {
    fu->{throttle_start} = time;
    err(429, 'Throttled on query execution time.')
        if ($throttle{ norm_ip fu->ip }||0) >= time + (config->{api_throttle}[0] * config->{api_throttle}[1]);
}

sub logreq {
    return if !config->{api_logfile};
    open my $F, '>>:utf8', config->{api_logfile} or return warn "Error opening API log file: $!\n";
    printf $F qq{%sZ %s %s %s %s %4dms %s "%s" "%s"\n},
        strftime('%Y-%m-%d %H:%M:%S', gmtime), fu->ip, auth->uid||'-',
        fu->method, fu->path =~ s{^/api/kana}{}r,
        fu->{throttle_start} ? (time - fu->{throttle_start})*1000 : 0,
        $_[0],
        fu->header('origin')||'-',
        fu->header('user-agent')||'';
}

sub err($status, $msg) {
    add_throttle;
    fu->status($status);
    fu->set_header('content-type', 'text');
    fu->set_header('www-authenticate', 'Token') if $status == 401;
    cors;
    utf8::encode($msg);
    fu->set_body("$msg\n");
    logreq "$status $msg";
    fu->done;
}

sub count_request($rows, $call) {
    add_throttle;
    logreq sprintf "%3dr%6db %s", $rows, length($FU::REQ->{resbody}), $call;
}


sub api_get($path, $schema, $sub) {
    my $s = FU::Validate->compile({ keys => $schema });
    FU::get "/api/kana$path", sub {
        check_throttle;
        my $res = $sub->();
        cors;
        eval { fu->send_json($s->coerce($res, unknown => 'pass')) };
        count_request(1, '-');
    };
}


sub api_del($path, $sub) {
    FU::delete qr{/api/kana$path}, sub(@a) {
        check_throttle;
        my $del = $sub->(@a);
        fu->status(204);
        cors;
        count_request($del?1:0, '-');
    };
}


sub api_patch($path, $req_schema, $sub) {
    $req_schema->{$_}{missing} = 'ignore' for keys $req_schema->%*;
    my $s = FU::Validate->compile({ unknown => 'reject', keys => $req_schema });
    FU::patch qr{/api/kana$path}, sub(@a) {
        check_throttle;
        my $req = eval { fu->json($s) };
        if (!$req) {
            my $err = $@;
            if ($err isa 'FU::Validate::err') {
                warn +($err->errors)[0]."\n";
                err 400, $err->{keys} ? "Unknown member '$err->{keys}[0]'." : 'Invalid request body.' if !$err->{errors};
                $err = $err->{errors}[0]//{};
                err 400, "Invalid '$err->{key}' member." if $err->{key};
            }
            err 400, 'Invalid request body.';
        }

        $sub->(@a, $req);
        fu->status(204);
        cors;
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
#   search => [ $type, $id, $subid ],
#       Whether sorting on "searchrank" is available, arguments are same as SearchQuery::sql_join().
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
# %field_definition for nested 1-to-1 objects that fetch from the parent object:
#   fields => {},    # Same as the parents' "fields" definitions.
#                    # Can only be used to nest simple fields at a single level.
#   nullif => 'SQL string',
#                    # The entire object itself is set to null if this SQL value is true.
#                    # The SQL string must return a column named "${fieldname}_nullif}".
#
# %field_definition for nested 1-to-1 objects that fetch from another API object:
#   object   => '/path' # API path to inherit fields from
#   select   => 'SQL',  # SQL to return the ID from the parent table.
#                       # ID is replaced with a sub-object and thus not directly included in the output.
#                       # May return NULL, in which case the entire object is null.
#   subid    => 'SQL',  # SQL to match the ID in the other API object.
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
my %OBJS;
sub api_query($path, %opt) {
    $OBJS{$path} = \%opt;

    my %sort = ($opt{sort}->@*, $opt{search} ? (searchrank => 'sc.score !o, sc.id, sc.subid') : ());
    my $req_schema = FU::Validate->compile({ unknown => 'reject', keys => {
        filters  => { advsearch => $opt{filters} },
        fields   => { default => {}, func => sub { parse_fields($opt{fields}, $_[0]) } },
        sort     => { default => $opt{sort}[0], enum => [ keys %sort ] },
        reverse  => { default => 0, bool => 1 },
        results  => { default => 10, uint => 1, range => [0,100] },
        page     => { default => 1, uint => 1, range => [1,1e6] },
        count    => { default => 0, bool => 1 },
        user     => { default => sub { auth->uid }, vndbid => 'u' },
        time     => { default => 0, bool => 1 },
        compact_filters    => { default => 0, bool => 1 },
        normalized_filters => { default => 0, bool => 1 },
    }});

    FU::post "/api/kana$path", sub {
        check_throttle;

        my $req = fu->json({ type => 'hash' }) || err 400, 'Invalid query.';
        fu->{advsearch_uid} = $req->{user};
        $req = eval { $req_schema->validate($req) };
        if(!$req) {
            my $err = $@;
            warn +($err->errors)[0]."\n";
            err 400, $err->{keys} ? "Unknown member '$err->{keys}[0]'." : 'Missing request body.' if !$err->{errors};
            $err = $err->{errors}[0]//{};
            err 400, "Invalid '$err->{field}' filter: $err->{msg}." if $err->{key} eq 'filters' && $err->{msg} && $err->{field};
            err 400, "Invalid '$err->{key}' member: $err->{msg}" if $err->{key} && $err->{msg};
            err 400, "Invalid '$err->{key}' member." if $err->{key};
            err 400, 'Invalid query.';
        };

        my $numfields = count_fields($opt{fields}, $req->{fields}, $req->{results});
        err 400, sprintf 'Too much data selected (estimated %.0f fields)', $numfields if $numfields > 100_000;

        my($filt, $searchquery) = $req->{sort} eq 'searchrank' ? $req->{filters}->extract_searchquery : ($req->{filters});
        err 400, '"searchrank" sort is only available when the top-level filter is "search", or an "and" with at most one "search".'
            if $req->{sort} eq 'searchrank' && !$searchquery;

        my $sort = $sort{$req->{sort}};
        my $order = $req->{reverse} ? 'DESC' : 'ASC';
        my $opposite_order = $req->{reverse} ? 'ASC' : 'DESC';
        $sort = $sort =~ /[?!]o/ ? ($sort =~ s/\?o/$order/rg =~ s/!o/$opposite_order/rg) : "$sort $order";

        my($select, $joins) = prepare_fields($opt{fields}, $opt{joins}, $req->{fields});
        $joins = sql $joins, $searchquery->sql_join($opt{search}->@*) if $searchquery;

        my($results,$more,$count);
        eval {
            local $SIG{ALRM} = sub { die "Timeout\n"; };
            alarm 3;
            ($results, $more) = $req->{results} == 0 ? ([], 0) :
                fu->dbPagei($req, $opt{sql}->($select, $joins, $filt->sql_where(), $req), 'ORDER BY', $sort);
            $count = $req->{count} && (
                !$more && $req->{results} && @$results <= $req->{results} ? ($req->{results}*($req->{page}-1))+@$results :
                fu->dbVali('SELECT count(*) FROM (', $opt{sql}->('', '', $req->{filters}->sql_where), ') x')
            );
            proc_results($opt{fields}, $req->{fields}, $req, $results);
            alarm 0;
            1;
        } || do {
            alarm 0;
            err 500, 'Processing timeout' if $@ =~ /^Timeout/ || $@ =~ /canceling statement due to statement timeout/;
            die $@;
        };

        cors;
        eval { fu->send_json({
            results => $results,
            more => $more?\1:\0,
            $req->{count} ? (count => $count) : (),
            $req->{compact_filters} ? (compact_filters => $req->{filters}->enc_query) : (),
            $req->{normalized_filters} ? (normalized_filters => $req->{filters}->json) : (),
            $req->{time} ? (time => int(1000*(time() - fu->{throttle_start}))) : (),
        }) };
        count_request(scalar @$results, sprintf '[%s] {%s %s r%dp%d%s%s} %s', fmt_fields($req->{fields}),
            $req->{sort}, lc($order), $req->{results}, $req->{page}, $req->{count}?'c':'', $req->{user}?" $req->{user}":'',
            $req->{filters}->enc_query()||'-');
    };
}


sub parse_fields {
    my @tokens = split /\s*([,.{}])\s*/, $_[1];
    $_[1] = {};
    return (sub {
        my($lvl, $f, $out) = @_;
        my $nf = $f;
        my $of = $out;
        my $ln;
        while(defined (my $t = shift @tokens)) {
            next if !length $t;
            if($t eq '}') {
                return { msg => $ln ? "The '$ln' object requires specifying sub-field(s)." : "Expected (sub)field, got '}'" } if $nf;
                return $lvl > 0 ? 1 : { msg => "Unmatched '}'" } ;
            } elsif($t eq '{') {
                return { msg => "Unexpected '{' after non-object field".($ln ? " '$ln'":'') } if !$nf;
                my $r = __SUB__->($lvl+1, $nf, $of);
                return $r if ref $r;
                ($nf, $of, $ln) = ();
            } elsif($t eq ',') {
                return { msg => $ln ? "The '$ln' object requires specifying sub-field(s)." : 'Expected (sub)field, got comma' } if $nf;
                ($nf, $of, $ln) = ($f, $out);
            } else {
                return { msg => $ln ? "Sub-field specified for non-object '$ln'" : 'Unexpected (sub)field after non-object field' } if !$nf;
                if($t eq '.') {
                    $t = shift(@tokens) // return { msg => "Expected name after '.'" };
                }
                my $d = $nf->{$t} // return { msg => "Field '$t' not found", name => $t };
                $ln = $t;
                $nf = $d->{fields};
                $of->{$t} ||= {};
                $of = $of->{$t};
            }
        }
        return { msg => "The '$ln' object requires specifying sub-field(s)." } if $nf;
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
            push @select, 'v.l_wikidata, v.l_renai' if $d->{extlinks} && $d->{extlinks} eq 'v';
            __SUB__->($d->{fields}, $_[1]{$f}) if $d->{fields} && !($d->{enrich} || $d->{object});
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

        # extlinks
        if($d->{extlinks}) {
            enrich_vislinks $d->{extlinks}, $enabled->{$f}, $results;
            $_->{extlinks} = delete $_->{vislinks} for @$results;
            if ($d->{extlinks} eq 'v') {
                delete @{$_}{ qw/l_renai l_wikidata/ } for @$results;
            }

        # nested 1-to-many objects
        } elsif($d->{enrich}) {
            my($select, $join) = prepare_fields($d->{fields}, $d->{joins}, $enabled->{$f});
            # DB::enrich() logic has been duplicated here to allow for
            # efficient handling of nested proc_results() and `atmostone`.
            my %ids = map defined($_->{$d->{key}}) ? ($_->{$d->{key}},[]) : (), @$results;
            my $rows = keys %ids ? fu->dbAlli($d->{enrich}->($select, $join, [keys %ids], $req)) : [];
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

        # nested 1-to-1 objects (external)
        } elsif($d->{object}) {
            my $subidname = "${f}_objid";
            my($select, $join) = prepare_fields($d->{fields}, $d->{joins}, $enabled->{$f});
            $select .= ",$d->{subid} AS $subidname";
            # This is enrich_obj()
            my %ids = map defined($_->{$f}) ? ($_->{$f},undef) : (), @$results;
            my $rows = keys %ids ? fu->dbAlli(
                $OBJS{$d->{object}}{sql}->($select, $join, sql($d->{subid}, 'IN', [keys %ids]), $req)
            ) : [];
            proc_results($d->{fields}, $enabled->{$f}, $req, $rows);
            $ids{ delete $_->{$subidname} } = $_ for @$rows;
            $_->{$f} = defined $_->{$f} ? $ids{ $_->{$f} } : undef for @$results;

        # nested 1-to-1 objects (internal)
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


api_get '/schema', {}, sub {
    # XXX: This only lists direct extlink fields of the object, not wikidata-derived or custom links.
    my sub el($t) {
        my $L = \%VNDB::ExtLinks::LINKS;
        [ map +{ name => $_, label => $L->{$_}{label}, url_format => $L->{$_}{fmt} },
            grep $L->{$_}{regex} && $L->{$_}{ent} =~ /$t/i, keys %$L ]
    }
    state $s = {
        enums => {
            language => [ map +{ id => $_, label => $LANGUAGE{$_}{txt} }, keys %LANGUAGE ],
            platform => [ map +{ id => $_, label => $PLATFORM{$_} }, keys %PLATFORM ],
            medium   => [ map +{ id => $_, label => $MEDIUM{$_}{txt}, plural => $MEDIUM{$_}{plural}||undef }, keys %MEDIUM ],
            staff_role => [ map +{ id => $_, label => $CREDIT_TYPE{$_} }, keys %CREDIT_TYPE ],
        },
        api_fields => { map +($_, (sub {
            +{ map {
                my $f = $_[0]{$_};
                my $sub = $f->{inherit} // $f->{object};
                my $s = $f->{fields} ? __SUB__->($f->{fields}, $sub ? $OBJS{$sub}{fields} : {}) : {};
                $s->{_inherit} = $sub if $sub;
                ($_, keys %$s ? $s : undef)
            } grep !$_[1]{$_}, keys $_[0]->%* }
        })->($OBJS{$_}{fields}, {})), keys %OBJS },
        extlinks => {
            '/vn'      => el('v'),
            '/release' => el('r'),
            '/staff'   => el('s'),
            '/producer'=> el('p'),
        },
    }
};


my @STATS = qw{traits producers tags chars staff vn releases};
api_get '/stats', { map +($_, { uint => 1 }), @STATS }, sub {
    +{ map +($_->{section}, $_->{count}),
        fu->dbAlli('SELECT * FROM stats_cache WHERE section IN', \@STATS)->@* };
};


api_get '/authinfo', {}, sub {
    err 401, 'Unauthorized' if !auth;
    +{
        id => auth->uid,
        username => auth->user->{user_name},
        permissions => [
            auth->api2Listread ? 'listread' : (),
            auth->api2Listwrite ? 'listwrite' : (),
        ]
    }
};


api_get '/user', {}, sub {
    my $data = eval { fu->query(
        q      => { accept_scalar => 1, maxlength => 100, elems => {} },
        fields => { fields => ['lengthvotes', 'lengthvotes_sum'] },
    ) } || err 400, 'Invalid argument';
    my ($q, $f) = @{$data}{qw{ q fields }};
    my $regex = '^u[1-9][0-9]{0,6}$';
    +{ map +(delete $_->{q}, $_->{id} ? $_ : undef), fu->dbAlli('
        WITH u AS (
            SELECT x.q, u.id, u.username
              FROM unnest(', sql_array(@$q), ') x(q)
              LEFT JOIN users u ON u.id = CASE WHEN x.q ~', \$regex, 'THEN x.q::vndbid ELSE NULL END
                                OR LOWER(u.username) = LOWER(x.q)
        ) SELECT u.*',
                 $f->{lengthvotes} ? ', coalesce(l.count,0) AS lengthvotes' : (),
                 $f->{lengthvotes_sum} ? ', coalesce(l.sum,0) AS lengthvotes_sum' : (),
          'FROM u',
          $f->{lengthvotes} || $f->{lengthvotes_sum} ? ('LEFT JOIN (
                SELECT uid, count(*) AS count, sum(length) AS sum
                  FROM vn_length_votes
                 WHERE uid IN(SELECT id FROM u)
                 GROUP BY uid
             ) l ON l.uid = u.id'
          ) : (),
    )->@* }
};


api_get '/ulist_labels', { labels => { aoh => {
    id      => { uint => 1 },
    private => { anybool => 1 },
    label   => {},
}}}, sub {
    my $data = eval { fu->query(
        user   => { vndbid => 'u', default => auth->uid||\'required' },
        fields => { default => undef, enum => ['count'] },
    ) } || err 400, 'Invalid argument';
    +{ labels => ulist_filtlabels $data->{user}, $data->{fields} };
};


api_patch qr{/ulist/$RE{vid}}, {
    vote         => { default => undef, uint => 1, range => [10,100] },
    notes        => { default => '', maxlength => 2000 },
    started      => { caldate => 1 },
    finished     => { caldate => 1 },
    labels       => { default => [], elems => { uint => 1, range => [1,1600] } },
    labels_set   => { default => [], elems => { uint => 1, range => [1,1600] } },
    labels_unset => { default => [], elems => { uint => 1, range => [1,1600] } },
}, sub($vid, $upd) {
    err 401, 'Unauthorized' if !auth->api2Listwrite;
    err 404, 'Visual novel not found' if !fu->dbExeci('SELECT 1 FROM vn WHERE NOT hidden AND id =', \$vid);

    my $newlabels = sql "'{}'::smallint[]";
    if($upd->{labels} || $upd->{labels_set} || $upd->{labels_unset}) {
        my @all = $upd->{labels} ? $upd->{labels}->@* : ();
        my @set = $upd->{labels_set} ? $upd->{labels_set}->@* : ();
        my @unset = $upd->{labels_unset} ? $upd->{labels_unset}->@* : ();
        my %labels = map +($_, 1), @all, @set;
        delete $labels{$_} for @unset;
        err 400, 'Label id 7 cannot be used here' if $labels{7} || grep $_ == 7, @unset;

        $upd->{labels} = $upd->{labels} ? sql(sql_array(sort { $a <=> $b } keys %labels),'::smallint[]') : do {
            my $l = 'ulist_vns.labels';
            $l = sql 'array_set(', $l, ',', \(0+$_), ')' for @set;
            $l = sql 'array_remove(', $l, ',', \(0+$_), ')' for @unset;
            $l
        };

        delete $upd->{labels_set};
        delete $upd->{labels_unset};
        $newlabels = sql(sql_array(sort { $a <=> $b } keys %labels),'::smallint[]');
    }
    $upd->{lastmod} = sql 'NOW()';
    $upd->{vote_date} = sql $upd->{vote} ? 'CASE WHEN ulist_vns.vote IS NULL THEN NOW() ELSE ulist_vns.vote_date END' : 'NULL'
        if exists $upd->{vote};

    my $done = fu->dbExeci(
        'INSERT INTO ulist_vns', { %$upd,
            labels => $newlabels,
            vote_date => sql($upd->{vote} ? 'NOW()' : 'NULL'),
            uid => auth->uid,
            vid => $vid
        },
        'ON CONFLICT (uid, vid) DO', keys %$upd ? ('UPDATE SET', $upd) : 'NOTHING'
    );
    if($done > 0) {
        fu->dbExeci(SELECT => sql_func update_users_ulist_private => \auth->uid, \$vid);
        fu->dbExeci(SELECT => sql_func update_users_ulist_stats => \auth->uid);
    }
};


api_patch qr{/rlist/$RE{rid}}, {
    status  => { uint => 1, default => 0, enum => \%RLIST_STATUS },
}, sub($rid, $upd) {
    err 401, 'Unauthorized' if !auth->api2Listwrite;
    err 404, 'Release not found' if !fu->dbExeci('SELECT 1 FROM releases WHERE NOT hidden AND id =', \$rid);
    fu->dbExeci(
        'INSERT INTO rlists', { %$upd, uid => auth->uid, rid => $rid },
        'ON CONFLICT (uid, rid) DO', keys %$upd ? ('UPDATE SET', $upd) : 'NOTHING'
    );
};


api_del qr{/ulist/$RE{vid}}, sub($id) {
    err 401, 'Unauthorized' if !auth->api2Listwrite;
    fu->dbExeci('DELETE FROM ulist_vns WHERE uid =', \auth->uid, 'AND vid =', \$id);
    fu->dbExeci(SELECT => sql_func update_users_ulist_stats => \auth->uid);
};


api_del qr{/rlist/$RE{rid}}, sub($id) {
    err 401, 'Unauthorized' if !auth->api2Listwrite;
    fu->dbExeci('DELETE FROM rlists WHERE uid =', \auth->uid, 'AND rid =', \$id);
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

# Extracts the alttitle from a 'vnt.titles'-like array column, returns null if equivalent to the main title.
sub ALTTITLE { my($t,$col) = @_; +(select => "CASE WHEN $t"."[1+1] = $t"."[1+1+1+1] THEN NULL ELSE $t"."[1+1+1+1] END AS ".($col // 'alttitle')) }


api_query '/vn',
    filters => 'v',
    sql => sub { sql 'SELECT v.id', $_[0], 'FROM vnt v', $_[1], 'WHERE NOT v.hidden AND (', $_[2], ')' },
    joins => {
        image => 'LEFT JOIN images i ON i.id = v.c_image',
    },
    search => [ 'v', 'v.id' ],
    fields => {
        id => {},
        title => { select => 'v.title[1+1]' },
        alttitle => { ALTTITLE 'v.title' },
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
            fields => {
                IMG('v.c_image', 'image', 'i.'),
                thumbnail => { join => 'image', col => 'thumbnail'
                             , select => "ARRAY[v.c_image::text, i.width::text, i.height::text] AS thumbnail"
                             , proc => sub { my($id,$w,$h) = $_[0]->@*; $_[0] = imgurl $id, $w <= config->{cv_size}[0] && $h <= config->{cv_size}[1] ? '' : 't' } },
                thumbnail_dims => { join => 'image', col => 'thumbnail_dims'
                                  , select => "ARRAY[i.width, i.height] AS thumbnail_dims"
                                  , proc => sub { @{$_[0]} = imgsize @{$_[0]}, config->{cv_size}->@* } },
            },
            nullif => 'v.c_image IS NULL AS image_nullif',
        },
        length => { select => 'v.length', proc => sub { $_[0] = undef if !$_[0] } },
        length_minutes => { select => 'v.c_length AS length_minutes' },
        length_votes => { select => 'v.c_lengthnum AS length_votes' },
        description => { select => 'v.description', @NSTR },
        average     => { select => 'v.c_average AS average', proc => sub { $_[0] /= 10 if defined $_[0] } },
        rating      => { select => 'v.c_rating AS rating', proc => sub { $_[0] /= 10 if defined $_[0] } },
        popularity  => { select => 'v.c_votecount AS popularity', proc => sub { $_[0] = min(100, $_[0]/150) if defined $_[0] } },
        votecount   => { select => 'v.c_votecount AS votecount' },
        screenshots => {
            enrich => sub { sql 'SELECT vs.id AS vid', $_[0], 'FROM vn_screenshots vs', $_[1], 'WHERE vs.id IN', $_[2] },
            key => 'id', col => 'vid', num => 10,
            joins => {
                image => 'JOIN images i ON i.id = vs.scr',
            },
            fields => {
                IMG('vs.scr', 'image', 'i.'),
                thumbnail => { select => "vs.scr AS thumbnail", col => 'thumbnail', proc => sub { $_[0] = imgurl $_[0], 't' } },
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
        relations => {
            enrich => sub { sql 'SELECT vr.id AS vid, v.id', $_[0], 'FROM vn_relations vr JOIN vnt v ON v.id = vr.vid', $_[1], 'WHERE vr.id IN', $_[2] },
            key => 'id', col => 'vid', num => 3,
            inherit => '/vn',
            fields => {
                relation          => { select => 'vr.relation' },
                relation_official => { select => 'vr.official AS relation_official', @BOOL },
            },
        },
        tags => {
            enrich => sub { sql 'SELECT tv.vid, t.id', $_[0], 'FROM tags_vn_direct tv JOIN tags t ON t.id = tv.tag', $_[1], 'WHERE NOT t.hidden AND tv.vid IN', $_[2] },
            key => 'id', col => 'vid', num => 50,
            inherit => '/tag',
            fields => {
                rating   => { select => 'tv.rating' },
                spoiler  => { select => 'tv.spoiler' },
                lie      => { select => 'tv.lie', @BOOL },
            },
        },
        developers => {
            enrich => sub { sql 'SELECT v.id AS vid, p.id', $_[0], 'FROM vn v, unnest(v.c_developers) vp(id), producerst p', $_[1], 'WHERE p.id = vp.id AND v.id IN', $_[2] },
            key => 'id', col => 'vid', num => 2,
            inherit => '/producer',
        },
        editions => {
            enrich => sub { sql 'SELECT id', $_[0], 'FROM vn_editions WHERE id IN', $_[2] },
            key => 'id', col => 'id', num => 3,
            fields => {
                eid   => { select => 'eid' },
                lang  => { select => 'lang' },
                name  => { select => 'name' },
                official => { select => 'official', @BOOL },
            },
        },
        staff => {
            enrich => sub { sql 'SELECT vs.id AS vid, s.id', $_[0], 'FROM vn_staff vs JOIN staff_aliast s ON s.aid = vs.aid', $_[1], 'WHERE NOT s.hidden AND vs.id IN', $_[2] },
            key => 'id', col => 'vid', num => 20,
            inherit => '/staff',
            fields => {
                eid   => { select => 'vs.eid' },
                role  => { select => 'vs.role' },
                note  => { select => 'vs.note', @NSTR },
            },
        },
        va => {
            enrich => sub { sql 'SELECT vs.id AS vid', $_[0], 'FROM vn_seiyuu vs JOIN staff_aliast s ON s.aid = vs.aid JOIN chars c ON c.id = vs.cid', $_[1], 'WHERE NOT s.hidden AND NOT c.hidden AND vs.id IN', $_[2] },
            key => 'id', col => 'vid', num => 10,
            fields => {
                staff     => { object => '/staff',     select => 'vs.aid AS staff',     subid => 's.aid' },
                character => { object => '/character', select => 'vs.cid AS character', subid => 'c.id' },
                note      => { select => 'vs.note', @NSTR },
            },
        },
        extlinks   => { extlinks => 'v' },
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
    search => [ 'r', 'r.id' ],
    fields => {
        id       => {},
        title    => { select => 'r.title[1+1]' },
        alttitle => { ALTTITLE 'r.title' },
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
            enrich => sub { sql 'SELECT rp.id AS rid, p.id', $_[0], 'FROM releases_producers rp JOIN producerst p ON p.id = rp.pid', $_[1], 'WHERE rp.id IN', $_[2] },
            key => 'id', col => 'rid', num => 3,
            inherit => '/producer',
            fields => {
                developer => { select => 'rp.developer', @BOOL },
                publisher => { select => 'rp.publisher', @BOOL },
            },
        },
        images => {
            enrich => sub { sql 'SELECT ri.id AS rid', $_[0], 'FROM releases_images ri', $_[1], 'WHERE ri.id IN', $_[2] },
            key => 'id', col => 'rid', num => 3,
            joins => {
                image => 'JOIN images i ON i.id = ri.img',
            },
            fields => {
                IMG('ri.img', 'image', 'i.'),
                thumbnail => { select => 'ri.img AS thumbnail', col => 'thumbnail', proc => sub { $_[0] = imgurl $_[0], 't' } },
                thumbnail_dims => { join => 'image', col => 'thumbnail_dims'
                                  , select => "ARRAY[i.width, i.height] AS thumbnail_dims"
                                  , proc => sub { @{$_[0]} = imgsize @{$_[0]}, config->{cv_size}->@* } },
                type      => { select => 'ri.itype AS type' },
                vn        => { select => 'ri.vid AS vn' },
                languages => { select => 'ri.lang::text[] AS languages' },
                photo     => { select => 'ri.photo', @BOOL },
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
        voiced     => { select => 'r.voiced', @NINT },
        notes      => { select => 'r.notes', @NSTR },
        gtin       => { select => 'r.gtin', proc => sub { $_[0] = undef if !gtintype $_[0] } },
        catalog    => { select => 'r.catalog', @NSTR },
        extlinks   => { extlinks => 'r' },
    },
    sort => [
        id       => 'r.id',
        title    => 'r.sorttitle ?o, r.id',
        released => 'r.released ?o, r.id',
    ];


api_query '/producer',
    filters => 'p',
    sql => sub { sql 'SELECT p.id', $_[0], 'FROM producerst p', $_[1], 'WHERE NOT p.hidden AND (', $_[2], ')' },
    search => [ 'p', 'p.id' ],
    fields => {
        id       => {},
        name     => { select => 'p.title[1+1] AS name' },
        original => { ALTTITLE 'p.title', 'original' },
        aliases  => { select => 'p.alias AS aliases', @MSTR },
        lang     => { select => 'p.lang' },
        type     => { select => 'p.type' },
        description => { select => 'p.description', @NSTR },
        extlinks => { extlinks => 'p' },
    },
    sort => [
        id       => 'p.id',
        name     => 'p.sorttitle ?o, p.id',
    ];


api_query '/character',
    filters => 'c',
    sql => sub { sql 'SELECT c.id', $_[0], 'FROM charst c', $_[1], 'WHERE NOT c.hidden AND (', $_[2], ')' },
    search => [ 'c', 'c.id' ],
    joins => {
        image => 'LEFT JOIN images i ON i.id = c.image',
    },
    fields => {
        id       => {},
        name     => { select => 'c.title[1+1] AS name' },
        original => { ALTTITLE 'c.title', 'original' },
        aliases  => { select => 'c.alias AS aliases', @MSTR },
        description => { select => 'c.description', @NSTR },
        image => {
            fields => { IMG 'c.image', 'image', 'i.' },
            nullif => 'c.image IS NULL AS image_nullif',
        },
        blood_type => { select => 'c.bloodt AS blood_type', proc => sub { $_[0] = undef if $_[0] eq 'unknown' } },
        height   => { select => 'c.height', @NINT },
        weight   => { select => 'c.weight' },
        bust     => { select => 'c.s_bust AS bust', @NINT },
        waist    => { select => 'c.s_waist AS waist', @NINT },
        hips     => { select => 'c.s_hip AS hips', @NINT },
        cup      => { select => 'c.cup_size AS cup', @NSTR },
        age      => { select => 'c.age' },
        birthday => { select => 'c.birthday', proc => sub { $_[0] = $_[0] ? [ int $_[0]/100, $_[0]%100 ] : undef } },
        sex      => { select => "NULLIF(ARRAY[NULLIF(c.sex, ''), NULLIF(COALESCE(c.spoil_sex, c.sex), '')]::text[], '{NULL,NULL}') AS sex" },
        gender   => { select => "NULLIF(ARRAY[
                COALESCE(NULLIF(c.gender::text, ''), CASE WHEN c.sex IN('m','f') THEN c.sex::text ELSE NULL END),
                NULLIF(COALESCE(c.spoil_gender::text, c.gender::text, CASE WHEN COALESCE(c.spoil_sex, c.sex) IN('m','f') THEN COALESCE(c.spoil_sex, c.sex)::text ELSE NULL END), '')
            ]::text[], '{NULL,NULL}') AS gender" },
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
            enrich => sub { sql 'SELECT ct.id AS cid, t.id', $_[0], 'FROM chars_traits ct JOIN traits t ON t.id = ct.tid', $_[1], 'WHERE NOT t.hidden AND ct.id IN', $_[2] },
            key => 'id', col => 'cid', num => 30,
            inherit => '/trait',
            fields => {
                spoiler  => { select => 'ct.spoil AS spoiler' },
                lie      => { select => 'ct.lie', @BOOL },
            },
        },
    },
    sort => [
        id       => 'c.id',
        name     => 'c.name ?o, c.id',
    ];


api_query '/staff',
    filters => 's',
    sql => sub { sql 'SELECT s.id', $_[0], 'FROM staff_aliast s', $_[1], 'WHERE NOT s.hidden AND (', $_[2], ')' },
    search => [ 's', 's.id', 's.aid' ],
    fields => {
        id       => {},
        aid      => { select => 's.aid' },
        ismain   => { select => 's.main = s.aid AS ismain', @BOOL },
        name     => { select => 's.title[1+1] AS name' },
        original => { ALTTITLE 's.title', 'original' },
        lang     => { select => 's.lang' },
        gender   => { select => "NULLIF(s.gender, '') AS gender" },
        description => { select => 's.description', @NSTR },
        extlinks => { extlinks => 's' },
        aliases  => {
            enrich => sub { sql 'SELECT sa.id', $_[0], 'FROM staff_alias sa', $_[1], 'WHERE sa.id IN', $_[2] },
            key => 'id', col => 'id', num => 3,
            joins => {
                main => 'JOIN staff s ON s.id = sa.id',
            },
            fields => {
                aid    => { select => 'sa.aid' },
                name   => { select => 'sa.name' },
                latin  => { select => 'sa.latin' },
                ismain => { join => 'main', select => 'sa.aid = s.main AS ismain', @BOOL },
            },
        },
    },
    sort => [
        id       => 's.id',
        name     => 's.sorttitle ?o, s.id',
    ];


api_query '/tag',
    filters => 'g',
    sql => sub { sql 'SELECT t.id', $_[0], 'FROM tags t', $_[1], 'WHERE NOT t.hidden AND (', $_[2], ')' },
    search => [ 'g', 't.id' ],
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


api_query '/trait',
    filters => 'i',
    sql => sub { sql 'SELECT t.id', $_[0], 'FROM traits t', $_[1], 'WHERE NOT t.hidden AND (', $_[2], ')' },
    search => [ 'i', 't.id' ],
    joins => {
        group => 'LEFT JOIN traits g ON g.id = t.gid',
    },
    fields => {
        id          => {},
        name        => { select => 't.name' },
        aliases     => { select => 't.alias AS aliases', @MSTR },
        description => { select => 't.description' },
        searchable  => { select => 't.searchable', @BOOL },
        applicable  => { select => 't.applicable', @BOOL },
        group_id    => { join => 'group', select => 't.gid AS group_id' },
        group_name  => { join => 'group', select => 'g.name AS group_name' },
        char_count  => { select => 't.c_items AS char_count' },
    },
    sort => [
        id         => 't.id',
        name       => 't.name ?o, t.id',
        char_count => 't.c_items ?o, t.id',
    ];


api_query '/ulist',
    filters => 'v',
    sql => sub {
        err 400, 'Missing "user" parameter and not authenticated.' if !$_[3]{user};
        sql 'SELECT v.id', $_[0], '
               FROM ulist_vns uv
               JOIN vnt v ON v.id = uv.vid', $_[1], '
              WHERE', sql_and
                'NOT v.hidden',
                sql('uv.uid =', \$_[3]{user}),
                auth->api2Listread($_[3]{user}) ? () : 'NOT uv.c_private',
                $_[2];
    },
    search => [ 'v', 'v.id' ],
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
            enrich => sub { sql 'SELECT uv.vid', $_[0], '
                                   FROM ulist_vns uv, unnest(uv.labels) l(id), ulist_labels ul
                                  WHERE', sql_and
                                     sql('uv.uid =', \$_[3]{user}),
                                     sql('ul.uid =', \$_[3]{user}),
                                     'ul.id = l.id',
                                     auth->api2Listread($_[3]{user}) ? () : 'NOT ul.private',
                                     sql('uv.vid IN', $_[2]) },
            key => 'id', col => 'vid', num => 3,
            fields => {
                id    => { select => 'l.id' },
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


api_query '/quote',
    filters => 'q',
    sql => sub { sql 'SELECT q.id', $_[0], 'FROM quotes q', $_[1], 'WHERE NOT q.hidden AND (', $_[2], ')' },
    fields => {
        id        => {},
        quote     => { select => 'q.quote' },
        score     => { select => 'q.score', @INT },
        vn        => { object => '/vn', select => 'q.vid AS vn', subid => 'v.id' },
        character => { object => '/character', select => 'q.cid AS character', subid => 'c.id' },
    },
    sort => [
        id         => 'q.id',
        score      => 'q.score',
    ];




# Now that all APIs have been defined, go over the definitions and:
# - Resolve 'inherit' fields
# - Expand 'extlinks' fields
(sub {
    for my $f (values $_[0]->%*) {
        if($f->{inherit} || $f->{object}) {
            my $o = $OBJS{ $f->{inherit} || $f->{object} };
            $f->{fields}{$_} = $o->{fields}{$_} for keys %{ $o->{fields}||{} };
            $f->{joins}{$_} = $o->{joins}{$_} for keys %{ $o->{joins}||{} };
        }
        $f->{fields} ||= { map +($_,{}), qw{name label id url} } if $f->{extlinks};
        __SUB__->($f->{fields}) if $f->{fields} && !$f->{_expand_done}++;
    }
})->($_->{fields}) for values %OBJS;

1;
