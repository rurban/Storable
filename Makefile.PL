# $Id: Makefile.PL,v 0.4.1.4 1997/02/27 15:31:04 ram Exp $
#
#  Copyright (c) 1995-1997, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: Makefile.PL,v $
# Revision 0.4.1.4  1997/02/27  15:31:04  ram
# patch4: updated version number
#
# Revision 0.4.1.3  1997/02/27  14:57:31  ram
# patch3: updated version number
#
# Revision 0.4.1.2  1997/01/22  14:32:48  ram
# patch2: updated version number
#
# Revision 0.4.1.1  1997/01/22  14:16:43  ram
# patch1: updated version number
#
# Revision 0.4  1997/01/15  18:20:09  ram
# Baseline for fourth netwide alpha release.
#

use ExtUtils::MakeMaker;
use Config;

$Version = '0.4_04';

WriteMakefile(
    'NAME'     => 'Storable',
    'DISTNAME' => "Storable",
    'VERSION'  => $Version,
    'dist'      => { SUFFIX => 'gz', COMPRESS => 'gzip -f' },
    'clean' 	=> {'FILES' => '*%'},
);

