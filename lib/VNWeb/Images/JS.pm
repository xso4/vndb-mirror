package VNWeb::Images::JS;

use VNWeb::Prelude;
use VNWeb::Images::Lib;
use AnyEvent::Util;


# Fetch info about an image
my $OUT = form_compile $IMGSCHEMA;

js_api 'Image', { id => { vndbid => [qw/ch cv sf/] } }, sub {
    my $r = {id=>$_[0]{id}};
    enrich_image 0, [$r];
    fu->notfound if !$r->{width};
    $OUT->coerce($r);
};


FU::post '/js/ImageUpload.json', sub {
    # Have to require the samesite cookie here as CSRF protection, because this API can be triggered as a regular HTML form post.
    fu->denied if !samesite || !(auth->permDbmod || (auth->permEdit && !global_settings->{lockdown_edit}));

    my $body = fu->multipart;
    my($type) = grep $_->name eq 'type', @$body;
    fu->notfound if !$type;
    $type = $type->value;
    fu->notfound if $type !~ /^(cv|ch|sf)$/;

    my($imgdata) = grep $_->name eq 'img', @$body;
    fu->notfound if !$imgdata;

    my $header = $imgdata->substr(0, 16);
    my $fmt =
        $header =~ /^\xff\xd8/ ? 'jpg' :
        $header =~ /^\x89\x50/ ? 'png' :
        $header =~ /^RIFF....WEBP/s ? 'webp' :
        $header =~ /^....ftyp/s ? 'avif' : # Considers every heif file to be AVIF, not entirely correct but works fine.
        $header =~ /^\xff\x0a/ ? 'jxl' :
        $header =~ /^\x00\x00\x00\x00\x0CJXL / ? 'jxl' :
        fu->send_json({_err => 'Unsupported image format'});

    my $seq = {qw/sf screenshots_seq cv covers_seq ch charimg_seq/}->{$type};
    my $id = fu->SQL('INSERT INTO images', VALUES({
        id       => RAW('vndbid('.fu->db_conn->escape_literal($type).', nextval('.fu->db_conn->escape_literal($seq).'))'),
        uploader => auth->uid,
        width    => 0,
        height   => 0
    }), 'RETURNING id')->val;

    my $fno = imgpath($id, 'orig', $fmt);
    my $fn0 = imgpath($id);
    my $fn1 = imgpath($id, 't');
    $imgdata->save($fno);

    my $rc = run_cmd(
         [
             config->{imgproc_path},
             $type eq 'ch' ? (fit => config->{ch_size}->@*, size => jpeg => 1) :
             $type eq 'cv' ? (size => jpeg => 1 => fit => config->{cv_size}->@*, jpeg => 3) :
             $type eq 'sf' ? (size => jpeg => 1 => fit => config->{scr_size}->@*, jpeg => 3) : die
         ],
         '<', $fno, '>', $fn0, '2>', \my $err,
         $type eq 'sf' || $type eq 'cv' ? ('3>', $fn1) : (),
         close_all => 1,
         on_prepare => sub { %ENV = () },
    )->recv;
    chomp($err);

    my sub cleanup {
        unlink $fno;
        unlink $fn0;
        unlink $fn1;
        fu->db->rollback;
    }

    if($rc || !-s $fn0 || $err !~ /^([0-9]+)x([0-9]+)$/) {
        warn "imgproc: $err\n" if $err;
        warn "Failed to run imgproc for $id\n";
        # keep original for troubleshooting
        rename $fno, config->{var_path}."/tmp/error-${id}.${fmt}";
        cleanup;
        fu->send_json({_err => 'Invalid image'});
    }
    my($w,$h) = ($1,$2);

    if (-s $fn0 >= 10*1024*1024) {
        cleanup;
        fu->send_json({_err => 'Encoded image too large, try a lower resolution'});
    }

    fu->SQL('UPDATE images', SET({ width => $w, height => $h }), 'WHERE id =', $id)->exec;
    chmod 0666, $fno;
    chmod 0666, $fn0;
    chmod 0666, $fn1;

    my @l = ({id => $id});
    enrich_image 1, \@l;
    fu->send_json($OUT->coerce(@l));
};

1;
