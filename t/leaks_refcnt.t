#!./perl
# [cpan #97316] via Devel::Refcount

use Test::More;
use Storable ();
BEGIN {
  eval "use Devel::Refcount";
  plan 'skip_all' => 'Devel::Refcount required for this test' if $@;
  Devel::Refcount->import('refcount');
}
plan 'tests' => 1;

package TestClass;

sub new {
  my $class = shift;
  return bless({}, $class);
}
sub STORABLE_freeze {
  die;
}

package main;
my $obj = TestClass->new;
my $old = refcount($obj);
eval { freeze($obj); };
is(refcount($obj), $old, "no leak in dying freeze hook RT #97316");
