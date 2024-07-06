# This module is responsible for generating elm/Gen/*;
#
# It exports an `elm_api` function to create an API endpoint, type definitions,
# a JSON encoder and HTML5 validation attributes to simplify and synchronize
# forms.
#
# It also exports an `elm_Response` function for each possible API response
# (see %apis below).

package VNWeb::Elm;

use v5.36;
use TUWF;
use Exporter 'import';
use List::Util 'max';
use VNDB::Config;
use VNDB::Types;
use VNDB::Func 'fmtrating';
use VNDB::ExtLinks ();
use VNDB::Skins;
use VNWeb::Validation;
use VNWeb::Auth;

our @EXPORT = qw/
    elm_api elm_empty
/;


# API response types and arguments. To generate an API response from Perl, call
# elm_ResponseName(@args), e.g.:
#
#   elm_Changed $id, $revision;
#
# These API responses are available in Elm in the `Gen.Api.Response` union type.
our %apis = (
    Unauth         => [], # Not authorized
    Unchanged      => [], # No changes
    Success        => [],
    Redirect       => [{}], # Redirect to the given URL
    Invalid        => [], # POST data did not validate the schema
    Editsum        => [], # Invalid edit summary
    Content        => [{}], # Rendered HTML content (for markdown/bbcode APIs)
    ImgFormat      => [], # Unrecognized image format
    LabelId        => [{uint => 1}], # Label created
    DupNames       => [ { aoh => { # Duplicate names/aliases (for tags & traits)
        id       => { vndbid => ['i','g'] },
        name     => {},
    } } ],
    Releases       => [ { aoh => { # Response to 'Release'
        id       => { vndbid => 'r' },
        title    => {},
        alttitle => { default => '' },
        released => { uint => 1 },
        rtype    => {},
        reso_x   => { uint => 1 },
        reso_y   => { uint => 1 },
        lang     => { type => 'array', values => {} },
        platforms=> { type => 'array', values => {} },
    } } ],
    Resolutions    => [ { aoh => { # Response to 'Resolutions'
        resolution   => {},
        count        => { uint => 1 },
    } } ],
    Engines        => [ { aoh => { # Response to 'Engines'
        engine   => {},
        count    => { uint => 1 },
    } } ],
    DRM            => [ { aoh => { # Response to 'DRM'
        name     => {},
        count    => { uint => 1 },
    } } ],
    BoardResult    => [ { aoh => { # Response to 'Boards'
        btype    => { enum => \%BOARD_TYPE },
        iid      => { default => undef, vndbid => ['p','v','u'] },
        title    => { default => undef },
    } } ],
    TagResult      => [ { aoh => { # Response to 'Tags'
        id           => { vndbid => 'g' },
        name         => {},
        searchable   => { anybool => 1 },
        applicable   => { anybool => 1 },
        hidden       => { anybool => 1 },
        locked       => { anybool => 1 },
    } } ],
    TraitResult    => [ { aoh => { # Response to 'Traits'
        id           => { vndbid => 'i' },
        name         => {},
        searchable   => { anybool => 1 },
        applicable   => { anybool => 1 },
        defaultspoil => { uint => 1 },
        hidden       => { anybool => 1 },
        locked       => { anybool => 1 },
        group_id     => { default => undef, vndbid => 'i' },
        group_name   => { default => undef },
    } } ],
    VNResult       => [ { aoh => { # Response to 'VN'
        id       => { vndbid => 'v' },
        title    => {},
        hidden   => { anybool => 1 },
    } } ],
    ProducerResult => [ { aoh => { # Response to 'Producers'
        id       => { vndbid => 'p' },
        name     => {},
        altname  => { default => undef },
    } } ],
    StaffResult    => [ { aoh => { # Response to 'Staff'
        id       => { vndbid => 's' },
        lang     => {},
        aid      => { id => 1 },
        title    => {},
        alttitle => {},
    } } ],
    CharResult     => [ { aoh => { # Response to 'Chars'
        id       => { vndbid => 'c' },
        title    => {},
        alttitle => {},
        main     => { default => undef, type => 'hash', keys => {
            id       => { vndbid => 'c' },
            title    => {},
            alttitle => {},
        } }
    } } ],
    AnimeResult => [ { aoh => { # Response to 'Anime'
        id       => { id => 1 },
        title    => {},
        original => { default => '' },
    } } ],
    ImageResult => [ { aoh => { # Response to 'Images'
        id              => { vndbid => ['ch','cv','sf'] },
        token           => { default => undef },
        width           => { uint => 1 },
        height          => { uint => 1 },
        votecount       => { uint => 1 },
        sexual          => { uint => 1, range => [0,2] },
        sexual_avg      => { num => 1, default => undef },
        sexual_stddev   => { num => 1, default => undef },
        violence        => { uint => 1, range => [0,2] },
        violence_avg    => { num => 1, default => undef },
        violence_stddev => { num => 1, default => undef },
        my_sexual       => { uint => 1, default => undef },
        my_violence     => { uint => 1, default => undef },
        my_overrule     => { anybool => 1 },
        entries         => { aoh => {
            id       => {},
            title    => {},
        } },
        votes           => { unique => 0, aoh => {
            user     => {},
            uid      => { vndbid => 'u', default => undef },
            sexual   => { uint => 1 },
            violence => { uint => 1 },
            ignore   => { anybool => 1 },
        } },
    } } ],
);
# (These references to other API results cause redundant Elm code - can be deduplicated)
$apis{AdvSearchQuery} = [ { type => 'hash', keys => { # Response to 'AdvSearchLoad'
        qtype        => {},
        query        => { type => 'any' },
        producers    => $apis{ProducerResult}[0],
        staff        => $apis{StaffResult}[0],
        tags         => $apis{TagResult}[0],
        traits       => $apis{TraitResult}[0],
        anime        => $apis{AnimeResult}[0],
} } ];
$apis{UListWidget} = [ { type => 'hash', keys => { # Initialization for UList.Widget and response to UListWidget
        uid      => { vndbid => 'u' },
        vid      => { vndbid => 'v' },
        # Only includes selected labels, null if the VN is not on the list at all.
        labels   => { default => undef, aoh => { id => { int => 1 }, label => {default => ''} } },
        # Can be set to null to lazily load the extra data as needed
        full     => { default => undef, type => 'hash', keys => {
            title     => {},
            labels    => { aoh => { id => { int => 1 }, label => {}, private => { anybool => 1 } } },
            canvote   => { anybool => 1 },
            canreview => { anybool => 1 },
            vote      => { vnvote => 1 },
            review    => { default => undef, vndbid => 'w' },
            notes     => { default => '' },
            started   => { default => '' },
            finished  => { default => '' },
            releases  => $apis{Releases}[0],
            rlist     => { aoh => { id => { vndbid => 'r' }, status => { uint => 1 } } },
        } },
} } ];


# Compile %apis into a %schema and generate the elm_Response() functions
my %schemas;
for my $name (keys %apis) {
    no strict 'refs';
    $schemas{$name} = [ map tuwf->compile($_), $apis{$name}->@* ];
    *{'elm_'.$name} = sub {
        my @args = map {
            $schemas{$name}[$_]->validate($_[$_])->data if tuwf->debug;
            $schemas{$name}[$_]->analyze->coerce_for_json($_[$_], unknown => 'reject')
        } 0..$#{$schemas{$name}};
        tuwf->resJSON({$name, \@args})
    };
    push @EXPORT, 'elm_'.$name;
}




# Formatting functions
sub indent    { $_[0] =~ s/\n/\n  /gr }
sub list      { indent "\n[ ".join("\n, ", @_)."\n]" }
sub string :prototype($) { '"'.($_[0] =~ s/([\\"])/\\$1/gr).'"' }
sub tuple     { '('.join(', ', @_).')' }
sub to_camel  { (ucfirst $_[0]) =~ s/_([a-z])/'_'.uc $1/egr; }

# Generate a variable definition: name, type, value
sub def       { sprintf "\n%s : %s\n%1\$s = %s\n", @_; }


# Generate an Elm type definition corresponding to a TUWF::Validate schema
sub def_type {
    my($name, $obj) = @_;
    my $data = '';
    my @keys = $obj->{keys} ? grep $obj->{keys}{$_}{keys}||($obj->{keys}{$_}{values}&&$obj->{keys}{$_}{values}{keys}), sort keys $obj->{keys}->%* : ();

    $data .= def_type($name . to_camel($_), $obj->{keys}{$_}{values} || bless { $obj->{keys}{$_}->%*, required => 1 }, ref $obj->{keys}{$_} ) for @keys;

    $data .= sprintf "\ntype alias %s = %s\n\n", $name, $obj->elm_type(
        any => 'JE.Value',
        keys => +{ map {
            my $t = $obj->{keys}{$_};
            my $n = $name . to_camel($_);
            $n = "List $n" if $t->{values};
            $n = "Maybe ($n)" if $t->{values} && !$t->{required} && !defined $t->{default};
            $n = "Maybe $n" if $t->{keys} && !$t->{required} && !defined $t->{default};
            ($_, $n)
        } @keys }
    );
    $data
}


# Generate HTML5 validation attribute lists corresponding to a TUWF::Validate schema
# TODO: Deduplicate some regexes (weburl, email)
# TODO: Throw these inside a struct for better namespacing?
sub def_validation {
    my($name, $obj) = @_;
    $obj = $obj->{values} if $obj->{values};
    my $data = '';

    $data .= def_validation($name . to_camel($_), $obj->{keys}{$_}) for $obj->{keys} ? sort keys $obj->{keys}->%* : ();

    my %v = $obj->html5_validation();
    $data .= def $name, 'List (Html.Attribute msg)', '[ '.join(', ',
        $v{required}          ? 'A.required True' : (),
        defined $v{minlength} ? "A.minlength $v{minlength}" : (),
        defined $v{maxlength} ? "A.maxlength $v{maxlength}" : (),
        defined $v{min}       ? 'A.min '.string($v{min}) : (),
        defined $v{max}       ? 'A.max '.string($v{max}) : (),
        $v{pattern}           ? 'A.pattern '.string($v{pattern}) : ()
    ).']' if !$obj->{keys};
    $data;
}


# Generate an Elm JSON encoder taking a corresponding def_type() as input
sub encoder {
    my($name, $type, $obj) = @_;
    def $name, "$type -> JE.Value", $obj->elm_encoder(any => ' ', json_encode => 'JE.');
}




sub write_module {
    my($module, $contents) = @_;
    my $fn = sprintf '%s/elm/Gen/%s.elm', config->{gen_path}, $module;

    # The imports aren't necessary in all the files, but might as well add them.
    $contents = <<~"EOF";
        -- This file is automatically generated from lib/VNWeb/Elm.pm.
        -- Do not edit, your changes will be lost.
        module Gen.$module exposing (..)
        import Dict
        import Http
        import Html
        import Html.Attributes as A
        import Json.Encode as JE
        import Json.Decode as JD
        $contents
        EOF

    # Don't write anything if the file hasn't changed.
    my $oldcontents = do {
        local $/=undef; my $F;
        open($F, '<:utf8', $fn) ? <$F> : '';
    };
    return if $oldcontents eq $contents;

    open my $F, '>:utf8', $fn or die "$fn: $!";
    print $F $contents;
}




# Create an API endpoint that can be called from Elm.
# Usage:
#
#   elm_api FormName => $OUT_SCHEMA, $IN_SCHEMA, sub {
#       my($data) = @_;
#       elm_Success # Or any other elm_Response() function
#   }, %extra_schemas;
#
# That will create an endpoint at `POST /elm/FormName.json` that accepts JSON
# data that must validate $IN_SCHEMA. The subroutine is given the validated
# data as argument.
#
# It will also create an Elm module called `Gen.FormName` with the following definitions:
#
#   -- Elm type corresponding to $OUT_SCHEMA
#   type alias Recv = { .. }
#   -- Elm type corresponding to $IN_SCHEMA
#   type alias Send = { .. }
#   -- HTML Validation attributes corresponding to fields in `Send`
#   valFieldName : List Html.Attribute
#
#   -- Command to send an API request to the endpoint and receive a response
#   send : Send -> (Gen.Api.Response -> msg) -> Cmd msg
#
# Extra type aliases can be added using %extra_schemas.
sub elm_api {
    my($name, $out, $in, $sub, %extra) = @_;

    my sub comp { ref $_[0] eq 'HASH' ? tuwf->compile({ type => 'hash', keys => $_[0] }) : $_[0] }
    $in = comp $in;

    TUWF::post qr{/elm/\Q$name\E\.json} => sub {
        my $data = tuwf->validate(json => $in);
        # Handle failure of the 'editsum' validation as a special case and return elm_Editsum().
        if(!$data && $data->err->{errors} && grep $_->{validation} eq 'editsum' || ($_->{validation} eq 'required' && $_->{key} eq 'editsum'), $data->err->{errors}->@*) {
            return elm_Editsum();
        }
        if(!$data) {
            warn "JSON validation failed\ninput: " . JSON::XS->new->allow_nonref->pretty->canonical->encode(tuwf->reqJSON) . "\nerror: " . JSON::XS->new->encode($data->err) . "\n";
            return elm_Invalid();
        }

        $sub->($data->data);
        warn "Non-JSON response to a json_api request, is this intended?\n" if tuwf->resHeader('Content-Type') !~ /^application\/json/;
    };

    if(tuwf->{elmgen}) {
        my $data = "import Gen.Api as GApi\n";
        $data .=   "import Lib.Api as Api\n";
        $data .= def_type Recv => comp($out)->analyze if $out;
        $data .= def_type Send => $in->analyze;
        $data .= def_type $_ => comp($extra{$_})->analyze for sort keys %extra;
        $data .= def_validation val => $in->analyze;
        $data .= encoder encode => 'Send', $in->analyze;
        $data .= "send : Send -> (GApi.Response -> msg) -> Cmd msg\n";
        $data .= "send v m = Api.post \"$name\" (encode v) m\n";
        write_module $name, $data;
    }
}


# Return a new, empty value that conforms to the given schema and can be parsed
# by the generated Elm/json decoder for the same schema.  It may not actually
# validate according to the schema (e.g. required fields may be left empty).
# Values are initialized as follows:
# - If a 'default' has been set in the schema, that will be used.
# - Nullable fields are initialized to undef
# - Integers are initialized to 0
# - Strings are initialized to ""
# - Arrays are initialized to []
sub elm_empty {
    my($schema) = @_;
    $schema = $schema->analyze if ref $schema eq 'TUWF::Validate';
    return $schema->{default} if exists $schema->{default};
    return undef if !$schema->{required};
    return [] if $schema->{type} eq 'array';
    return '' if $schema->{type} eq 'bool' || $schema->{type} eq 'scalar';
    return 0  if $schema->{type} eq 'num'  || $schema->{type} eq 'int';
    return +{ map +($_, elm_empty($schema->{keys}{$_})), $schema->{keys} ? keys $schema->{keys}->%* : () } if $schema->{type} eq 'hash';
    die "Unable to initialize required value of type '$schema->{type}' without a default";
}


# Generate the Gen.Api module with the Response type and decoder.
sub write_api {

    # Extract all { type => 'hash' } schemas and give them their own
    # definition, so that it's easy to refer to those records in other places
    # of the Elm code, similar to def_type().
    my(@union, @decode);
    my $data = '';
    my $len = max map length, keys %schemas;
    for (sort keys %schemas) {
        my($name, $schema) = ($_, $schemas{$_});
        my $def = $name;
        my $dec = sprintf 'JD.field "%s"%s <| %s', $name,
            ' 'x($len-(length $name)),
            @$schema == 0 ? "JD.succeed $name" :
            @$schema == 1 ? "JD.map $name"     : sprintf 'JD.map%d %s', scalar @$schema, $name;
        my $tname = "Api$name";
        for my $argn (0..$#$schema) {
            my $arg = $schema->[$argn]->analyze();
            my $jd = $arg->elm_decoder(json_decode => 'JD.', level => 3);
            $dec .= " (JD.index $argn $jd)";
            if($arg->{keys}) {
                $data .= def_type $tname, $arg;
                $def .= " $tname";
            } elsif($arg->{values} && $arg->{values}{keys}) {
                $data .= def_type $tname, $arg->{values};
                $def .= " (List $tname)";
            } else {
                $def .= ' '.$arg->elm_type();
            }
        }
        push @union, $def;
        push @decode, $dec;
    }
    $data .= sprintf "\ntype Response\n  = HTTPError Http.Error\n  | %s\n", join "\n  | ", @union;
    $data .= sprintf "\ndecode : JD.Decoder Response\ndecode = JD.oneOf\n  [ %s\n  ]", join "\n  , ", @decode;

    write_module Api => $data;
};


sub write_types {
    my $data = '';

    $data .= def languages  => 'List (String, String)' => list map tuple(string $_, string $LANGUAGE{$_}{txt}), sort { $LANGUAGE{$a}{txt} cmp $LANGUAGE{$b}{txt} } keys %LANGUAGE;
    $data .= def platforms  => 'List (String, String)' => list map tuple(string $_, string $PLATFORM{$_}), keys %PLATFORM;
    $data .= def releaseTypes => 'List (String, String)' => list map tuple(string $_, string $RELEASE_TYPE{$_}), keys %RELEASE_TYPE;
    $data .= def media      => 'List (String, String, Bool)' => list map tuple(string $_, string $MEDIUM{$_}{txt}, $MEDIUM{$_}{qty}?'True':'False'), keys %MEDIUM;
    $data .= def rlistStatus=> 'List (Int, String)' => list map tuple($_, string $RLIST_STATUS{$_}), keys %RLIST_STATUS;
    $data .= def boardTypes => 'List (String, String)' => list map tuple(string $_, string $BOARD_TYPE{$_}{txt}), keys %BOARD_TYPE;
    $data .= def ratings    => 'List String' => list map string(fmtrating $_), 1..10;
    $data .= def ageRatings => 'List (Int, String)' => list map tuple($_, string $AGE_RATING{$_}{txt}.($AGE_RATING{$_}{ex}?" ($AGE_RATING{$_}{ex})":'')), keys %AGE_RATING;
    $data .= def devStatus  => 'List (Int, String)' => list map tuple($_, string $DEVSTATUS{$_}), keys %DEVSTATUS;
    $data .= def voiced     => 'List (Int, String)' => list map tuple($_, string $VOICED{$_}{txt}), keys %VOICED;
    $data .= def animated   => 'List (Int, String)' => list map tuple($_, string $ANIMATED{$_}{txt}), keys %ANIMATED;
    $data .= def staffGenders => 'List (String, String)' => list map tuple(string $_, string $STAFF_GENDER{$_}), keys %STAFF_GENDER;
    $data .= def charSex    => 'List (String, String)' => list map tuple(string $_, string $CHAR_SEX{$_}), keys %CHAR_SEX;
    $data .= def cupSizes   => 'List (String, String)' => list map tuple(string $_, string $CUP_SIZE{$_}), keys %CUP_SIZE;
    $data .= def bloodTypes => 'List (String, String)' => list map tuple(string $_, string $BLOOD_TYPE{$_}), keys %BLOOD_TYPE;
    $data .= def charRoles  => 'List (String, String)' => list map tuple(string $_, string $CHAR_ROLE{$_}{txt}), keys %CHAR_ROLE;
    $data .= def vnLengths  => 'List (Int, String)' => list map tuple($_, string $VN_LENGTH{$_}{txt}.($VN_LENGTH{$_}{time}?" ($VN_LENGTH{$_}{time})":'')), keys %VN_LENGTH;
    $data .= def vnRelations=> 'List (String, String)' => list map tuple(string $_, string $VN_RELATION{$_}{txt}), keys %VN_RELATION;
    $data .= def creditTypes=> 'List (String, String)' => list map tuple(string $_, string $CREDIT_TYPE{$_}), keys %CREDIT_TYPE;
    $data .= def producerRelations=> 'List (String, String)' => list map tuple(string $_, string $PRODUCER_RELATION{$_}{txt}), keys %PRODUCER_RELATION;
    $data .= def producerTypes=> 'List (String, String)' => list map tuple(string $_, string $PRODUCER_TYPE{$_}), keys %PRODUCER_TYPE;
    $data .= def tagCategories=> 'List (String, String)' => list map tuple(string $_, string $TAG_CATEGORY{$_}), keys %TAG_CATEGORY;
    $data .= def curYear    => Int => (gmtime)[5]+1900;

    write_module Types => $data;
}


sub write_extlinks {
    my $data =<<~'_';
        import Regex

        type alias Site =
          { name  : String
          , advid : String
          }
        _

    my sub links {
        my($name, @links) = @_;
        $data .= def $name.'Sites' => "List (Site)" => list map {
            my $l = $_;
            my $addval = $l->{int} ? 'toint v' : 'v';
            '{ '.join("\n  , ",
                'name  = '.string($l->{name}),
                'advid = '.string($l->{id} =~ s/^l_//r),
            )."\n  }";
        } @links;
    }
    links release => VNDB::ExtLinks::extlinks_sites('r');
    links staff => VNDB::ExtLinks::extlinks_sites('s');

    write_module ExtLinks => $data;
}


if(tuwf->{elmgen}) {
    write_api;
    write_types;
    write_extlinks;
    open my $F, '>', config->{gen_path}.'/elm/Gen/.generated';
    print $F scalar gmtime;
}


1;
