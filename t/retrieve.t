#!./perl

# $Id: retrieve.t,v 0.2 1997/01/13 10:53:37 ram Exp $
#
#  Copyright (c) 1995-1997, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: retrieve.t,v $
# Revision 0.2  1997/01/13  10:53:37  ram
# Baseline for second netwide alpha release.
#

chdir 't' if -d 't';
require './dump.pl';

use Storable qw(store retrieve nstore);

print "1..7\n";

$a = 'toto';
$b = \$a;
$c = bless {}, CLASS;
$c->{attribute} = 'attrval';
%a = ('key', 'value', 1, 0, $a, $b, 'cvar', \$c);
@a = ('first', undef, 3, 456, 4.5, $b, \$a, $a, $c, \$c, \%a);

print "not " unless defined store(\@a, 'store');
print "ok 1\n";
print "not " unless defined nstore(\@a, 'nstore');
print "ok 2\n";

$root = retrieve('store');
print "not " unless defined $root;
print "ok 3\n";

$nroot = retrieve('nstore');
print "not " unless defined $nroot;
print "ok 4\n";

$d1 = &dump($root);
print "ok 5\n";
$d2 = &dump($nroot);
print "ok 6\n";

print "not " unless $d1 eq $d2; 
print "ok 7\n";

unlink 'store', 'nstore';

