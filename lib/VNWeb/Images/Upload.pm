package VNWeb::Misc::ImageUpload;

use VNWeb::Prelude;
use VNWeb::Images::Lib;
use AnyEvent::Util;


TUWF::post qr{/elm/ImageUpload.json}, sub {
    # Have to require the samesite cookie here as CSRF protection, because this API can be triggered as a regular HTML form post.
    return elm_Unauth if !samesite || !(auth->permDbmod || (auth->permEdit && !global_settings->{lockdown_edit}));

    my $type = tuwf->validate(post => type => { enum => [qw/cv ch sf/] })->data;
    my $imgdata = tuwf->reqUploadRaw('img');
    my $fmt =
        $imgdata =~ /^\xff\xd8/ ? 'jpg' :
        $imgdata =~ /^\x89\x50/ ? 'png' :
        $imgdata =~ /^RIFF....WEBP/s ? 'webp' :
        $imgdata =~ /^....ftyp/s ? 'avif' : # Considers every heif file to be AVIF, not entirely correct but works fine.
        $imgdata =~ /^\xff\x0a/ ? 'jxl' :
        $imgdata =~ /^\x00\x00\x00\x00\x0CJXL / ? 'jxl' : undef;
    return elm_ImgFormat if !$fmt;

    my $seq = {qw/sf screenshots_seq cv covers_seq ch charimg_seq/}->{$type}||die;
    my $id = tuwf->dbVali('INSERT INTO images', {
        id       => sql_func(vndbid => \$type, sql(sql_func(nextval => \$seq), '::int')),
        uploader => \auth->uid,
        width    => 0,
        height   => 0
    }, 'RETURNING id');

    my $fno = imgpath($id, 'orig', $fmt);
    my $fn0 = imgpath($id);
    my $fn1 = imgpath($id, 'thumb');

    {
        open my $F, '>', $fno or die $!;
        print $F $imgdata;
    }

    my $rc = run_cmd(
         [
             config->{imgproc_path},
             $type eq 'ch' ? (fit => config->{ch_size}->@*, size => jpeg => 1) :
             $type eq 'cv' ? (fit => config->{cv_size}->@*, size => jpeg => 1) :
             $type eq 'sf' ? (size => jpeg => 1 => fit => config->{scr_size}->@*, jpeg => 3) : die
         ],
         '<',  \$imgdata,
         '>',  $fn0,
         '2>', \my $err,
         $type eq 'sf' ? ('3>', $fn1) : (),
         close_all => 1,
         on_prepare => sub { %ENV = () },
    )->recv;
    chomp($err);

    if($rc || !-s $fn0 || $err !~ /^([0-9]+)x([0-9]+)$/) {
        warn "imgproc: $err\n" if $err;
        warn "Failed to run imgproc for $id\n";
        # keep original for troubleshooting
        rename $fno, config->{root}."/static/${type}.orig/error-${id}.${fmt}";
        unlink $fn0;
        unlink $fn1;
        tuwf->dbRollBack;
        return elm_ImgFormat;
    }
    my($w,$h) = ($1,$2);
    tuwf->dbExeci('UPDATE images SET', { width => $w, height => $h }, 'WHERE id =', \$id);

    chmod 0666, $fno;
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
