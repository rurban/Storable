# $Id: Makefile.PL,v 0.5.1.7 1998/04/24 14:59:51 ram Exp $
#
#  Copyright (c) 1995-1997, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: Makefile.PL,v $
# Revision 0.5.1.7  1998/04/24  14:59:51  ram
# patch7: increased revision number
#
# Revision 0.5.1.6  1998/04/09  16:05:49  ram
# patch6: increased revision number
#
# Revision 0.5.1.5  1998/04/08  11:12:36  ram
# patch5: increased version number
#
# Revision 0.5.1.4  1998/03/25  13:48:39  ram
# patch4: increased revision minor
#
# Revision 0.5.1.3  1998/01/20  08:21:41  ram
# patch3: don't use any '_' in version number
#
# Revision 0.5.1.2  1998/01/13  16:49:49  ram
# patch2: Updated version number
#
# Revision 0.5.1.1  1997/11/05  09:47:37  ram
# patch1: updated version number
#
# Revision 0.5  1997/06/10  16:38:37  ram
# Baseline for fifth alpha release.
#

use ExtUtils::MakeMaker;
use Config;

$Version = '0.507';

WriteMakefile(
    'NAME'     => 'Storable',
    'DISTNAME' => "Storable",
    'VERSION'  => $Version,
    'dist'      => { SUFFIX => 'gz', COMPRESS => 'gzip -f' },
    'clean' 	=> {'FILES' => '*%'},
);

