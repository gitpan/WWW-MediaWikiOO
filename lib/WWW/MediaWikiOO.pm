# $Id: MediaWikiOO.pm,v 1.3 2006/09/03 15:25:13 cfaerber Exp $
#
# WWW::MediaWikiOO - object-orientated interface to MediaWiki sites.
# (c) Copyright 2005 Claus Faerber <perl@faerber.muc.de>
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
package WWW::MediaWikiOO;

our $VERSION = '0.00_20060903';

use utf8;
use strict;
use Carp;

use File::Spec;
use HTML::LinkExtor;
use LWP::UserAgent;
use URI;
use URI::Heuristic;
use URI::QueryParam;

use WWW::MediaWikiOO::Article;

sub new {
  my $pkg = shift;
  my $self = {}; bless($self, $pkg);

  $self->site_uri(shift) if @_;
  $self->logon(@_) if @_;

  return $self;
}

sub _ua {
  my ($self,$new_ua) = @_;
  my $old_ua = $self->{'_ua'};

  if($new_ua) {
  
    carp 'not a LWP::UserAgent' unless UNIVERSAL::isa('LWP::UserAgent',$new_ua);
    $self->{'_ua'} = $new_ua;
    
  } elsif(!$old_ua) {
  
    $new_ua = new LWP::UserAgent(
  	'agent'		=> 'libwww-mediawiki-perl/0.01',
  	'cookie_jar' 	=> {}, );
    return $self->{'_ua'} = $new_ua;

  }

  return $old_ua;
}

my %_api_cache;

sub _api_uri {
  my ($self,$new_api_uri) = @_;
  my $old_api_uri = $self->{'_api_uri'};

  if($new_api_uri) {

    $self->{'_api_uri'} = URI->new($new_api_uri)->canonical;

  } elsif(!$old_api_uri) {

    return $_api_cache{$self->site_uri} if $_api_cache{$self->site_uri};

    my $ok = undef;
    my $lex = undef;
    my $res = $self->_ua->get($self->site_uri, ':content_cb' =>
      sub { 
        unless($lex) {
          my $auth =  new URI($_[1]->base)->canonical->authority;
          $lex = HTML::LinkExtor->new(
            sub {
              my($tag, %attr) = @_;
              return if $tag ne 'a' || !exists $attr{'href'};
              my $nu = URI->new($attr{'href'})->canonical;
   	      if($nu->query_param('title') && $nu->query_param('action') &&
	          $nu->authority eq $auth) {
	        $new_api_uri = $nu->as_string;
		$new_api_uri =~ s/[\?#].*//;
		$new_api_uri = new URI($new_api_uri)->canonical;
	        $ok = 1;die('done');
	      }
            }, $_[1]->base);
        };
        $lex->parse($_[0])
      });
    carp 'cannot determine API URI - '.$res->status_line unless $ok;

    $self->{'_api_uri'} = $new_api_uri;
    $_api_cache{$self->site_uri} = $new_api_uri;
    return $new_api_uri->clone;

  }
  return $old_api_uri->clone;
}

sub _api {
  my($self,%param) = @_;
  my $new = $self->_api_uri;
  $new->query_form(%param);
  return $new;
}

sub site_uri {
  my ($self,$new_site) = @_;
  my $old_site = $self->{'_site_uri'};

  if($new_site)
  {
    my $uri = URI::Heuristic::uf_uri($new_site)->canonical;
    carp 'unsupported uri format - ' .$uri unless $uri->scheme =~ m/^https?/i;
    $self->{'_site_uri'} = $uri;
    $self->{'_api_uri'} = undef;
  }

  return $old_site;
}

sub login {
  my($self,$name,$pass) = @_;

  my $res = $self->_ua->post($self->_api('title'=>'Special:Userlogin','action'=>'submitlogin'),
    { 'wpName' => $name, 'wpRemember' => 1, 'wpPassword' => $pass, 'wpLoginattempt' => 1, } );
  return 1 if ($res->code >= 301 && $res->code <= 306);
  croak $res->message unless $res->is_success;
  croak 'login failed';
}

sub article {
  my ($self,$title) = @_;
  return WWW::MediaWikiOO::Article->new($self,$title);
}

sub edit_article {
  my ($self,$title) = @_;
  return WWW::MediaWikiOO::Article->edit_new($self,$title);
}

sub upload {
  my ($self,$file,$message,%param) = @_;
  $param{'filename'} ||= $file; 
  $param{'filename'} = (File::Spec->splitpath($param{'filename'}))[2];

  croak 'no message' unless $message;
 
  my %data = ();
  $data{'wpUploadFile'}		= (ref $file eq 'ARRAY') ? $file : [$file];
  $data{'wpUploadDescription'}	= $message;
  $data{'wpUploadAffirm'}	= 1;
  $data{'wpUpload'}		= "Upload file";
  $data{'wpIgnoreWarning'}	= 1 if  $param{'overwrite'};
  
  my $res = $self->_ua->post($self->_api('title'=>'Special:Upload'),\%data, 
    'Content_Type' => 'form-data' );
  
  return 1 if ($res->code >= 301 && $res->code <= 306);
  croak $res->message unless $res->is_success;
  croak 'already present: '.$res->message."\n----\n".$res->content."\n----";
}

1;
