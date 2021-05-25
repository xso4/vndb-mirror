package VNWeb::Misc::SavePref;

use VNWeb::Prelude;

my @vnlang_keys = (map +($_,"$_-mtl"), keys %LANGUAGE);

TUWF::post qr{/js/save-pref} => sub {
    return tuwf->resDenied if !auth;
    my $prefs = tuwf->validate(json => {type => 'hash', unknown => 'pass'})->data;

    my %vnlang = map exists($prefs->{"vnlang-$_"}) ? ($_, $prefs->{"vnlang-$_"}) : (), @vnlang_keys;
    if(keys %vnlang) {
        my $v = tuwf->dbVali('SELECT vnlang FROM users WHERE id =', \auth->uid);
        $v = $v ? JSON::XS::decode_json($v) : {};
        for(keys %vnlang) {
            delete $v->{$_} if !defined $vnlang{$_};
            $v->{$_} = $vnlang{$_}?\1:\0 if defined $vnlang{$_};
        }
        $v = JSON::XS::encode_json($v);
        tuwf->dbExeci('UPDATE users SET vnlang =', \$v, 'WHERE id =', \auth->uid);
    }
};

1;
