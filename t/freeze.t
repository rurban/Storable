#!./perl

# $Id: freeze.t,v 0.5 1997/06/10 16:38:41 ram Exp $
#
#  Copyright (c) 1995-1997, Raphael Manfredi
#  
#  You may redistribute only under the terms of the Artistic License,
#  as specified in the README file that comes with the distribution.
#
# $Log: freeze.t,v $
# Revision 0.5  1997/06/10  16:38:41  ram
# Baseline for fifth alpha release.
#

require 't/dump.pl';

use Storable qw(freeze nfreeze thaw);

print "1..13\n";

$a = 'toto';
$b = \$a;
$c = bless {}, CLASS;
$c->{attribute} = 'attrval';
%a = ('key', 'value', 1, 0, $a, $b, 'cvar', \$c);
@a = ('first', undef, 3, -4, -3.14159, 456, 4.5,
	$b, \$a, $a, $c, \$c, \%a);

print "not " unless defined ($f1 = freeze(\@a));
print "ok 1\n";

$dumped = &dump(\@a);
print "ok 2\n";

$root = thaw($f1);
print "not " unless defined $root;
print "ok 3\n";

$got = &dump($root);
print "ok 4\n";

print "not " unless $got eq $dumped; 
print "ok 5\n";

package FOO; @ISA = qw(Storable);

sub make {
	my $self = bless {};
	$self->{key} = \%main::a;
	return $self;
};

package main;

$foo = FOO->make;
print "not " unless $f2 = $foo->freeze;
print "ok 6\n";

print "not " unless $f3 = $foo->nfreeze;
print "ok 7\n";

$root3 = thaw($f3);
print "not " unless defined $root3;
print "ok 8\n";

print "not " unless &dump($foo) eq &dump($root3);
print "ok 9\n";

$root = thaw($f2);
print "not " unless &dump($foo) eq &dump($root);
print "ok 10\n";

print "not " unless &dump($root3) eq &dump($root);
print "ok 11\n";

$other = freeze($root);
print "not " unless length($other) == length($f2);
print "ok 12\n";

$root2 = thaw($other);
print "not " unless &dump($root2) eq &dump($root);
print "ok 13\n";

