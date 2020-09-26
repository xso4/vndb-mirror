
package VNDB::Handler::Tags;


use strict;
use warnings;
use TUWF ':html', ':xml', 'xml_escape';
use VNDB::Func;
use VNDB::Types;


TUWF::register(
  qr{g([1-9]\d*)},          \&tagpage,
  qr{old/g([1-9]\d*)/(edit)},   \&tagedit,
  qr{old/g([1-9]\d*)/(add)},    \&tagedit,
  qr{old/g/new},                \&tagedit,
  qr{g/list},               \&taglist,
  qr{u([1-9]\d*)/tags},     \&usertags,
  qr{g},                    \&tagindex,
  qr{g/debug},              \&fulltree,
  qr{xml/tags\.xml},        \&tagxml,
);


sub tagpage {
  my($self, $tag) = @_;

  my $t = $self->dbTagGet(id => $tag, what => 'parents(0) childs(2) aliases')->[0];
  return $self->resNotFound if !$t;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'tagscore', enum => [ qw|title rel pop tagscore rating| ] },
    { get => 'o', required => 0, default => 'd', enum => [ 'a','d' ] },
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 'm', required => 0, default => $self->authPref('spoilers') || 0, enum => [qw|0 1 2|] },
    { get => 'fil', required => 0 },
  );
  return $self->resNotFound if $f->{_err};
  $f->{fil} //= $self->authPref('filter_vn');

  my($list, $np) = !$t->{searchable} || $t->{state} != 2 ? ([],0) : $self->filFetchDB(vn => $f->{fil}, undef, {
    what => 'rating',
    results => 50,
    page => $f->{p},
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    tagspoil => $f->{m},
    tag_inc => $tag,
    tag_exc => undef,
  });

  my $title = "Tag: $t->{name}";
  $self->htmlHeader(title => $title, noindex => $t->{state} != 2);
  $self->htmlMainTabs('g', $t);

  if($t->{state} != 2) {
    div class => 'mainbox';
     h1 $title;
     if($t->{state} == 1) {
       div class => 'warning';
        h2 'Tag deleted';
        p;
         txt 'This tag has been removed from the database, and cannot be used or re-added.';
         br;
         txt 'File a request on the ';
         a href => '/t/db', 'discussion board';
         txt ' if you disagree with this.';
        end;
       end;
     } else {
       div class => 'notice';
        h2 'Waiting for approval';
        p 'This tag is waiting for a moderator to approve it. You can still use it to tag VNs as you would with a normal tag.';
       end;
     }
    end 'div';
  }

  div class => 'mainbox';
   a class => 'addnew', href => "/g$tag/add", 'Create child tag' if $self->authCan('tag') && $t->{state} != 1;
   h1 $title;

   parenttags($t, 'Tags', 'g');

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
       txt 'Can not be directly applied to visual novels.' if !$t->{applicable};
     end;
   }
   p class => 'center';
    b 'Category';
    br;
    txt $TAG_CATEGORY{$t->{cat}};
   end;
   if(@{$t->{aliases}}) {
     p class => 'center';
      b 'Aliases';
      br;
      lit xml_escape($_).'<br />' for (@{$t->{aliases}});
     end;
   }
  end 'div';

  childtags($self, 'Child tags', 'g', $t) if @{$t->{childs}};

  if($t->{searchable} && $t->{state} == 2) {
    form action => "/g$t->{id}", 'accept-charset' => 'UTF-8', method => 'get';
    div class => 'mainbox';
     a class => 'addnew', href => "/g/links?t=$tag", 'Recently tagged';
     h1 'Visual novels';

     p class => 'browseopts';
      a href => "/g$t->{id}?fil=$f->{fil};s=$f->{s};o=$f->{o};m=0", $f->{m} == 0 ? (class => 'optselected') : (), 'Hide spoilers';
      a href => "/g$t->{id}?fil=$f->{fil};s=$f->{s};o=$f->{o};m=1", $f->{m} == 1 ? (class => 'optselected') : (), 'Show minor spoilers';
      a href => "/g$t->{id}?fil=$f->{fil};s=$f->{s};o=$f->{o};m=2", $f->{m} == 2 ? (class => 'optselected') : (), 'Spoil me!';
     end;

     p class => 'filselect';
      a id => 'filselect', href => '#v';
       lit '<i>&#9656;</i> Filters<i></i>';
      end;
     end;
     input type => 'hidden', class => 'hidden', name => 'fil', id => 'fil', value => $f->{fil};
     input type => 'hidden', class => 'hidden', name => 'm', id => 'm', value => $f->{m};

     if(!@$list) {
       p; br; br; txt 'This tag has not been linked to any visual novels yet, or they were hidden because of your spoiler settings or default filters.'; end;
     }
     if(@{$t->{childs}}) {
       p; br; txt 'The list below also includes all visual novels linked to child tags.'; end;
     }
    end 'div';
    end 'form';
    $self->htmlBrowseVN($list, $f, $np, "/g$t->{id}?fil=$f->{fil};m=$f->{m}", 1) if @$list;
  }

  $self->htmlFooter(pref_code => 1);
}


sub tagedit {
  my($self, $tag, $act) = @_;

  my($frm, $par);
  if($act && $act eq 'add') {
    $par = $self->dbTagGet(id => $tag)->[0];
    return $self->resNotFound if !$par;
    $frm->{parents} = $par->{name};
    $frm->{cat} = $par->{cat};
    $tag = undef;
  }

  return $self->htmlDenied if !$self->authCan('tag') || $tag && !$self->authCan('tagmod');

  my $t = $tag && $self->dbTagGet(id => $tag, what => 'parents(1) aliases addedby')->[0];
  return $self->resNotFound if $tag && !$t;

  if($self->reqMethod eq 'POST') {
    return if !$self->authCheckCode;
    $frm = $self->formValidate(
      { post => 'name',        required => 1, maxlength => 250, regex => [ qr/^[^,]+$/, 'A comma is not allowed in tag names' ] },
      { post => 'state',       required => 0, default => 0,  enum => [ 0..2 ] },
      { post => 'cat',         required => 1, enum => [ keys %TAG_CATEGORY ] },
      { post => 'catrec',      required => 0 },
      { post => 'searchable',  required => 0, default => 0 },
      { post => 'applicable',  required => 0, default => 0 },
      { post => 'alias',       required => 0, maxlength => 1024, default => '', regex => [ qr/^[^,]+$/s, 'No comma allowed in aliases' ]  },
      { post => 'description', required => 0, maxlength => 10240, default => '' },
      { post => 'defaultspoil',required => 0, default => 0, enum => [ 0..2 ] },
      { post => 'parents',     required => !$self->authCan('tagmod'), default => '' },
      { post => 'merge',       required => 0, default => '' },
      { post => 'wipevotes',   required => 0, default => 0 },
    );
    my @aliases = split /[\t\s]*\n[\t\s]*/, $frm->{alias};
    my @parents = split /[\t\s]*,[\t\s]*/, $frm->{parents};
    my @merge = split /[\t\s]*,[\t\s]*/, $frm->{merge};
    if(!$frm->{_err}) {
      my @dups = @{$self->dbTagGet(name => $frm->{name}, noid => $tag)};
      push @dups, @{$self->dbTagGet(name => $_, noid => $tag)} for @aliases;
      push @{$frm->{_err}}, \sprintf 'Tag <a href="/g%d">%s</a> already exists!', $_->{id}, xml_escape $_->{name} for @dups;
      for(@parents, @merge) {
        my $c = $self->dbTagGet(name => $_, noid => $tag);
        push @{$frm->{_err}}, "Tag '$_' not found" if !@$c;
        $_ = $c->[0]{id};
      }
    }

    if(!$frm->{_err}) {
      if(!$self->authCan('tagmod')) {
        $frm->{state} = 0;
        $frm->{searchable} = $frm->{applicable} = 1;
      }
      my %opts = (
        name => $frm->{name},
        state => $frm->{state},
        cat => $frm->{cat},
        description => $frm->{description},
        searchable => $frm->{searchable}?1:0,
        applicable => $frm->{applicable}?1:0,
        defaultspoil => $frm->{defaultspoil},
        aliases => \@aliases,
        parents => \@parents,
      );
      if(!$tag) {
        $tag = $self->dbTagAdd(%opts);
      } else {
        $self->dbTagEdit($tag, %opts, upddate => $frm->{state} == 2 && $t->{state} != 2);
        _set_childs_cat($self, $tag, $frm->{cat}) if $frm->{catrec};
      }
      $self->dbTagWipeVotes($tag) if $self->authCan('tagmod') && $frm->{wipevotes};
      $self->dbTagMerge($tag, @merge) if $self->authCan('tagmod') && @merge;
      $self->resRedirect("/g$tag", 'post');
      return;
    }
  }

  if($tag) {
    $frm->{$_} ||= $t->{$_} for (qw|name searchable applicable description state cat defaultspoil|);
    $frm->{alias} ||= join "\n", @{$t->{aliases}};
    $frm->{parents} ||= join ', ', map $_->{name}, @{$t->{parents}};
  }

  my $title = $par ? "Add child tag to $par->{name}" : $tag ? "Edit tag: $t->{name}" : 'Add new tag';
  $self->htmlHeader(title => $title, noindex => 1);
  $self->htmlMainTabs('g', $par || $t, 'edit') if $t || $par;

  if(!$self->authCan('tagmod')) {
    div class => 'mainbox';
     h1 'Requesting new tag';
     div class => 'notice';
      h2 'Your tag must be approved';
      p;
       txt 'Because all tags have to be approved by moderators, it can take a while before it will show up in the tag list'
          .' or on visual novel pages. You can still vote on tag even if it has not been approved yet, though.';
       br; br;
       txt 'Also, make sure you\'ve read the ';
       a href => '/d10', 'guidelines';
       txt ' so you can predict whether your tag will be accepted or not.';
      end;
     end;
    end;
  }

  $self->htmlForm({ frm => $frm, action => $par ? "/old/g$par->{id}/add" : $tag ? "/old/g$tag/edit" : '/old/g/new' }, 'tagedit' => [ $title,
    [ input    => short => 'name',     name => 'Primary name' ],
    $self->authCan('tagmod') ? (
      $tag ?
        [ static   => label => 'Added by', content => sub { VNWeb::HTML::user_($t); '' } ] : (),
      [ select   => short => 'state',    name => 'State', options => [
        [0, 'Awaiting moderation'], [1, 'Deleted/hidden'], [2, 'Approved']  ] ],
      [ checkbox => short => 'searchable', name => 'Searchable (people can use this tag to filter VNs)' ],
      [ checkbox => short => 'applicable', name => 'Applicable (people can apply this tag to VNs)' ],
    ) : (),
    [ select   => short => 'cat', name => 'Category', options => [
      map [$_, $TAG_CATEGORY{$_}], keys %TAG_CATEGORY ] ],
    $self->authCan('tagmod') && $tag ? (
      [ checkbox => short => 'catrec', name => 'Also edit all child tags to have this category' ],
      [ static => content => 'WARNING: This will overwrite the category field for all child tags, this action can not be reverted!' ],
    ) : (),
    [ textarea => short => 'alias',    name => "Aliases\n(separated by newlines)", cols => 30, rows => 4 ],
    [ textarea => short => 'description', name => 'Description' ],
    [ static   => content => 'What should the tag be used for? Having a good description helps users choose which tags to link to a VN.' ],
    [ select   => short => 'defaultspoil', name => 'Default spoiler level', options => [ map [$_, fmtspoil $_], 0..2 ] ],
    [ static   => content => 'This is the spoiler level that will be used by default when everyone has voted "neutral".' ],
    [ input    => short => 'parents',  name => 'Parent tags' ],
    [ static   => content => 'Comma separated list of tag names to be used as parent for this tag.' ],
    $self->authCan('tagmod') ? (
      [ part   => title => 'DANGER: Merge tags' ],
      [ input  => short => 'merge', name => 'Tags to merge' ],
      [ static => content =>
          'Comma separated list of tag names to merge into this one.'
         .' All votes and aliases/names will be moved over to this tag, and the old tags will be deleted.'
         .' Just leave this field empty if you don\'t intend to do a merge.'
         .'<br />WARNING: this action cannot be undone!' ],

      [ part     => title => 'DANGER: Delete tag votes' ],
      [ checkbox => short => 'wipevotes', name => 'Remove all votes on this tag. WARNING: cannot be undone!' ],
    ) : (),
  ]);
  $self->htmlFooter;
}

# recursively edit all child tags and set the category field
# Note: this can be done more efficiently by doing everything in one UPDATE
#  query, but that takes more code and this feature isn't used very often
#  anyway.
sub _set_childs_cat {
  my($self, $tag, $cat) = @_;
  my %done;

  my $e;
  $e = sub {
    my $l = shift;
    for (@$l) {
      $self->dbTagEdit($_->{id}, cat => $cat) if !$done{$_->{id}}++;
      $e->($_->{sub}) if $_->{sub};
    }
  };

  my $childs = $self->dbTTTree(tag => $tag, 25);
  $e->($childs);
}


sub taglist {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 's', required => 0, default => 'name', enum => ['added', 'name'] },
    { get => 'o', required => 0, default => 'a', enum => ['a', 'd'] },
    { get => 'p', required => 0, default => 1, template => 'page' },
    { get => 't', required => 0, default => -1, enum => [ -1..2 ] },
    { get => 'q', required => 0, default => '' },
  );
  return $self->resNotFound if $f->{_err};

  my($t, $np) = $self->dbTagGet(
    sort => $f->{s}, reverse => $f->{o} eq 'd',
    page => $f->{p},
    results => 50,
    state => $f->{t},
    search => $f->{q}
  );

  $self->htmlHeader(title => 'Browse tags');
  div class => 'mainbox';
   h1 'Browse tags';
   form action => '/g/list', 'accept-charset' => 'UTF-8', method => 'get';
    input type => 'hidden', name => 't', value => $f->{t};
    $self->htmlSearchBox('g', $f->{q});
   end;
   p class => 'browseopts';
    a href => "/g/list?q=$f->{q};t=-1", $f->{t} == -1 ? (class => 'optselected') : (), 'All';
    a href => "/g/list?q=$f->{q};t=0", $f->{t} == 0 ? (class => 'optselected') : (), 'Awaiting moderation';
    a href => "/g/list?q=$f->{q};t=1", $f->{t} == 1 ? (class => 'optselected') : (), 'Deleted';
    a href => "/g/list?q=$f->{q};t=2", $f->{t} == 2 ? (class => 'optselected') : (), 'Accepted';
   end;
   if(!@$t) {
     p 'No results found';
   }
  end 'div';
  if(@$t) {
    $self->htmlBrowse(
      class    => 'taglist',
      options  => $f,
      nextpage => $np,
      items    => $t,
      pageurl  => "/g/list?t=$f->{t};q=$f->{q};s=$f->{s};o=$f->{o}",
      sorturl  => "/g/list?t=$f->{t};q=$f->{q}",
      header   => [
        [ 'Created', 'added' ],
        [ 'Tag',  'name'  ],
      ],
      row => sub {
        my($s, $n, $l) = @_;
        Tr;
         td class => 'tc1', fmtage $l->{added};
         td class => 'tc3';
          a href => "/g$l->{id}", $l->{name};
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


sub tagindex {
  my $self = shift;

  $self->htmlHeader(title => 'Tag index');
  div class => 'mainbox';
   a class => 'addnew', href => "/g/new", 'Create new tag' if $self->authCan('tag');
   h1 'Search tags';
   form action => '/g/list', 'accept-charset' => 'UTF-8', method => 'get';
    $self->htmlSearchBox('g', '');
   end;
  end;

  my $t = $self->dbTTTree(tag => 0, 2);
  childtags($self, 'Tag tree', 'g', {childs => $t});

  table class => 'mainbox threelayout';
   Tr;

    # Recently added
    td;
     a class => 'right', href => '/g/list', 'Browse all tags';
     my $r = $self->dbTagGet(sort => 'added', reverse => 1, results => 10, state => 2);
     h1 'Recently added';
     ul;
      for (@$r) {
        li;
         txt fmtage $_->{added};
         txt ' ';
         a href => "/g$_->{id}", $_->{name};
        end;
      }
     end;
    end;

    # Popular
    td;
     a class => 'addnew', href => "/g/links", 'Recently tagged';
     $r = $self->dbTagGet(sort => 'items', reverse => 1, searchable => 1, applicable => 1, results => 10);
     h1 'Popular tags';
     ul;
      for (@$r) {
        li;
         a href => "/g$_->{id}", $_->{name};
         txt " ($_->{c_items})";
        end;
      }
     end;
    end;

    # Moderation queue
    td;
     h1 'Awaiting moderation';
     $r = $self->dbTagGet(state => 0, sort => 'added', reverse => 1, results => 10);
     ul;
      li 'Moderation queue empty! yay!' if !@$r;
      for (@$r) {
        li;
         txt fmtage $_->{added};
         txt ' ';
         a href => "/g$_->{id}", $_->{name};
        end;
      }
      li;
       br;
       a href => '/g/list?t=0;o=d;s=added', 'Moderation queue';
       txt ' - ';
       a href => '/g/list?t=1;o=d;s=added', 'Denied tags';
      end;
     end;
    end;

   end 'tr';
  end 'table';
  $self->htmlFooter;
}


# non-translatable debug page
sub fulltree {
  my $self = shift;
  return $self->htmlDenied if !$self->authCan('tagmod');

  my $e;
  $e = sub {
    my $lst = shift;
    ul style => 'list-style-type: none; margin-left: 15px';
     for (@$lst) {
       li;
        txt '> ';
        a href => "/g$_->{id}", $_->{name};
        b class => 'grayedout', " ($_->{c_items})" if $_->{c_items};
       end;
       $e->($_->{sub}) if $_->{sub};
     }
    end;
  };

  my $tags = $self->dbTTTree(tag => 0, 25);
  $self->htmlHeader(title => '[DEBUG] Tag tree', noindex => 1);
  div class => 'mainbox';
   h1 '[DEBUG] Tag tree';
   $e->($tags);
  end;
  $self->htmlFooter;
}


sub tagxml {
  my $self = shift;

  my $f = $self->formValidate(
    { get => 'q', required => 0, maxlength => 500 },
    { get => 'id', required => 0, multi => 1, template => 'id' },
    { get => 'searchable', required => 0, default => 0 },
    { get => 'r', required => 0, template => 'uint', min => 1, max => 50, default => 15 },
  );
  return $self->resNotFound if $f->{_err} || (!$f->{q} && !$f->{id} && !$f->{id}[0]);

  my($list, $np) = $self->dbTagGet(
    !$f->{q} ? () : $f->{q} =~ /^g([1-9]\d*)/ ? (id => $1) : $f->{q} =~ /^=(.+)$/ ? (name => $1) : (search => $f->{q}, sort => 'search'),
    $f->{id} && $f->{id}[0] ? (id => $f->{id}) : (),
    results => $f->{r},
    page => 1,
    $f->{searchable} ? (state => 2, searchable => 1) : (),
  );

  $self->resHeader('Content-type' => 'text/xml; charset=UTF-8');
  xml;
  tag 'tags', more => $np ? 'yes' : 'no', $f->{q} ? (query => $f->{q}) : ();
   for(@$list) {
     tag 'item', id => $_->{id}, searchable => $_->{searchable} ? 'yes' : 'no', applicable => $_->{applicable} ? 'yes' : 'no', state => $_->{state}, $_->{name};
   }
  end;
}


1;
