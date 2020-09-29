
package VNDB::Handler::Traits;

use strict;
use warnings;
use TUWF ':html', ':xml', 'html_escape', 'xml_escape';
use VNDB::Func;


TUWF::register(
  qr{i([1-9]\d*)},        \&traitpage,
  qr{i/list},             \&traitlist,
  qr{i},                  \&traitindex,
  qr{xml/traits\.xml},    \&traitxml,
);


sub traitpage {
  my($self, $trait) = @_;

  my $t = $self->dbTraitGet(id => $trait, what => 'parents(0) childs(2)')->[0];
  return $self->resNotFound if !$t;

  my $f = $self->formValidate(
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'm', required => 0, default => $self->authPref('spoilers')||0, enum => [qw|0 1 2|] },
    { get => 'fil', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my $title = "Trait: $t->{name}";
  $self->htmlHeader(title => $title, noindex => $t->{state} != 2);
  $self->htmlMainTabs('i', $t);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 $title;
     if($t->{state} == 1) {
       div class => 'warning';
        h2 'Trait deleted';
        p;
         txt 'This trait has been removed from the database, and cannot be used or re-added. File a request on the ';
         a href => '/t/db', 'discussion board';
         txt ' if you disagree with this.';
        end;
       end;
     } else {
       div class => 'notice';
        h2 'Waiting for approval';
        p 'This trait is waiting for a moderator to approve it.';
       end;
     }
    end 'div';
  }

  div class => 'mainbox';
   a class => 'addnew', href => "/i$trait/add", 'Create child trait' if $self->authCan('edit') && $t->{state} != 1;
   h1 $title;

   parenttags($t, 'Traits', 'i');

   if($t->{description}) {
     p class => 'description';
      lit bb_format $t->{description};
     end;
   }
   if(!$t->{applicable} || !$t->{searchable}) {
     p class => 'center';
       b 'Properties';
       br;
       txt 'Not searchable.' if !$t->{searchable};
       br;
       txt 'Can not be directly applied to characters.' if !$t->{applicable};
     end;
   }
   if($t->{sexual}) {
     p class => 'center';
      b 'Sexual content';
     end;
   }
   if($t->{alias}) {
     p class => 'center';
      b 'Aliases';
      br;
      lit html_escape($t->{alias});
     end;
   }
  end 'div';

  childtags($self, 'Child traits', 'i', $t) if @{$t->{childs}};

  if($t->{searchable} && $t->{state} == 2) {
    my($chars, $np) = $self->filFetchDB(char => $f->{fil}, {}, {
      trait_inc => $trait,
      tagspoil => $f->{m},
      results => 50,
      page => $f->{p},
      what => 'vns',
    });

    form action => "/i$t->{id}", 'accept-charset' => 'UTF-8', method => 'get';
    div class => 'mainbox';
     h1 'Characters';

     p class => 'browseopts';
      a href => "/i$trait?fil=$f->{fil};m=0", $f->{m} == 0 ? (class => 'optselected') : (), 'Hide spoilers';
      a href => "/i$trait?fil=$f->{fil};m=1", $f->{m} == 1 ? (class => 'optselected') : (), 'Show minor spoilers';
      a href => "/i$trait?fil=$f->{fil};m=2", $f->{m} == 2 ? (class => 'optselected') : (), 'Spoil me!';
     end;

     p class => 'filselect';
      a id => 'filselect', href => '#c';
       lit '<i>&#9656;</i> Filters<i></i>';
      end;
     end;
     input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
     input type => 'hidden', class => 'hidden', name => 'm', id => 'm', value => $f->{m};

     if(!@$chars) {
       p; br; br; txt 'This trait has not been linked to any characters yet, or they were hidden because of your spoiler settings.'; end;
     }
     if(@{$t->{childs}}) {
       p; br; txt 'The list below also includes all characters linked to child traits.'; end;
     }
    end 'div';
    end 'form';
    @$chars && $self->charBrowseTable($chars, $np, $f, "/i$trait?m=$f->{m};fil=$f->{fil}");
  }

  $self->htmlFooter;
}


sub traitlist {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'name', enum => ['added', 'name'] },
    { get => 'o', required => 0, default => 'a', enum => ['a', 'd'] },
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 't', required => 0, default => -1, enum => [ -1..2 ] },
    { get => 'q', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my($t, $np) = $self->dbTraitGet(
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    page => $f->{p},
    results => 50,
    state => $f->{t},
    search => $f->{q}
  );

  $self->htmlHeader(title => 'Browse traits');
  div class => 'mainbox';
   h1 'Browse traits';
   form action => '/i/list', 'accept-charset' => 'UTF-8', method => 'get';
    input type => 'hidden', name => 't', value => $f->{t};
    $self->htmlSearchBox('i', $f->{q});
   end;
   p class => 'browseopts';
    a href => "/i/list?q=$f->{q};t=-1", $f->{t} == -1 ? (class => 'optselected') : (), 'All';
    a href => "/i/list?q=$f->{q};t=0", $f->{t} == 0 ? (class => 'optselected') : (), 'Awaiting moderation';
    a href => "/i/list?q=$f->{q};t=1", $f->{t} == 1 ? (class => 'optselected') : (), 'Deleted';
    a href => "/i/list?q=$f->{q};t=2", $f->{t} == 2 ? (class => 'optselected') : (), 'Accepted';
   end;
   if(!@$t) {
     p 'No results found';
   }
  end 'div';
  if(@$t) {
    $self->htmlBrowse(
      class    => 'traitlist',
      options  => $f,
      nextpage => $np,
      items    => $t,
      pageurl  => "/i/list?t=$f->{t};q=$f->{q};s=$f->{s};o=$f->{o}",
      sorturl  => "/i/list?t=$f->{t};q=$f->{q}",
      header   => [
        [ 'Created', 'added' ],
        [ 'Trait',  'name'  ],
      ],
      row => sub {
        my($s, $n, $l) = @_;
        Tr;
         td class => 'tc1', fmtage $l->{added};
         td class => 'tc3';
          if($l->{group}) {
            b class => 'grayedout', $l->{groupname}.' / ';
          }
          a href => "/i$l->{id}", $l->{name};
          if($f->{t} == -1) {
            b class => 'grayedout', ' awaiting moderation' if $l->{state} == 0;
            b class => 'grayedout', ' deleted' if $l->{state} == 1;
          }
         end;
        end 'tr';
      }
    );
  }
  $self->htmlFooter;
}


sub traitindex {
  my $self = shift;

  $self->htmlHeader(title => 'Trait index');
  div class => 'mainbox';
   a class => 'addnew', href => "/i/new", 'Create new trait' if $self->authCan('edit');
   h1 'Search traits';
   form action => '/i/list', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('i', '');
   end;
  end;

  my $t = $self->dbTTTree(trait => 0, 2);
  childtags($self, 'Trait tree', 'i', {childs => $t}, 'order');

  table class => 'mainbox threelayout';
   Tr;

    # Recently added
    td;
     a class => 'right', href => '/i/list', 'Browse all traits';
     my $r = $self->dbTraitGet(sort => 'added', reverse => 1, results => 10);
     h1 'Recently added';
     ul;
      for (@$r) {
        li;
         txt fmtage $_->{added};
         txt ' ';
         b class => 'grayedout', $_->{groupname}.' / ' if $_->{group};
         a href => "/i$_->{id}", $_->{name};
        end;
      }
     end;
    end;

    # Popular
    td;
     h1 'Popular traits';
     ul;
      $r = $self->dbTraitGet(sort => 'items', reverse => 1, results => 10);
      for (@$r) {
        li;
         b class => 'grayedout', $_->{groupname}.' / ' if $_->{group};
         a href => "/i$_->{id}", $_->{name};
         txt " ($_->{c_items})";
        end;
      }
     end;
    end;

    # Moderation queue
    td;
     h1 'Awaiting moderation';
     $r = $self->dbTraitGet(state => 0, sort => 'added', reverse => 1, results => 10);
     ul;
      li 'Moderation queue empty! yay!' if !@$r;
      for (@$r) {
        li;
         txt fmtage $_->{added};
         txt ' ';
         b class => 'grayedout', $_->{groupname}.' / ' if $_->{group};
         a href => "/i$_->{id}", $_->{name};
        end;
      }
      li;
       br;
       a href => '/i/list?t=0;o=d;s=added', 'Moderation queue';
       txt ' - ';
       a href => '/i/list?t=1;o=d;s=added', 'Denied traits';
      end;
     end;
    end;

   end 'tr';
  end 'table';
  $self->htmlFooter;
}


sub traitxml {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 'q', required => 0, maxlength => 500 },
    { get => 'id', required => 0, multi => 1, template => 'id' },
    { get => 'r', required => 0, default => 15, template => 'uint', min => 1, max => 200 },
    { get => 'searchable', required => 0, default => 0 },
  );
  return $self->resNotFound if $f->{_err} || (!$f->{q} && !$f->{id} && !$f->{id}[0]);

  my($list, $np) = $self->dbTraitGet(
    results => $f->{r},
    page => 1,
    sort => 'group',
    state => 2,
    $f->{searchable} ? (searchable => 1) : (),
    !$f->{q} ? () : $f->{q} =~ /^i([1-9]\d*)/ ? (id => $1) : (search => $f->{q}, sort => 'search'),
    $f->{id} && $f->{id}[0] ? (id => $f->{id}) : (),
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'traits', more => $np ? 'yes' : 'no';
   for(@$list) {
     tag 'item', id => $_->{id}, searchable => $_->{searchable} ? 'yes' : 'no', applicable => $_->{applicable} ? 'yes' : 'no', group => $_->{group}||'',
       groupname => $_->{groupname}||'', state => $_->{state}, defaultspoil => $_->{defaultspoil}, $_->{name};
   }
  end;
}


1;

