#!./perl

# $Id: lock.t,v 1.0.1.2 2000/10/23 18:03:07 ram Exp $
#
#  Copyright (c) 1995-2000, Raphael Manfredi
#  
#  You may redistribute only under the same terms as Perl 5, as specified
#  in the README file that comes with the distribution.
#
# $Log: lock.t,v $
# Revision 1.0.1.2  2000/10/23 18:03:07  ram
# patch4: protected calls to flock() for dos platform
#
# Revision 1.0.1.1  2000/09/28 21:44:06  ram
# patch2: created.
#
#

use Config;

if ($Config{'osname'} eq 'dos') {
	print "1..0 # Skip: fcntl/flock emulation broken on this platform\n";
	exit 0;
}

require 't/dump.pl';
sub ok;

use Storable qw(lock_store lock_retrieve);

print "1..5\n";

@a = ('first', undef, 3, -4, -3.14159, 456, 4.5);

#
# We're just ensuring things work, we're not validating locking.
#

ok 1, defined lock_store(\@a, 't/store');
ok 2, $dumped = &dump(\@a);

$root = lock_retrieve('t/store');
ok 3, ref $root eq 'ARRAY';
ok 4, @a == @$root;
ok 5, &dump($root) eq $dumped; 

unlink 't/store';

