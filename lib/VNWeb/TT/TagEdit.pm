package VNWeb::TT::TagEdit;

use VNWeb::Prelude;

my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id           => { default => undef, vndbid => 'g' },
    name         => { maxlength => 250, sl => 1 },
    alias        => { maxlength => 1024, default => '' },
    cat          => { enum => \%TAG_CATEGORY, default => 'cont' },
    description  => { maxlength => 10240 },
    searchable   => { anybool => 1, default => 1 },
    applicable   => { anybool => 1, default => 1 },
    defaultspoil => { uint => 1, range => [0,2] },
    parents      => { aoh => {
        parent      => { vndbid => 'g' },
        main        => { anybool => 1 },
        name        => { _when => 'out' },
    } },
    wipevotes    => { _when => 'in', anybool => 1 },
    merge        => { aoh => {
        id          => { vndbid => 'g' },
        name        => { _when => 'out' },
    } },
    hidden       => { anybool => 1 },
    locked       => { anybool => 1 },

    authmod      => { _when => 'out', anybool => 1 },
    editsum      => { editsum => 1 },
};


FU::get qr{/$RE{grev}/edit}, sub($id, $rev=0) {
    my $g = db_entry $id, $rev or fu->notfound;
    fu->denied if !can_edit g => $g;

    $g->{authmod} = auth->permTagmod;
    $g->{editsum} = $g->{chrev} == $g->{maxrev} ? '' : "Reverted to revision $g->{id}.$g->{chrev}";
    $g->{merge} = [];

    framework_ title => "Edit tag: $g->{name}", dbobj => $g, tab => 'edit', sub {
        div_ widget(TagEdit => $FORM_OUT, $g), '';
    };
};


FU::get qr{/(?:$RE{gid}/add|g/new)}, sub($id=undef) {
    my $g = $id && fu->dbRowi('SELECT id, name, cat FROM tags WHERE NOT hidden AND id =', \$id);
    fu->denied if !can_edit g => {};
    fu->notfound if $id && !$g->{id};

    my $e = $FORM_OUT->empty;
    $e->{authmod} = auth->permTagmod;
    if($id) {
        $e->{parents} = [{ parent => $g->{id}, main => 1, name => $g->{name} }];
        $e->{cat} = $g->{cat};
    }

    framework_ title => 'Submit a new tag', sub {
        article_ sub {
            h1_ 'Requesting new tag';
            div_ class => 'notice', sub {
                h2_ 'Your tag must be approved';
                p_ sub {
                    txt_ 'All tags have to be approved by a moderator, so it can take a while before it will show up in the tag list'
                       .' or on visual novel pages. You can still vote on the tag even if it has not been approved yet.';
                    br_;
                    br_;
                    txt_ 'Make sure you\'ve read the '; a_ href => '/d10', 'guidelines'; txt_ ' to increase the chances of getting your tag accepted.';
                }
            }
        } if !auth->permTagmod;
        div_ widget(TagEdit => $FORM_OUT, $e), '';
    };
};


js_api TagEdit => $FORM_IN, sub($data) {
    my $new = !$data->{id};
    my $e = $new ? {} : db_entry $data->{id} or fu->notfound;
    fu->notfound if !$new && !$e->{id};
    fu->denied if !can_edit g => $e;

    if(!auth->permTagmod) {
        $data->{hidden} = $e->{hidden}//1;
        $data->{locked} = $e->{locked}//0;
    }

    my $re = '[\t\s]*\n[\t\s]*';
    my $dups = fu->dbAlli('
        SELECT id, name
          FROM (SELECT id, name FROM tags UNION SELECT id, s FROM tags, regexp_split_to_table(alias, ', \$re, ') a(s) WHERE s <> \'\') n(id,name)
         WHERE ', sql_and(
             $new ? () : sql('id <>', \$data->{id}),
             sql 'lower(name) IN', [ map lc($_), $data->{name}, grep length($_), split /$re/, $data->{alias} ]
         )
    );
    return +{ dups => $dups } if @$dups;

    # Make sure parent IDs exists and are not a child tag of the current tag (i.e. don't allow cycles)
    validate_dbid sub {
        'SELECT id FROM tags WHERE', sql_and
            $new ? () : sql('id NOT IN(WITH RECURSIVE t(id) AS (SELECT', \$data->{id}, '::vndbid UNION SELECT tp.id FROM tags_parents tp JOIN t ON t.id = tp.parent) SELECT id FROM t)'),
            sql 'id IN', $_[0]
    }, map $_->{parent}, $data->{parents}->@*;
    die "No or multiple primary parents" if $data->{parents}->@* && 1 != grep $_->{main}, $data->{parents}->@*;

    $data->{description} = bb_subst_links($data->{description});

    my $changed = 0;
    if(!$new && auth->permTagmod && $data->{wipevotes}) {
        my $num = fu->dbExeci('DELETE FROM tags_vn WHERE tag =', \$e->{id});
        auth->audit(undef, 'tag wipe', "Wiped $num votes on $e->{id}");
        $changed++;
    }

    if(!$new && auth->permTagmod && $data->{merge}->@*) {
        my @merge = map $_->{id}, $data->{merge}->@*;
        # Bugs:
        # - Arbitrarily takes one vote if there are duplicates, should ideally try to merge them instead.
        # - The 'ignore' flag will be inconsistent if set and the same VN has been voted on for multiple tags.
        my $mov = fu->dbExeci('
            INSERT INTO tags_vn (tag,vid,uid,vote,spoiler,date,ignore,notes)
                 SELECT ', \$e->{id}, ',vid,uid,vote,spoiler,date,ignore,notes
                   FROM tags_vn WHERE tag IN', \@merge, '
                     ON CONFLICT (tag,vid,uid) DO NOTHING'
        );
        my $del = fu->dbExeci('DELETE FROM tags_vn tv WHERE tag IN', \@merge);
        my $lst = join ',', @merge;
        auth->audit(undef, 'tag merge', "Moved $mov/$del votes from $lst to $e->{id}");
        $changed++;
    }

    my $ch = db_edit g => $e->{id}, $data;
    return $ch->{nitemid} ? +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" } : $changed ? +{ _redir => "/$e->{id}" } : 'No changes.';
};

1;
