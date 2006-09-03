# $Id: Makefile.PL,v 1.2 2006/06/11 14:56:42 cfaerber Exp $
#
#
#

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'WWW::MediaWikiOO',
    'VERSION_FROM'	=> 'lib/WWW/MediaWikiOO.pm', # finds $VERSION
    'PREREQ_PM'		=> {
		'Params::Validate'	=> 0.75,
	},
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      ( #ABSTRACT_FROM => 'lib/WWW/MediaWikiOO.pm', # retrieve abstract from module
       AUTHOR     => 'Claus Färber <perl@faerber.muc.de>') : ()),
);
