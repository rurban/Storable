# -*- perl -*-

# Test that our declared minimum Perl version matches our syntax
use strict;
BEGIN {
  $|  = 1;
  $^W = 1;
}

my @MODULES = (
  'Perl::MinimumVersion 1.20',
  'Test::MinimumVersion 0.101082',
);

# Don't run tests during end-user installs
use Test::More;
unless (-d '.git' || $ENV{AUTHOR_TESTING}) {
  plan( skip_all => "Author tests not required for installation" );
}

# Load the testing modules
foreach my $MODULE ( @MODULES ) {
  eval "use $MODULE";
  if ( $@ ) {
    plan( skip_all => "$MODULE not available for testing" );
    die "Failed to load required release-testing module $MODULE"
      if -d '.git' || $ENV{AUTHOR_TESTING};
  }
}

# but <5.8 is allowed dynamically
# t/regexp.t skips some parts for <5.14 (stacked labels, qr//p) and <5.22 (qr//n)
all_minimum_version_ok("5.008", { skip => [qw(t/regexp.t)] }); 

1;
