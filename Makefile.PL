# $Id: Makefile.PL,v 0.5.1.1 1997/11/05 09:47:37 ram Exp $
#
#  Copyright (c) 1995-1997, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: Makefile.PL,v $
# Revision 0.5.1.1  1997/11/05  09:47:37  ram
# patch1: updated version number
#
# Revision 0.5  1997/06/10  16:38:37  ram
# Baseline for fifth alpha release.
#

use ExtUtils::MakeMaker;
use Config;

$Version = '0.5_01';

WriteMakefile(
    'NAME'     => 'Storable',
    'DISTNAME' => "Storable",
    'VERSION'  => $Version,
    'dist'      => { SUFFIX => 'gz', COMPRESS => 'gzip -f' },
    'clean' 	=> {'FILES' => '*%'},
);

