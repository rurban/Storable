# $Id: Makefile.PL,v 0.2 1997/01/13 10:53:35 ram Exp $
#
#  Copyright (c) 1995-1997, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: Makefile.PL,v $
# Revision 0.2  1997/01/13  10:53:35  ram
# Baseline for second netwide alpha release.
#

use ExtUtils::MakeMaker;
use Config;

$Version = '0.2';

WriteMakefile(
    'NAME'     => 'Storable',
    'DISTNAME' => "Storable",
    'VERSION'  => $Version,
    'dist'      => { SUFFIX => 'gz', COMPRESS => 'gzip -f' },
    'clean' 	=> {'FILES' => '*%'},
);

