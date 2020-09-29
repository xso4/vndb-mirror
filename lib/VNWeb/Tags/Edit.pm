package VNWeb::Tags::Edit;

use VNWeb::Prelude;

# TODO: Let users edit their own tag while it's still waiting for approval?

my $FORM = {
    id           => { required => 0, id => 1 },
    name         => { maxlength => 250, regex => qr/^[^,\r\n]+$/ },
    aliases      => { type => 'array', values => { maxlength => 250, regex => qr/^[^,\r\n]+$/ } },
    state        => { uint => 1, range => [0,2] },
    cat          => { enum => \%TAG_CATEGORY, default => 'cont' },
    description  => { maxlength => 10240 },
    searchable   => { anybool => 1, default => 1 },
    applicable   => { anybool => 1, default => 1 },
    defaultspoil => { uint => 1, range => [0,2] },
    parents      => { aoh => {
        id          => { id => 1 },
        name        => { _when => 'out' },
    } },
    wipevotes    => { _when => 'in', anybool => 1 },
    merge        => { _when => 'in', aoh => { id => { id => 1 } } },

    addedby      => { _when => 'out' },
    can_mod      => { _when => 'out', anybool => 1 },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;


TUWF::get qr{/$RE{gid}/edit}, sub {
    my $g = tuwf->dbRowi('
        SELECT g.id, g.name, g.description, g.state, g.cat, g.defaultspoil, g.searchable, g.applicable
             , ', sql_user('u', 'addedby_'), '
          FROM tags g
          LEFT JOIN users u ON g.addedby = u.id
         WHERE g.id =', \tuwf->capture('id')
    );
    return tuwf->resNotFound if !$g->{id};

    enrich_flatten aliases => id => tag => 'SELECT tag, alias FROM tags_aliases WHERE tag IN', $g;
    enrich parents => id => tag => 'SELECT gp.tag, g.id, g.name FROM tags_parents gp JOIN tags g ON g.id = gp.parent WHERE gp.tag IN', $g;

    return tuwf->resDenied if !can_edit g => $g;

    $g->{addedby} = xml_string sub { user_ $g, 'addedby_'; };
    $g->{can_mod} = auth->permTagmod;

    framework_ title => "Edit $g->{name}", type => 'g', dbobj => $g, tab => 'edit', sub {
        elm_ TagEdit => $FORM_OUT, $g;
    };
};


TUWF::get qr{/(?:$RE{gid}/add|g/new)}, sub {
    my $id = tuwf->capture('id');
    my $g = tuwf->dbRowi('SELECT id, name, cat FROM tags WHERE id =', \$id);
    return tuwf->resDenied if !can_edit g => {};
    return tuwf->resNotFound if $id && !$g->{id};

    my $e = elm_empty($FORM_OUT);
    $e->{can_mod} = auth->permTagmod;
    if($id) {
        $e->{parents} = [$g];
        $e->{cat} = $g->{cat};
    }

    framework_ title => 'Submit a new tag', sub {
        div_ class => 'mainbox', sub {
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
        elm_ TagEdit => $FORM_OUT, $e;
    };
};


elm_api TagEdit => $FORM_OUT, $FORM_IN, sub {
    my($data) = @_;
    my $id = delete $data->{id};
    my $g = !$id ? {} : tuwf->dbRowi('SELECT id, addedby, state FROM tags WHERE id =', \$id);
    return tuwf->resNotFound if $id && !$g->{id};
    return elm_Unauth if !can_edit g => $g;

    $data->{addedby} = $g->{addedby} // auth->uid;
    if(!auth->permTagmod) {
        $data->{state} = 0;
        $data->{applicable} = $data->{searchable} = 1;
    }

    my $dups = tuwf->dbAlli('
        SELECT id, name
          FROM (SELECT id, name FROM tags UNION SELECT tag, alias FROM tags_aliases) n(id,name)
         WHERE ', sql_and(
             $id ? sql 'id <>', \$id : (),
             sql 'lower(name) IN', [ map lc($_), $data->{name}, $data->{aliases}->@* ]
         )
    );
    return elm_DupNames $dups if @$dups;

    # Make sure parent IDs exists and are not a child tag of the current tag (i.e. don't allow cycles)
    validate_dbid sub {
        'SELECT id FROM tags WHERE', sql_and
            $id ? sql 'id NOT IN(WITH RECURSIVE t(id) AS (SELECT', \$id, '::int UNION SELECT tag FROM tags_parents tp JOIN t ON t.id = tp.parent) SELECT id FROM t)' : (),
            sql 'id IN', $_[0]
    }, map $_->{id}, $data->{parents}->@*;

    my %set = map +($_,$data->{$_}), qw/name description state addedby cat defaultspoil searchable applicable/;
    $set{added} = sql 'NOW()' if $id && $data->{state} == 2 && $g->{state} != 2;
    tuwf->dbExeci('UPDATE tags SET', \%set, 'WHERE id =', \$id) if $id;
    $id = tuwf->dbVali('INSERT INTO tags', \%set, 'RETURNING id') if !$id;

    tuwf->dbExeci('DELETE FROM tags_aliases WHERE tag =', \$id);
    tuwf->dbExeci('INSERT INTO tags_aliases (tag,alias) VALUES(', \$id, ',', \$_, ')') for $data->{aliases}->@*;

    tuwf->dbExeci('DELETE FROM tags_parents WHERE tag =', \$id);
    tuwf->dbExeci('INSERT INTO tags_parents (tag,parent) VALUES(', \$id, ',', \$_->{id}, ')') for $data->{parents}->@*;

    auth->audit(undef, 'tag edit', "g$id") if $id; # Since we don't have edit histories for tags yet.

    if(auth->permTagmod && $data->{wipevotes}) {
        my $num = tuwf->dbExeci('DELETE FROM tags_vn WHERE tag =', \$id);
        auth->audit(undef, 'tag wipe', "Wiped $num votes on g$id");
    }

    if(auth->permTagmod && $data->{merge}->@*) {
        my @merge = map $_->{id}, $data->{merge}->@*;
        # Bugs:
        # - Arbitrarily takes one vote if there are duplicates, should ideally try to merge them instead.
        # - The 'ignore' flag will be inconsistent if set and the same VN has been voted on for multiple tags.
        my $mov = tuwf->dbExeci('
            INSERT INTO tags_vn (tag,vid,uid,vote,spoiler,date,ignore,notes)
                 SELECT ', \$id, ',vid,uid,vote,spoiler,date,ignore,notes
                   FROM tags_vn WHERE tag IN', \@merge, '
                     ON CONFLICT (tag,vid,uid) DO NOTHING'
        );
        my $del = tuwf->dbExeci('DELETE FROM tags_vn tv WHERE tag IN', \@merge);
        my $lst = join ',', map "g$_", @merge;
        auth->audit(undef, 'tag merge', "Moved $mov/$del votes from $lst to g$id");
    }

    elm_Redirect "/g$id";
};

1;
