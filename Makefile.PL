# $Id: Makefile.PL,v 2.02 2002/05/28 20:22:27 ams Exp $
#
#  Copyright (c) 1995-2000, Raphael Manfredi
#  
#  You may redistribute only under the same terms as Perl 5, as specified
#  in the README file that comes with the distribution.
#
# $Log: Makefile.PL,v $
# Revision 2.02  2002/05/28 20:22:27  ams
# 1. Rework file header handling. (Nicholas Clark)
# 2. Add integer.t and safer integer storing code. (Nicholas Clark)
#
# Revision 2.01  2002/05/21 05:09:32  ams
# 1. Declare correct version for Test::More dependency. (Autrijus Tang)
# 2. Install in core library directory. (Tatsuhiko Miyagawa)
# 3. Mention $canonical in Storable.pm to suppress warning. (Nicholas Clark)
#
# Revision 2.00  2002/05/18 16:00:57  ams
# Import Storable 2.00 from perl-current.
#
# Revision 1.0.1.1  2001/01/03 09:38:39  ram
# patch7: removed spurious 'clean' entry
#
# Revision 1.0  2000/09/01 19:40:41  ram
# Baseline for first official release.
#

use ExtUtils::MakeMaker;
use Config;

WriteMakefile(
    NAME                => 'Storable',
    DISTNAME            => "Storable",
    MAN3PODS            => {},
    PREREQ_PM           => { 'Test::More' => '0.41' },
    INSTALLDIRS         => 'perl',
    VERSION_FROM        => 'Storable.pm',
    dist                => { SUFFIX => 'gz', COMPRESS => 'gzip -f' },
);
