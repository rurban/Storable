# [perl #118139] crash in global destruction when accessing an
# already freed PL_modglobalor accessing the freed cxt.
use Test::More tests => 1;
use Storable;
use vars '$x';
BEGIN {
  store {}, "foo";
}
package foo;
sub new { return bless {} }
DESTROY {
  open $fh, "<", "foo" or die $!;
  eval { Storable::pretrieve($fh); };
  close $fh or die $!;
  unlink "foo";
}

package main;
print "# $^X\n";
$x = foo->new();

ok(1);
