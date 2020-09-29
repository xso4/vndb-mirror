
package VNDB::DB::Traits;

# This module is for a large part a copy of VNDB::DB::Tags. I could have chosen
# to modify that module to work for both traits and tags but that would have
# complicated the code, so I chose to maintain two versions with similar
# functionality instead.

use strict;
use warnings;
use Exporter 'import';

our @EXPORT = qw|dbTraitGet|;


# Options: id noid search name state searchable applicable what results page sort reverse
# what: parents childs(n) addedby
# sort: id name name added items search
sub dbTraitGet {
  my $self = shift;
  my %o = (
    page => 1,
    results => 10,
    what => '',
    @_,
  );

  $o{search} =~ s/%//g if $o{search};

  my %where = (
    $o{id}    ? ( 't.id IN(!l)' => [ ref($o{id}) ? $o{id} : [$o{id}] ]) : (),
    $o{group} ? ( 't.group = ?' => $o{group} ) : (),
    $o{noid}  ? ( 't.id <> ?' => $o{noid} ) : (),
    defined $o{state} && $o{state} != -1 ? (
      't.state = ?' => $o{state} ) : (),
    !defined $o{state} && !$o{id} && !$o{name} ? (
      't.state = 2' => 1 ) : (),
    $o{search} ? (
      '(t.name ILIKE ? OR t.alias ILIKE ?)' => [ "%$o{search}%", "%$o{search}%" ] ) : (),
    $o{name}  ? ( # TODO: This is terribly ugly, use an aliases table.
      q{(LOWER(t.name) = LOWER(?) OR t.alias ~ ('(!sin)^'||?||'$'))} => [ $o{name}, '?', quotemeta $o{name} ] ) : (),
    defined $o{applicable} ? ('t.applicable = ?' => $o{applicable}?1:0 ) : (),
    defined $o{searchable} ? ('t.searchable = ?' => $o{searchable}?1:0 ) : (),
  );

  my @select = (
    qw|t.id t.searchable t.applicable t.name t.description t.state t.alias t."group" t."order" t.sexual t.c_items t.defaultspoil|,
    'tg.name AS groupname', 'tg."order" AS grouporder', q|extract('epoch' from t.added) as added|,
    $o{what} =~ /addedby/ ? (VNWeb::DB::sql_user()) : (),
  );
  my @join = $o{what} =~ /addedby/ ? 'JOIN users u ON u.id = t.addedby' : ();
  push @join, 'LEFT JOIN traits tg ON tg.id = t."group"';

  my $order = sprintf {
    id    => 't.id %s',
    name  => 't.name %s',
    group => 'tg."order" %s, t.name %1$s',
    added => 't.added %s',
    items => 't.c_items %s',
    search=> 'substr_score(t.name, ?) ASC, t.name %s', # Can't score aliases at the moment
  }->{ $o{sort}||'id' }, $o{reverse} ? 'DESC' : 'ASC';
  my @order = $o{sort} && $o{sort} eq 'search' ? ($o{search}) : ();

  my($r, $np) = $self->dbPage(\%o, qq|
    SELECT !s
      FROM traits t
      !s
      !W
      ORDER BY $order|,
    join(', ', @select), join(' ', @join), \%where, @order,
  );

  if($o{what} =~ /parents\((\d+)\)/) {
    $_->{parents} = $self->dbTTTree(trait => $_->{id}, $1, 1) for(@$r);
  }

  if($o{what} =~ /childs\((\d+)\)/) {
    $_->{childs} = $self->dbTTTree(trait => $_->{id}, $1) for(@$r);
  }

  return wantarray ? ($r, $np) : $r;
}


1;

