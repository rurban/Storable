# $Id: Makefile.PL,v 0.1 1995/09/29 20:19:33 ram Exp $
#
#  Copyright (c) 1995, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: Makefile.PL,v $
# Revision 0.1  1995/09/29  20:19:33  ram
# Baseline for first netwide alpha release.
#

use ExtUtils::MakeMaker;
use Config;

$Version = '0.1';

WriteMakefile(
    'NAME'     => 'Storable',
    'DISTNAME' => "Storable",
    'VERSION'  => $Version,
    'dist'      => { SUFFIX => 'gz', COMPRESS => 'gzip -f' },
    'clean' 	=> {'FILES' => '*%'},
);

