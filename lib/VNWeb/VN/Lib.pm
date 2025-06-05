package VNWeb::VN::Lib;

use VNWeb::Prelude;
use VNWeb::Images::Lib;
use Exporter 'import';

our @EXPORT = qw/ sql_vnimage VNIMAGE enrich_vnimage /;

# Returns a 'vnimage' column that takes the user's vnimage preference into account.
# Doesn't fetch the user's preferred vn_image_vote, use enrich_vnimage() for that.
sub sql_vnimage :prototype() {
    ['c_image', 'c_imgfirst', 'c_imglast']->[ VNWeb::Auth::auth()->pref('vnimage')||0 ].' AS vnimage'
}


sub VNIMAGE :prototype() { RAW sql_vnimage }

# Replaces the 'vnimage' field with an image object.
# Fetches the user's vn_image_vote instead of the VN-provided image when the user has voted.
sub enrich_vnimage($l) {
    if (auth) {
        my $custom = fu->SQL(
            'SELECT vid, img FROM vn_image_votes
              WHERE c_main AND uid =', auth->uid, 'AND vid', IN [ map $_->{id}, @$l ]
        )->kvv;
        $_->{vnimage} = $custom->{$_->{id}} for grep $custom->{$_->{id}}, @$l;
    }
    enrich_image_obj vnimage => $l;
}


# List of official producers for this VN, used by Chars::Edit to determine if
# the a character can be linked to relevant VNs.
sub charproducers($vid) {
    fu->SQL('
        SELECT DISTINCT ON (p.id) p.id, p.title[2]
          FROM releases_vn rv
          JOIN releases r ON r.id = rv.id
          JOIN releases_producers rp ON rp.id = rv.id
          JOIN', PRODUCERST, 'p ON rp.pid = p.id
         WHERE rv.vid =', $vid, "AND r.official AND NOT rv.rtype = 'trial'
         ORDER BY p.id
   ")->allh;
}

1;
