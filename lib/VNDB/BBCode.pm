package VNDB::BBCode;

use v5.36;
use Exporter 'import';

our @EXPORT = qw/bb_format bb_subst_links/;

# Supported BBCode:
#  [b] .. [/b]
#  [i] .. [/i]
#  [u] .. [/u]
#  [s] .. [/s]
#  [spoiler] .. [/spoiler]
#  [quote] .. [/quote]
#  [code] .. [/code]
#  [url=..] [/url]
#  [raw] .. [/raw]
#  link: http://../
#  dblink: v+, v+.+, d+#+, d+#+.+
#
# Permitted nesting of formatting codes:
#  inline = b,i,u,s,spoiler
#  inline  -> inline, url, raw, link, dblink
#  quote   -> anything
#  code    -> nothing
#  url     -> raw
#  raw     -> nothing


# State action function usage:
#   _state_action \@stack, $match, $char_pre, $char_post
# Returns: ($token, @arg) on successful parse, () otherwise.

# Trivial open and close actions
sub _b_start       { if(lc$_[1] eq '[b]')        { push @{$_[0]}, 'b';       ('b_start')       } else { () } }
sub _i_start       { if(lc$_[1] eq '[i]')        { push @{$_[0]}, 'i';       ('i_start')       } else { () } }
sub _u_start       { if(lc$_[1] eq '[u]')        { push @{$_[0]}, 'u';       ('u_start')       } else { () } }
sub _s_start       { if(lc$_[1] eq '[s]')        { push @{$_[0]}, 's';       ('s_start')       } else { () } }
sub _spoiler_start { if(lc$_[1] eq '[spoiler]')  { push @{$_[0]}, 'spoiler'; ('spoiler_start') } else { () } }
sub _quote_start   { if(lc$_[1] eq '[quote]')    { push @{$_[0]}, 'quote';   ('quote_start')   } else { () } }
sub _code_start    { if(lc$_[1] eq '[code]')     { push @{$_[0]}, 'code';    ('code_start')    } else { () } }
sub _raw_start     { if(lc$_[1] eq '[raw]')      { push @{$_[0]}, 'raw';     ('raw_start')     } else { () } }
sub _b_end         { if(lc$_[1] eq '[/b]')       { pop  @{$_[0]}; ('b_end'      ) } else { () } }
sub _i_end         { if(lc$_[1] eq '[/i]')       { pop  @{$_[0]}; ('i_end'      ) } else { () } }
sub _u_end         { if(lc$_[1] eq '[/u]')       { pop  @{$_[0]}; ('u_end'      ) } else { () } }
sub _s_end         { if(lc$_[1] eq '[/s]')       { pop  @{$_[0]}; ('s_end'      ) } else { () } }
sub _spoiler_end   { if(lc$_[1] eq '[/spoiler]') { pop  @{$_[0]}; ('spoiler_end') } else { () } }
sub _quote_end     { if(lc$_[1] eq '[/quote]'  ) { pop  @{$_[0]}; ('quote_end'  ) } else { () } }
sub _code_end      { if(lc$_[1] eq '[/code]'   ) { pop  @{$_[0]}; ('code_end'   ) } else { () } }
sub _raw_end       { if(lc$_[1] eq '[/raw]'    ) { pop  @{$_[0]}; ('raw_end'    ) } else { () } }
sub _url_end       { if(lc$_[1] eq '[/url]'    ) { pop  @{$_[0]}; ('url_end'    ) } else { () } }

sub _url_start {
  if($_[1] =~ m{^\[url=((https?://|/)[^\]>]+)\]$}i) {
    push @{$_[0]}, 'url';
    (url_start => $1)
  } else { () }
}

sub _link {
  my(undef, $match, $char_pre, $char_post) = @_;

  # Tags arent links
  return () if $match =~ /^\[/;

  # URLs (already "validated" in the parsing regex)
  return ('link') if $match =~ /^[hf]t/;

  # Now we're left with various forms of IDs, just need to make sure it's not surrounded by word characters
  return ('dblink') if $char_pre !~ /[\w-]/ && $char_post !~ /[\w-]/;

  ();
}


# Permitted actions to take in each state. The actions are run in order, if
# none succeed then the token is passed through as text.
# The "current state" is the most recent tag in the stack, or '' if no tags are open.
my @INLINE = (\&_link, \&_url_start, \&_raw_start, \&_b_start, \&_i_start, \&_u_start, \&_s_start, \&_spoiler_start);
my %STATE = (
  ''      => [                @INLINE, \&_quote_start, \&_code_start],
  b       => [\&_b_end,       @INLINE],
  i       => [\&_i_end,       @INLINE],
  u       => [\&_u_end,       @INLINE],
  s       => [\&_s_end,       @INLINE],
  spoiler => [\&_spoiler_end, @INLINE],
  quote   => [\&_quote_end,   @INLINE, \&_quote_start, \&_code_start],
  code    => [\&_code_end     ],
  url     => [\&_url_end,     \&_raw_start],
  raw     => [\&_raw_end      ],
);


my %XML = qw/& &amp; < &lt; " &quot;/;
sub xml_escape { $_[0] =~ s/([&<"])/$XML{$1}/gr }


# Usage:
#
#   parse $input, sub {
#     my($raw, $token, @arg) = @_;
#     return 1; # to continue processing, 0 to stop. (Note that _close tokens may still follow after stopping)
#   };
#
#   $raw   = the raw part that has been parsed
#   $token = name of the parsed bbcode token, with some special cases (see below)
#   @arg   = $token-specific arguments.
#
# Tags:
#   text           -> literal text, $raw is the text to display
#   b_start        -> start bold
#   b_end          -> end
#   i_start        -> start italic
#   i_end          -> end
#   u_start        -> start underline
#   u_end          -> end
#   s_start        -> start strike
#   s_end          -> end
#   spoiler_start  -> start a spoiler
#   spoiler_end    -> end
#   quote_start    -> start a quote
#   quote_end      -> end
#   code_start     -> code block
#   code_end       -> end
#   url_start      -> [url=..], $arg[0] contains the url
#   url_end        -> [/url]
#   raw_start      -> [raw]
#   raw_end        -> [/raw]
#   link           -> http://.../, $raw is the link
#   dblink         -> v123, t13.1, etc. $raw is the dblink
#
# This function will ensure correct nesting of _start and _end tokens.
sub parse {
  my($raw, $sub) = @_;
  $raw =~ s/\r//g;
  return if !$raw && $raw ne '0';

  my $last = 0;
  my @stack;

  while($raw =~ m{(?:
    \[ \/? (?i: b|i|u|s|spoiler|quote|code|url|raw ) [^\s\]]* \] |  # tag
    d[1-9][0-9]* \# [1-9][0-9]* (?: \.[1-9][0-9]* )?             |  # d+#+[.+]
    [tdvprcswgi][1-9][0-9]*\.[1-9][0-9]*                         |  # v+.+
    [tdvprcsugiw][1-9][0-9]*                                     |  # v+
    (?:https?|ftp)://[^><"\n\s\]\[]+[\d\w=/-]                       # link
  )}xg) {
    my $token = $&;
    my $pre = substr $raw, $last, $-[0]-$last;
    my $char_pre = $-[0] ? substr $raw, $-[0]-1, 1 : '';
    $last = pos $raw;
    my $char_post = substr $raw, $last, 1;

    # Pass through the unformatted text before the match
    $sub->($pre, 'text') || goto FINAL if length $pre;

    # Call the state functions. Arguments to these functions are implicitely
    # passed through @_, which avoids allocating a new stack for each function
    # call.
    my $state = $STATE{ $stack[$#stack]||'' };
    my @ret;
    @_ = (\@stack, $token, $char_pre, $char_post);
    for(@$state) {
      @ret = &$_;
      last if @ret;
    }
    $sub->($token, @ret ? @ret : ('text')) || goto FINAL;
  }

  $sub->(substr($raw, $last), 'text') if $last < length $raw;

FINAL:
  # Close all tags. This code is a bit of a hack, as it bypasses the state actions.
  $sub->('', "${_}_end") for reverse @stack;
}


# Options:
#   maxlength    => 0/$n - truncate after $n visible characters
#   inline       => 0/1  - don't insert line breaks and don't format block elements
#
# One of:
#   text         => 0/1  - format as plain text, no tags
#   onlyids      => 0/1  - format as HTML, but only convert VNDBIDs, leave the rest alone (including [spoiler]s)
#   default: format all to HTML.
#
# One of:
#   delspoil     => 0/1  - delete [spoiler] tags and its contents
#   replacespoil => 0/1  - replace [spoiler] tags with a "hidden by spoiler settings" message
#   keepsoil     => 0/1  - keep the contents of spoiler tags without any special formatting
#   default: format as <span class="spoiler">..
sub bb_format {
  my($input, %opt) = @_;
  $opt{delspoil} = 1 if $opt{text} && !$opt{keepspoil};

  my $incode = 0;
  my $inspoil = 0;
  my $rmnewline = 0;
  my $length = 0;
  my $ret = '';

  # escapes, returns string, and takes care of $length and $maxlength; also
  # takes care to remove newlines and double spaces when necessary
  my sub e {
    local $_ = shift;

    s/^\n//         if $rmnewline && $rmnewline--;
    s/\n{5,}/\n\n/g if !$incode;
    s/  +/ /g       if !$incode;
    $length += length $_;
    if($opt{maxlength} && $length > $opt{maxlength}) {
      $_ = substr($_, 0, $opt{maxlength}-$length);
      s/\W+\w*$//; # cleanly cut off on word boundary
    }
    if(!$opt{text}) {
      s/&/&amp;/g;
      s/>/&gt;/g;
      s/</&lt;/g;
      s/\n/<br>/g if !$opt{inline};
    }
    s/\n/ /g    if $opt{inline};
    $_;
  };

  parse $input, sub {
    my($raw, $tag, @arg) = @_;

    return 1 if $inspoil && $tag ne 'spoiler_end' && ($opt{delspoil} || $opt{replacespoil});

    if($tag eq 'text') {
      $ret .= e $raw;

    } elsif($tag eq 'dblink') {
      (my $link = $raw) =~ s/^d(\d+)\.(\d+)\.(\d+)$/d$1#$2.$3/;
      $ret .= $opt{text} ? e $raw : sprintf '<a href="/%s">%s</a>', $link, e $raw;

    } elsif($opt{idonly}) {
      $ret .= e $raw;

    } elsif($tag eq 'b_start') { $ret .= $opt{text} ? e '*' : '<strong>'
    } elsif($tag eq 'b_end')   { $ret .= $opt{text} ? e '*' : '</strong>'
    } elsif($tag eq 'i_start') { $ret .= $opt{text} ? e '/' : '<em>'
    } elsif($tag eq 'i_end')   { $ret .= $opt{text} ? e '/' : '</em>'
    } elsif($tag eq 'u_start') { $ret .= $opt{text} ? e '_' : '<span class="underline">'
    } elsif($tag eq 'u_end')   { $ret .= $opt{text} ? e '_' : '</span>'
    } elsif($tag eq 's_start') { $ret .= $opt{text} ? e '-' : '<s>'
    } elsif($tag eq 's_end')   { $ret .= $opt{text} ? e '-' : '</s>'
    } elsif($tag eq 'quote_start') {
      $ret .= $opt{text} || $opt{inline} ? e '"' : '<div class="quote">';
      $rmnewline = 1;
    } elsif($tag eq 'quote_end') {
      $ret .= $opt{text} || $opt{inline} ? e '"' : '</div>';
      $rmnewline = 1;

    } elsif($tag eq 'code_start') {
      $ret .= $opt{text} || $opt{inline} ? e '`' : '<pre>';
      $rmnewline = 1;
      $incode = 1;
    } elsif($tag eq 'code_end') {
      $ret .= $opt{text} || $opt{inline} ? e '`' : '</pre>';
      $rmnewline = 1;
      $incode = 0;

    } elsif($tag eq 'spoiler_start') {
      $inspoil = 1;
      $ret .= $opt{delspoil} || $opt{keepspoil} ? ''
        : $opt{replacespoil} ? '<small>&lt;hidden by spoiler settings&gt;</small>'
        : '<span class="spoiler">';
    } elsif($tag eq 'spoiler_end') {
      $inspoil = 0;
      $ret .= $opt{delspoil} || $opt{keepspoil} || $opt{replacespoil} ? '' : '</span>';

    } elsif($tag eq 'url_start') {
      $ret .= $opt{text} ? '' : sprintf '<a href="%s" rel="nofollow">', xml_escape($arg[0]);
    } elsif($tag eq 'url_end') {
      $ret .= $opt{text} ? '' : '</a>';

    } elsif($tag eq 'link') {
      $ret .= $opt{text} ? e $raw : sprintf '<a href="%s" rel="nofollow">%s</a>', xml_escape($raw), e 'link';
    }

    !$opt{maxlength} || $length < $opt{maxlength};
  };
  $ret;
}


# Turn (most) 'dblink's into [url=..] links. This function relies on FU to do
# the database querying, so can't be used from Multi.
# Doesn't handle:
# - d+, t+, r+ and u+ links
# - item revisions
sub bb_subst_links {
  my $msg = shift;

  # Parse a message and create an index of links to resolve
  my %lookup;
  parse $msg, sub {
    my($code, $tag) = @_;
    $lookup{$1} = 1 if $tag eq 'dblink' && $code =~ /^([vcpgis]\d+)$/;
    1;
  };
  return $msg unless %lookup;

  my $links = FU::fu->sql('SELECT id, title[2] FROM unnest($1::vndbid[]) n(id), item_info(NULL, n.id, NULL)', [keys %lookup])->kvv;
  return $msg unless %$links;

  # Now substitute
  my $result = '';
  parse $msg, sub {
    my($code, $tag) = @_;
    $result .= $tag eq 'dblink' && $links->{$code}
      ? sprintf '[url=/%s]%s[/url]', $code, $links->{$code}
      : $code;
    1;
  };
  return $result;
}


1;
