package VNWeb::Misc::ImageUpload;

use VNWeb::Prelude;
use VNWeb::Images::Lib;
use AnyEvent::Util;


TUWF::post qr{/elm/ImageUpload.json}, sub {
    if(!auth->csrfcheck(tuwf->reqHeader('X-CSRF-Token')||'')) {
        warn "Invalid CSRF token in request\n";
        return elm_CSRF;
    }
    return elm_Unauth if !auth->permEdit;

    my $type = tuwf->validate(post => type => { enum => [qw/cv ch sf/] })->data;
    my $imgdata = tuwf->reqUploadRaw('img');
    return elm_ImgFormat if $imgdata !~ /^(\xff\xd8|\x89\x50)/; # JPG or PNG header

    my $seq = {qw/sf screenshots_seq cv covers_seq ch charimg_seq/}->{$type}||die;
    my $id = tuwf->dbVali('INSERT INTO images', {
        id     => sql_func(vndbid => \$type, sql(sql_func(nextval => \$seq), '::int')),
        width  => 0,
        height => 0
    }, 'RETURNING id');

    my $fn0 = tuwf->imgpath($id, 0);
    my $fn1 = tuwf->imgpath($id, 1);
    my $fntmp = "$fn0-tmp.jpg";

    sub resize { (-resize => "$_[0][0]x$_[0][1]>", -print => 'r:%wx%h') }
    my @unsharp = (-unsharp => '0x0.75+0.75+0.008');
    my @cmd = (
        config->{convert_path}, '-',
        '-strip', -define => 'filter:Lagrange',
        -background => '#fff', -alpha => 'Remove',
        -quality => 90, -print => 'o:%wx%h',
        $type eq 'ch' ? (resize(tuwf->{ch_size}), -write => $fn0, @unsharp, $fntmp) :
        $type eq 'cv' ? (resize(tuwf->{cv_size}), -write => $fn0, @unsharp, $fntmp) :
        $type eq 'sf' ? (-write => $fn0, resize(tuwf->{scr_size}), @unsharp, $fn1) : die
    );

    run_cmd(\@cmd, '<', \$imgdata, '>', \my $out, '2>', \my $err)->recv;
    warn "convert STDERR: $err" if $err;
    if(!-f $fn0 || $out !~ /^o:([0-9]+)x([0-9]+)r:([0-9]+)x([0-9]+)/) {
        warn "convert STDOUT: $out" if $out;
        warn "Failed to run convert\n";
        unlink $fn0;
        unlink $fn1;
        unlink $fntmp;
        return elm_ImgFormat;
    }
    my($ow,$oh,$rw,$rh) = ($1,$2, $type eq 'sf' ? ($1,$2) : ($3,$4));
    tuwf->dbExeci('UPDATE images SET', { width => $rw, height => $rh }, 'WHERE id =', \$id);

    rename $fntmp, $fn0 if $ow*$oh > $rw*$rh; # Use the -unsharp'ened image if we did a resize
    unlink $fntmp;

    chmod 0666, $fn0;
    chmod 0666, $fn1;

    my $l = [{id => $id}];
    enrich_image 1, $l;
    elm_ImageResult $l;
};


elm_api Image => undef, { id => { vndbid => [qw/ch cv sf/] } }, sub {
    my($data) = @_;
    my $l = tuwf->dbAlli('SELECT id FROM images WHERE id =', \$data->{id});
    enrich_image 0, $l;
    elm_ImageResult $l;
};

1;
