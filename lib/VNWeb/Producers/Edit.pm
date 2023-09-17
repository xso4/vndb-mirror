package VNWeb::Producers::Edit;

use VNWeb::Prelude;


my $FORM = {
    id          => { required => 0, vndbid => 'p' },
    type        => { default => 'co', enum => \%PRODUCER_TYPE },
    name        => { maxlength => 200 },
    latin       => { required => 0, maxlength => 200 },
    alias       => { required => 0, default => '', maxlength => 500 },
    lang        => { enum => \%LANGUAGE },
    website     => { required => 0, default => '', weburl => 1 },
    l_wikidata  => { required => 0, uint => 1, max => (1<<31)-1 },
    description => { required => 0, default => '', maxlength => 5000 },
    relations   => { sort_keys => 'pid', aoh => {
        pid      => { vndbid => 'p' },
        relation => { enum => \%PRODUCER_RELATION },
        name     => { _when => 'out' },
    } },
    hidden      => { anybool => 1 },
    locked      => { anybool => 1 },
    editsum     => { _when => 'in out', editsum => 1 },
};

my $FORM_OUT = form_compile out => $FORM;
my $FORM_IN  = form_compile in  => $FORM;
my $FORM_CMP = form_compile cmp => $FORM;


TUWF::get qr{/$RE{prev}/edit} => sub {
    my $e = db_entry tuwf->captures('id', 'rev') or return tuwf->resNotFound;
    return tuwf->resDenied if !can_edit p => $e;

    $e->{authmod} = auth->permDbmod;
    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";

    enrich_merge pid => sql('SELECT id AS pid, title[1+1] AS name FROM', producerst, 'p WHERE id IN'), $e->{relations};

    my $title = titleprefs_swap @{$e}{qw/ lang name latin /};
    framework_ title => "Edit $title->[1]", dbobj => $e, tab => 'edit',
    sub {
        editmsg_ p => $e, "Edit $title->[1]";
        div_ widget(ProducerEdit => $FORM_OUT, $e), '';
    };
};


TUWF::get qr{/p/add}, sub {
    return tuwf->resDenied if !can_edit p => undef;

    framework_ title => 'Add producer',
    sub {
        editmsg_ p => undef, 'Add producer';
        div_ widget(ProducerEdit => $FORM_OUT, elm_empty $FORM_OUT), '';
    };
};


js_api ProducerEdit => $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or return tuwf->resNotFound;
    return tuwf->resDenied if !can_edit p => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{description} = bb_subst_links $data->{description};
    $data->{alias} =~ s/\n\n+/\n/;

    $data->{relations} = [] if $data->{hidden};
    validate_dbid 'SELECT id FROM producers WHERE id IN', map $_->{pid}, $data->{relations}->@*;
    die "Relation with self" if grep $_->{pid} eq $e->{id}, $data->{relations}->@*;

    return +{ _err => 'No changes.' } if !$new && !form_changed $FORM_CMP, $data, $e;
    my $ch = db_edit p => $e->{id}, $data;
    update_reverse($ch->{nitemid}, $ch->{nrev}, $e, $data);
    +{ _redir => "/$ch->{nitemid}.$ch->{nrev}" };
};


sub update_reverse {
    my($id, $rev, $old, $new) = @_;

    my %old = map +($_->{pid}, $_), $old->{relations} ? $old->{relations}->@* : ();
    my %new = map +($_->{pid}, $_), $new->{relations}->@*;

    # Updates to be performed, pid => { pid => x, relation => y } or undef if the relation should be removed.
    my %upd;

    for my $i (keys %old, keys %new) {
        if($old{$i} && !$new{$i}) {
            $upd{$i} = undef;
        } elsif(!$old{$i} || $old{$i}{relation} ne $new{$i}{relation}) {
            $upd{$i} = {
                pid      => $id,
                relation => $PRODUCER_RELATION{ $new{$i}{relation} }{reverse},
            };
        }
    }

    for my $i (keys %upd) {
        my $e = db_entry $i;
        $e->{relations} = [
            $upd{$i} ? $upd{$i} : (),
            grep $_->{pid} ne $id, $e->{relations}->@*
        ];
        $e->{editsum} = "Reverse relation update caused by revision $id.$rev";
        db_edit p => $i, $e, 'u1';
    }
}

1;
