package VNWeb::Releases::Edit;

use VNWeb::Prelude;


my $FORM = {
    id         => { required => 0, vndbid => 'r' },
    official   => { anybool => 1 },
    patch      => { anybool => 1 },
    freeware   => { anybool => 1 },
    doujin     => { anybool => 1 },
    has_ero    => { anybool => 1 },
    titles     => { minlength => 1, sort_keys => 'lang', aoh => {
        lang      => { enum => \%LANGUAGE },
        mtl       => { anybool => 1 },
        title     => { required => 0, default => undef, maxlength => 300 },
        latin     => { required => 0, default => undef, maxlength => 300 },
    } },
    # Titles fetched from the VN entry, for auto-filling
    vntitles   => { _when => 'out', aoh => {
        lang      => {},
        title     => {},
        latin     => { required => 0 },
    } },
    olang      => { enum => \%LANGUAGE, default => 'ja' },
    platforms  => { aoh => { platform => { enum => \%PLATFORM } } },
    media      => { aoh => {
        medium    => { enum => \%MEDIUM },
        qty       => { uint => 1, range => [0,40] },
    } },
    gtin       => { gtin => 1 },
    catalog    => { required => 0, default => '', maxlength => 50 },
    released   => { default => 99999999, min => 1, rdate => 1 },
    minage     => { required => 0, default => undef, int => 1, enum => \%AGE_RATING },
    uncensored => { undefbool => 1 },
    reso_x     => { uint => 1, range => [0,32767] },
    reso_y     => { uint => 1, range => [0,32767] },
    voiced     => { uint => 1, enum => \%VOICED },
    ani_story  => { uint => 1, enum => \%ANIMATED },
    ani_ero    => { uint => 1, enum => \%ANIMATED },
    ani_story_sp => { required => 0, uint => 1, range => [0,32767] },
    ani_story_cg => { required => 0, uint => 1, range => [0,32767] },
    ani_cutscene => { required => 0, uint => 1, range => [0,32767] },
    ani_ero_sp   => { required => 0, uint => 1, range => [0,32767] },
    ani_ero_cg   => { required => 0, uint => 1, range => [0,32767] },
    ani_face   => { undefbool => 1 },
    ani_bg     => { undefbool => 1 },
    website    => { required => 0, default => '', weburl => 1 },
    engine     => { required => 0, default => '', maxlength => 50 },
    extlinks   => validate_extlinks('r'),
    notes      => { required => 0, default => '', maxlength => 10240 },
    vn         => { sort_keys => 'vid', aoh => {
        vid    => { vndbid => 'v' },
        title  => { _when => 'out' },
        rtype  => { default => 'complete', enum => \%RELEASE_TYPE },
    } },
    producers  => { sort_keys => 'pid', aoh => {
        pid       => { vndbid => 'p' },
        developer => { anybool => 1 },
        publisher => { anybool => 1 },
        name      => { _when => 'out' },
    } },
    hidden     => { anybool => 1 },
    locked     => { anybool => 1 },

    authmod    => { _when => 'out', anybool => 1 },
    editsum    => { _when => 'in out', editsum => 1 },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;
my $FORM_CMP = form_compile cmp => $FORM;

sub to_extlinks { $_[0]{extlinks} = { map +($_, delete $_[0]{$_}), grep /^l_/, keys $_[0]->%* } }


TUWF::get qr{/$RE{rrev}/(?<action>edit|copy)} => sub {
    my $e = db_entry tuwf->captures('id', 'rev') or return tuwf->resNotFound;
    my $copy = tuwf->capture('action') eq 'copy';
    return tuwf->resDenied if !can_edit r => $copy ? {} : $e;

    $e->{editsum} = $copy ? "Copied from $e->{id}.$e->{chrev}" : $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";
    $e->{authmod} = auth->permDbmod;

    $e->{titles} = [ sort { $a->{lang} cmp $b->{lang} } $e->{titles}->@* ];
    to_extlinks $e;

    $e->{vntitles} = $e->{vn}->@* == 1 ? tuwf->dbAlli('SELECT lang, title, latin FROM vn_titles WHERE id =', \$e->{vn}[0]{vid}) : [];

    enrich_merge vid => sql('SELECT id AS vid, title[1+1] FROM', vnt, 'v WHERE id IN'), $e->{vn};
    enrich_merge pid => sql('SELECT id AS pid, title[1+1] AS name FROM', producerst, 'p WHERE id IN'), $e->{producers};

    $e->@{qw/gtin catalog extlinks/} = elm_empty($FORM_OUT)->@{qw/gtin catalog extlinks/} if $copy;

    my $title = ($copy ? 'Copy ' : 'Edit ').titleprefs_obj($e->{olang}, $e->{titles})->[1];
    framework_ title => $title, dbobj => $e, tab => tuwf->capture('action'),
    sub {
        editmsg_ r => $e, $title, $copy;
        elm_ ReleaseEdit => $FORM_OUT, $copy ? {%$e, id=>undef} : $e;
    };
};


TUWF::get qr{/$RE{vid}/add}, sub {
    return tuwf->resDenied if !can_edit r => undef;
    my $v = tuwf->dbRowi('SELECT id, title FROM', vnt, 'v WHERE NOT hidden AND v.id =', \tuwf->capture('id'));
    return tuwf->resNotFound if !$v->{id};

    my $delrel = tuwf->dbAlli('SELECT r.id, r.title FROM', releasest, 'r JOIN releases_vn rv ON rv.id = r.id WHERE r.hidden AND rv.vid =', \$v->{id}, 'ORDER BY id');
    enrich_flatten languages => id => id => 'SELECT id, lang FROM releases_titles WHERE id IN', $delrel;

    my $e = {
        elm_empty($FORM_OUT)->%*,
        vn       => [{vid => $v->{id}, title => $v->{title}[1], rtype => 'complete'}],
        vntitles => tuwf->dbAlli('SELECT lang, title, latin FROM vn_titles WHERE id =', \$v->{id}),
        official => 1,
    };
    $e->{authmod} = auth->permDbmod;

    framework_ title => "Add release to $v->{title}[1]",
    sub {
        editmsg_ r => undef, "Add release to $v->{title}[1]";

        article_ sub {
            h1_ 'Deleted releases';
            div_ class => 'warning', sub {
                p_ q{This visual novel has releases that have been deleted
                    before. Please review this list to make sure you're not
                    adding a release that has already been deleted.};
                br_;
                ul_ sub {
                    li_ sub {
                        txt_ '['.join(',', $_->{languages}->@*)."] $_->{id}:";
                        a_ href => "/$_->{id}", tattr $_;
                    } for @$delrel;
                }
            }
        } if @$delrel;

        elm_ ReleaseEdit => $FORM_OUT, $e;
    };
};


elm_api ReleaseEdit => $FORM_OUT, $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or return tuwf->resNotFound;
    return elm_Unauth if !can_edit r => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }

    if($data->{patch}) {
        $data->{doujin} = $data->{voiced} = $data->{ani_story} = $data->{ani_ero} = 0;
        $data->{reso_x} = $data->{reso_y} = 0;
        $data->{ani_story_sp} = $data->{ani_story_cg} = $data->{ani_cutscene} = $data->{ani_ero_sp} = $data->{ani_ero_cg} = $data->{ani_face} = $data->{ani_bg} = undef;
        $data->{engine} = '';
    }
    if(!$data->{has_ero}) {
        $data->{uncensored} = undef;
        $data->{ani_ero} = 0;
        $data->{ani_ero_sp} = $data->{ani_ero_cg} = undef;
    }
    ani_compat($data, $e);

    die "No title in main language" if !grep $_->{lang} eq $data->{olang}, $data->{titles}->@*;

    $_->{qty} = $MEDIUM{$_->{medium}}{qty} ? $_->{qty}||1 : 0 for $data->{media}->@*;
    $data->{notes} = bb_subst_links $data->{notes};
    die "No VNs selected" if !$data->{vn}->@*;
    die "Invalid resolution: ($data->{reso_x},$data->{reso_y})" if (!$data->{reso_x} && $data->{reso_y} > 1) || ($data->{reso_x} && !$data->{reso_y});

    to_extlinks $e;

    return elm_Unchanged if !$new && !form_changed $FORM_CMP, $data, $e;

    $data->{$_} = $data->{extlinks}{$_} for $data->{extlinks}->%*;
    delete $data->{extlinks};

    my $ch = db_edit r => $e->{id}, $data;
    elm_Redirect "/$ch->{nitemid}.$ch->{nrev}";
};


# Set the old ani_story and ani_ero fields to some sort of value based on the
# new ani_* fields, if they've been changed.
sub ani_compat {
    my($r, $old) = @_;
    return if !grep +($r->{$_}//'_undef_') ne ($old->{$_}//'_undef_'),
        qw{ ani_story_sp ani_story_cg ani_cutscene ani_ero_sp ani_ero_cg ani_face ani_bg };

    my sub known($) { defined $r->{"ani_$_[0]"} }
    my sub hasani($) { $r->{"ani_$_[0]"} && $r->{"ani_$_[0]"} > 1 }
    my sub someani($) { hasani $_[0] && ($r->{"ani_$_[0]"} & 512) == 0 }
    my sub fullani($) { defined $r->{"ani_$_[0]"} && ($r->{"ani_$_[0]"} & 512) > 0 }

    $r->{ani_story} =
        !known  'story_sp' && !known  'story_cg' && !known  'cutscene' ? 0 :
        !hasani 'story_sp' && !hasani 'story_cg' && !hasani 'cutscene' ? 1 :
        (fullani 'story_sp' || fullani 'story_cg') && !(someani 'story_sp' || someani 'story_cg') ? 4 : 3;

    $r->{ani_ero} =
        !known  'ero_sp' && !known  'ero_cg' ? 0 :
        !hasani 'ero_sp' && !hasani 'ero_cg' ? 1 :
        (fullani 'ero_sp' || fullani 'ero_cg') && !(someani 'ero_sp' || someani 'ero_cg') ? 4 : 3;

    $r->{ani_story} = 2 if $r->{ani_story} < 2 && ($r->{ani_face} || $r->{ani_bg});
}


1;
