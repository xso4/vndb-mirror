
package VNDB::Handler::Tags;


use strict;
use warnings;
use TUWF ':html', ':xml', 'xml_escape';
use VNDB::Func;
use VNDB::Types;


TUWF::register(
  qr{g([1-9]\d*)},          \&tagpage,
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
