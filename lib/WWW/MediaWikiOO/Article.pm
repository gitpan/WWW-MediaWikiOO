# $Id: Article.pm,v 1.1 2006/06/11 14:55:27 cfaerber Exp $
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of either:
# 
# a) the GNU General Public License as published by the Free Software
# Foundation; either version 1, or (at your option) any later version,
# or
# b) the "Artistic License" which comes with this Kit.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See either the
# GNU General Public License or the Artistic License for more details.
# 
# You should have received a copy of the Artistic License with this Kit,
# in the file named "Artistic".
# 
# You should also have received a copy of the GNU General Public License
# along with this program in the file named "Copying". If not, write to
# the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
# Boston, MA 02111-1307, USA or visit their web page on the internet at
# http://www.gnu.org/copyleft/gpl.html.
#
package WWW::MediaWikiOO::Article;

use strict;
use utf8;

use Carp;
use Data::Dumper;
use Digest::SHA1;
use HTML::LinkExtor;
use LWP::UserAgent;
use URI;
use URI::Heuristic;
use URI::QueryParam;

sub new {
  my $pkg = shift;
  my $self = {}; bless($self, $pkg);
  
  $self->site(shift);
  $self->title(shift);

  return $self;
}

sub edit_new {
  my $self = new(@_);
  $self->edit();
  return $self;
}

sub _ua { 
  return shift->site->_ua 
}

sub _api { 
  my ($self,%param) = @_;
  $param{'title'} = $self->title;
  my $x = $self->site->_api(%param);
  print STDERR "<$x>\n";
  return $x;
}

sub title {
  my ($self,$new_title) = @_;
  my $old_title = $self->{'_title'};

  if($new_title)
  {
    carp 'invalid title' if $new_title =~ m/[\[\]\+\{\}\<\>\|]/;
    $new_title =~ s/ /_/g;
    $self->{'_title'} = $new_title;
  }
  return $old_title;
}

sub site {
  my ($self,$new_site) = @_;
  my $old_site = $self->{'_site'};

  if($new_site)
  {
    carp 'not a WWW::Mediawiki' unless eval{$new_site->isa('WWW::MediaWikiOO')};
    $self->{'_site'} = $new_site;
  }
  return $old_site;
}

sub content_ref {
  my($self,$new_content_ref) = @_;

  if($self->editable()) {
  
    $self->_retrieve_content unless ($self->{'_content_sha1'});

    my $old_content_ref = $self->{'_content_ref'};
    $self->{'_content_ref'} = ref $new_content_ref ? $new_content_ref : \$new_content_ref if(defined $new_content_ref);
    return $old_content_ref;
    
  } else {

    carp 'read only - not editable' if $new_content_ref;
  
    # just get the raw data directly (not via edit form)
    unless ($self->{'_content_ref'}) {
      my $res = $self->_ua->get($self->_api('action'=>'raw'));
      $self->{'_content_ref'} = $res->content_ref;
      $self->{'_content_sha1'} = undef;
    }
    return $self->{'_content_ref'};
  }
}

sub content : lvalue {
  my($self,$new_content) = (@_);
  ${$self->content_ref($new_content)};
};

sub content_html {
  my($self) = @_;
  unless($self->{'_content_html'}) {
    my $res = $self->_ua->get($self->_api('action'=>'raw'));
    $self->{'_content_html'} = $res->content_ref;
  }
  return ${$self->{'_content_html'}};
}

sub edit {
  my($self) = @_;
  $self->{'_content_sha1'} = undef;			# trigger reload
  $self->editable(1);					# set editable
}

sub editable {
  my ($self,$new) = @_;
  my $old = $self->{'_content_editable'};
  $self->{'_content_editable'} = $new ? 1 : 0 if defined $new;
  return $old;
}

sub _retrieve_content {
  my($self) = @_;

  my $textarea;
  my %fields;

  my $p = HTML::Parser->new( 'api_version' => 3,
    start_h =>	[ sub {
        my($elem,$attr) = @_;
	return unless $attr->{'name'};
	$textarea = \$fields{$attr->{'name'}} if $elem eq 'textarea';
	$fields{$attr->{'name'}} = $attr->{'value'} if $elem eq 'input' && (lc $attr->{'type'}) eq 'hidden';
      }, 'tagname, attr' ],
    end_h   =>	[ sub {
        my($elem) = @_;
        $textarea = undef if $elem eq 'textarea';
      }, 'tagname' ],
    text_h  => 	[ sub {
        return unless ref $textarea;
	$$textarea .= shift;
      }, 'dtext' ] );
  
  my $res = $self->_ua->get($self->_api('action'=>'edit','redirect'=>'no'), 
      ':content_cb' => sub { $p->parse(shift); 1; });
  $p->eof();

  $self->{'_content_ref'} = \$fields{'wpTextbox1'}; delete $fields{'wpTextbox1'};
  foreach(keys %fields) { $self->{'_content_edit_'.$_} = $fields{$_}; };
  $self->{'_content_sha1'} = Digest::SHA1::sha1(${$self->{'_content_ref'}});
}

sub save {
  my($self,$message,$minor) = @_;

  carp 'read only - not editable' unless $self->editable;
  carp 'no change message' unless $message;
  carp 'no content' unless $self->{'_content_sha1'};
  
  # we can't have changed something if there has not been anyting downloaded to change
  return 0 unless $self->{'_content_sha1'};	

  # do nothing if the new and old content are identical
  return 0 if $self->{'_content_sha1'} eq Digest::SHA1::sha1(${$self->{'_content_ref'}});

  my %data = (); foreach(keys %{$self}) {
    $data{$1} = $self->{$_} if m/_content_edit_(.*)/;
  }

  $data{'wpSave'} = 1; $data{'wpMinoredit'} = 1 if $minor;
  $data{'wpSummary'} = $message;
  $data{'wpTextbox1'} = ${$self->{'_content_ref'}};

  my $res = $self->_ua->post($self->_api('action'=>'submit'), \%data);

  if ($res->code >= 301 && $res->code <= 306) { 
    # invalidate hash (=marker whether we have a current version)
    delete $self->{'_content_sha1'}; return 1;
  }
  croak $res->message unless $res->is_success; croak 'update failed';

  
};

1;
