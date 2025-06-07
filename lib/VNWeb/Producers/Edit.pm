package VNWeb::Producers::Edit;

use VNWeb::Prelude;


my($FORM_IN, $FORM_OUT) = form_compile 'in', 'out', {
    id          => { default => undef, vndbid => 'p' },
    type        => { default => 'co', enum => \%PRODUCER_TYPE },
    name        => { sl => 1, maxlength => 200 },
    latin       => { default => undef, sl => 1, maxlength => 200 },
    alias       => { default => '', maxlength => 500 },
    lang        => { enum => \%LANGUAGE },
    description => { default => '', maxlength => 5000 },
    relations   => { sort_keys => 'pid', aoh => {
        pid      => { vndbid => 'p' },
        relation => { enum => \%PRODUCER_RELATION },
        name     => { _when => 'out' },
    } },
    extlinks    => { extlinks => 'p' },
    hidden      => { anybool => 1 },
    locked      => { anybool => 1 },
    editsum     => { editsum => 1 },
};


FU::get qr{/$RE{prev}/edit} => sub($id, $rev=0) {
    my $e = db_entry $id, $rev or fu->notfound;
    fu->denied if !can_edit p => $e;

    $e->{editsum} = $e->{chrev} == $e->{maxrev} ? '' : "Reverted to revision $e->{id}.$e->{chrev}";
    $_->{name} = $_->{title}[1] for $e->{relations}->@*;

    my $title = titleprefs_swap @{$e}{qw/ lang name latin /};
    framework_ title => "Edit $title->[1]", dbobj => $e, tab => 'edit',
    sub {
        editmsg_ p => $e, "Edit $title->[1]";
        div_ widget(ProducerEdit => $FORM_OUT, $e), '';
    };
};


FU::get '/p/add', sub {
    fu->denied if !can_edit p => undef;

    framework_ title => 'Add producer',
    sub {
        editmsg_ p => undef, 'Add producer';
        div_ widget(ProducerEdit => $FORM_OUT, $FORM_OUT->empty), '';
    };
};


js_api ProducerEdit => $FORM_IN, sub {
    my $data = shift;
    my $new = !$data->{id};
    my $e = $new ? { id => 0 } : db_entry $data->{id} or fu->notfound;
    fu->denied if !can_edit p => $e;

    if(!auth->permDbmod) {
        $data->{hidden} = $e->{hidden}||0;
        $data->{locked} = $e->{locked}||0;
    }
    $data->{description} = bb_subst_links $data->{description};
    $data->{alias} =~ s/\n\n+/\n/;

    $data->{relations} = [] if $data->{hidden};
    validate_dbid 'SELECT id FROM producers WHERE id', map $_->{pid}, $data->{relations}->@*;
    return 'Invalid relation with self.' if grep $_->{pid} eq $e->{id}, $data->{relations}->@*;

    VNDB::ExtLinks::normalize $e, $data;

    my $ch = db_edit p => $e->{id}, $data;
    return 'No changes.' if !$ch->{nitemid};
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
